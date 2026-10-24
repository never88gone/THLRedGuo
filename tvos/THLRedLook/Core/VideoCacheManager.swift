import Foundation
import AVFoundation

/// 视频播放器缓存与后台预热管理器（参考 thldytv 原生 TVOS 实现）
/// 具备 namespace 隔离、LRU 实例淘汰、以及关键的“后台静音预热 3 秒媒体分片”能力，
/// 消除切集与切推荐视频时的等待与转圈，实现真正的毫秒级秒开起播。
public final class VideoCacheManager: NSObject {
    public static let shared = VideoCacheManager()

    // 播放器实例池，key 为 "\(namespace)_\(urlString)"
    private var players: [String: AVPlayer] = [:]
    private var taskHistory: [String] = [] // LRU 队列
    private let queue = DispatchQueue(label: "com.thlredlook.videocachemanager", qos: .userInitiated)

    // 后台静音预热队列：每次只预热一条，避免抢占当前视频带宽
    private var warmupQueue: [String] = []
    private var activeWarmupKey: String?
    private var warmupTimer: DispatchWorkItem?
    private var warmupObservation: NSKeyValueObservation?
    private let warmupBufferDuration: Double = 3.0

    private override init() {
        super.init()
    }

    // MARK: - 获取或创建播放器 (带 namespace 隔离)

    public func getPlayer(for urlString: String, headers: [String: String] = [:], namespace: String = "default") -> AVPlayer {
        return queue.sync {
            let key = "\(namespace)_\(urlString)"
            if let existingPlayer = players[key], existingPlayer.currentItem != nil {
                updateLRU(key, namespace: namespace)
                return existingPlayer
            }

            let player = createPlayer(for: urlString, headers: headers)
            players[key] = player
            updateLRU(key, namespace: namespace)
            trimPlayers(for: namespace)
            return player
        }
    }

    func cachedPlayer(for urlString: String, namespace: String) -> AVPlayer? {
        queue.sync {
            let key = "\(namespace)_\(urlString)"
            guard let player = players[key], player.currentItem != nil else { return nil }
            updateLRU(key, namespace: namespace)
            return player
        }
    }

    private func createPlayer(for urlString: String, headers: [String: String]) -> AVPlayer {
        guard let url = URL(string: urlString) else {
            return AVPlayer()
        }

        var options: [String: Any] = [:]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }

        let asset = AVURLAsset(url: url, options: options.isEmpty ? nil : options)
        let item = AVPlayerItem(asset: asset)

        item.audioTimePitchAlgorithm = .timeDomain
        item.preferredForwardBufferDuration = 10.0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        return player
    }

    func preload(asset: AVURLAsset, for urlString: String, namespace: String) {
        queue.sync {
            let key = "\(namespace)_\(urlString)"
            if players[key] == nil {
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 3
                let player = AVPlayer(playerItem: item)
                player.automaticallyWaitsToMinimizeStalling = true
                players[key] = player
                updateLRU(key, namespace: namespace)
                trimPlayers(for: namespace)
            }
            enqueueWarmup(keys: [key])
        }
    }

    // MARK: - LRU 队列更新与淘汰

    private func updateLRU(_ key: String, namespace: String) {
        if let index = taskHistory.firstIndex(of: key) {
            taskHistory.remove(at: index)
        }
        taskHistory.append(key)
    }

    private func trimPlayers(for namespace: String) {
        let keysInNamespace = taskHistory.filter { $0.hasPrefix("\(namespace)_") }
        let maxCount = 5 // 限制当前 namespace 下保留最多 5 个播放器实例

        if keysInNamespace.count > maxCount {
            let excess = keysInNamespace.count - maxCount
            let toRemove = Array(keysInNamespace.prefix(excess))

            for key in toRemove {
                if key == activeWarmupKey {
                    finishWarmup(for: key, restoreAudio: false)
                }
                warmupQueue.removeAll { $0 == key }
                if let idx = taskHistory.firstIndex(of: key) {
                    taskHistory.remove(at: idx)
                }
                if let oldPlayer = players.removeValue(forKey: key) {
                    DispatchQueue.main.async {
                        oldPlayer.pause()
                        oldPlayer.currentItem?.asset.cancelLoading()
                        oldPlayer.replaceCurrentItem(with: nil)
                    }
                }
            }
        }
    }

    // MARK: - 预加载与静音预热 (Prewarm)

    /// 预加载多个候选视频，首个为即将播放项，其余按顺序入队静音预热
    public func preload(items: [(url: String, headers: [String: String])], namespace: String = "default") {
        queue.async {
            guard !items.isEmpty else { return }

            var keysToWarmup: [String] = []
            for item in items {
                guard !item.url.isEmpty else { continue }
                let key = "\(namespace)_\(item.url)"
                if self.players[key] == nil {
                    let player = self.createPlayer(for: item.url, headers: item.headers)
                    self.players[key] = player
                    self.updateLRU(key, namespace: namespace)
                }
                keysToWarmup.append(key)
            }
            self.trimPlayers(for: namespace)

            // 将后续项排入后台预热队列
            self.enqueueWarmup(keys: keysToWarmup)
        }
    }

    private func enqueueWarmup(keys: [String]) {
        guard !keys.isEmpty else { return }
        for key in keys where key != activeWarmupKey && !warmupQueue.contains(key) {
            warmupQueue.append(key)
        }
        startNextWarmupIfNeeded()
    }

    private func startNextWarmupIfNeeded() {
        guard activeWarmupKey == nil else { return }

        while !warmupQueue.isEmpty {
            let key = warmupQueue.removeFirst()
            guard let player = players[key], let item = player.currentItem else { continue }

            activeWarmupKey = key
            item.preferredForwardBufferDuration = warmupBufferDuration
            player.isMuted = true
            player.automaticallyWaitsToMinimizeStalling = false

            warmupObservation = item.observe(\.loadedTimeRanges, options: [.new, .initial]) { [weak self] item, _ in
                self?.queue.async {
                    guard let self,
                          self.activeWarmupKey == key,
                          self.bufferedDuration(for: item) >= self.warmupBufferDuration else { return }
                    self.finishWarmup(for: key, restoreAudio: false)
                }
            }

            // 关键：不使用在 tvOS 容易失败的 preroll，直接以静音模式在后台 playImmediately 真实拉取前 3 秒分片
            player.playImmediately(atRate: 1.0)

            let timeout = DispatchWorkItem { [weak self] in
                self?.finishWarmup(for: key, restoreAudio: false)
            }
            warmupTimer = timeout
            queue.asyncAfter(deadline: .now() + 4.0, execute: timeout)
            return
        }
    }

    private func bufferedDuration(for item: AVPlayerItem) -> Double {
        guard let range = item.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        let end = CMTimeGetSeconds(CMTimeAdd(range.start, range.duration))
        return max(0, end - CMTimeGetSeconds(item.currentTime()))
    }

    private func finishWarmup(for key: String, restoreAudio: Bool) {
        guard activeWarmupKey == key else { return }

        warmupTimer?.cancel()
        warmupTimer = nil
        warmupObservation?.invalidate()
        warmupObservation = nil

        if let player = players[key] {
            player.pause()
            // 静音预热会推进少量播放时间，拉取成功后归零，保证用户切入时从第 0 秒无缝起播
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.automaticallyWaitsToMinimizeStalling = true
            if restoreAudio {
                player.isMuted = false
            }
        }
        activeWarmupKey = nil
        startNextWarmupIfNeeded()
    }

    // MARK: - 视频聚焦 (切入前台起播)

    /// 当用户选中/滑到该视频时调用：取消该条后台预热、解除静音、提升 LRU 优先级
    public func focusOnVideo(urlString: String, namespace: String = "default") {
        queue.async {
            let key = "\(namespace)_\(urlString)"
            if key == self.activeWarmupKey {
                self.finishWarmup(for: key, restoreAudio: true)
                self.players[key]?.automaticallyWaitsToMinimizeStalling = true
            } else {
                self.warmupQueue.removeAll { $0 == key }
                self.players[key]?.isMuted = false
                self.players[key]?.automaticallyWaitsToMinimizeStalling = true
                self.updateLRU(key, namespace: namespace)
            }
        }
    }

    // MARK: - 资源释放

    public func clearNamespace(_ namespace: String) {
        queue.async {
            let keys = self.players.keys.filter { $0.hasPrefix("\(namespace)_") }
            for key in keys {
                if key == self.activeWarmupKey {
                    self.finishWarmup(for: key, restoreAudio: false)
                }
                self.warmupQueue.removeAll { $0 == key }
                if let idx = self.taskHistory.firstIndex(of: key) {
                    self.taskHistory.remove(at: idx)
                }
                if let player = self.players.removeValue(forKey: key) {
                    DispatchQueue.main.async {
                        player.pause()
                        player.currentItem?.asset.cancelLoading()
                        player.replaceCurrentItem(with: nil)
                    }
                }
            }
        }
    }

    public func clearAll() {
        queue.async {
            self.warmupQueue.removeAll()
            if let activeKey = self.activeWarmupKey {
                self.finishWarmup(for: activeKey, restoreAudio: false)
            }
            let all = Array(self.players.values)
            self.players.removeAll()
            self.taskHistory.removeAll()

            DispatchQueue.main.async {
                for p in all {
                    p.pause()
                    p.currentItem?.asset.cancelLoading()
                    p.replaceCurrentItem(with: nil)
                }
            }
        }
    }
}
