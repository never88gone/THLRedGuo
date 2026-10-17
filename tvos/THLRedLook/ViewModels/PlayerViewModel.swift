import Foundation
import AVFoundation
import Combine
import SwiftUI

@MainActor
public final class PlayerViewModel: ObservableObject {
    @Published public var player: AVPlayer?
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var currentEpisodeIndex: Int
    @Published public var plan: PlaybackPlan?
    @Published public var selectedQuality: Int = 360
    @Published public var playbackRate: Float = 1.0
    @Published public var danmakuEnabled: Bool = true
    @Published public var activeDanmakus: [DanmakuItem] = []
    @Published public var isControlsVisible: Bool = true
    @Published public var isEpisodeDrawerVisible: Bool = false
    @Published public var isLoading: Bool = true
    @Published public var errorMessage: String?
    @Published public var nextEpisodeCountdown: Int?
    @Published public var relatedSeasons: [Drama] = []
    @Published public var switchSeasonDrama: Drama?

    public let drama: Drama
    @Published public var allEpisodes: [Episode]
    public var keepControlsVisible: Bool = false

    private let repository: NativeRepository
    private let store: LocalStore
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var progressSaveTimer: Timer?
    private var controlsHideTimer: Timer?
    private var danmakuCache: [DanmakuItem] = []
    
    private var prefetchTask: Task<Void, Never>?
    private var prefetchedNextPlan: PlaybackPlan?
    private var prefetchedNextEpisodeIndex: Int?

    public init(
        drama: Drama,
        allEpisodes: [Episode],
        initialEpisodeIndex: Int = 1,
        initialPosition: Double = 0,
        initialShowControls: Bool = true,
        keepControlsVisible: Bool = false,
        initialShowDrawer: Bool = false,
        repository: NativeRepository = .shared,
        store: LocalStore = .shared
    ) {
        self.drama = drama
        self.allEpisodes = allEpisodes
        self.currentEpisodeIndex = initialEpisodeIndex
        self.currentTime = initialPosition
        self.isControlsVisible = initialShowDrawer ? false : initialShowControls
        self.isEpisodeDrawerVisible = initialShowDrawer
        self.keepControlsVisible = keepControlsVisible
        self.repository = repository
        self.store = store

        startProgressSaveTimer()
    }

    deinit {
        // deinit 中清理
    }

    public func onAppear() {
        configureAudioSession()
        Task {
            do {
                let detail = try await self.repository.loadDetail(drama: self.drama)
                if !detail.episodes.isEmpty {
                    self.allEpisodes = detail.episodes
                    NSLog("🎬 [PlayerVM] 动态拉取补全剧集列表，共 %d 集", detail.episodes.count)
                }
            } catch {
                NSLog("🎬 [PlayerVM] 动态补全剧集列表失败: %@", error.localizedDescription)
            }
            
            await loadSeasons()
            await preparePlayback(episodeIndex: currentEpisodeIndex, seekTo: currentTime)
        }
    }

    private func loadSeasons() async {
        let pattern = "第\\s*[0-9零一二两三四五六七八九十百]+\\s*[季部].*$"
        let baseName = drama.title.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !baseName.isEmpty else { return }
        let targetSource = drama.source.lowercased()
        do {
            let result = try await repository.loadCatalog(source: drama.source, query: baseName)
            let filtered = result.items.filter { 
                $0.id != drama.id &&
                $0.source.lowercased() == targetSource &&
                !$0.cover.isEmpty &&
                $0.title.contains(baseName) 
            }.sorted { $0.title < $1.title }
            self.relatedSeasons = filtered
        } catch {
        }
    }

    public func onDisappear() {
        prefetchTask?.cancel()
        prefetchTask = nil
        saveCurrentProgress()
        progressSaveTimer?.invalidate()
        progressSaveTimer = nil
        controlsHideTimer?.invalidate()
        controlsHideTimer = nil
        statusObserver?.invalidate()
        statusObserver = nil
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 忽略会话配置告警
        }
    }

    public func preparePlayback(episodeIndex: Int, seekTo: Double = 0) async {
        configureAudioSession()
        isLoading = true
        errorMessage = nil
        currentEpisodeIndex = episodeIndex
        
        prefetchTask?.cancel()
        prefetchTask = nil

        // 停止并清理前一个播放器会话
        statusObserver?.invalidate()
        statusObserver = nil
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()

        do {
            var currentEp = allEpisodes.indices.contains(episodeIndex - 1) ? allEpisodes[episodeIndex - 1] : nil
            if currentEp == nil || currentEp?.raw == nil {
                if let freshDetail = try? await self.repository.loadDetail(drama: self.drama), !freshDetail.episodes.isEmpty {
                    self.allEpisodes = freshDetail.episodes
                    currentEp = self.allEpisodes.indices.contains(episodeIndex - 1) ? self.allEpisodes[episodeIndex - 1] : nil
                }
            }
            let epId = currentEp?.id ?? "\(episodeIndex)"

            if drama.id.starts(with: "test_") {
                self.isLoading = false
                self.errorMessage = nil
                self.isPlaying = true
                self.duration = 180
                self.currentTime = 35
                return
            }

            // 优先检查本地离线下载文件：若存在已完成的本地视频文件，直接秒播
            if let localURL = DownloadService.shared.completedLocalURL(dramaId: drama.id, episodeId: epId) {
                NSLog("🎬 [PlayerVM] 命中已下载的本地离线文件，直接秒播: %@", localURL.path)
                let asset = AVURLAsset(url: localURL)
                let item = AVPlayerItem(asset: asset)
                startPlaybackWithItem(item: item, seekTo: seekTo)
                return
            }

            let plan: PlaybackPlan
            if let prefetched = self.prefetchedNextPlan, self.prefetchedNextEpisodeIndex == episodeIndex {
                plan = prefetched
                NSLog("🎬 [PlayerVM] 使用提前预加载的播放地址: 第%d集", episodeIndex)
                self.prefetchedNextPlan = nil
                self.prefetchedNextEpisodeIndex = nil
            } else {
                plan = try await repository.resolvePlayback(
                    drama: drama,
                    episode: currentEp,
                    episodeIndex: episodeIndex,
                    quality: selectedQuality
                )
            }
            
            self.plan = plan
            self.selectedQuality = plan.quality

            NSLog("🎬 [PlayerVM] 解析得到播放方案: 剧集=%@, 第%d集, URL=%@, decryptionKey='%@'(长度%ld), headers=%@", drama.title, episodeIndex, plan.url, plan.decryptionKey, plan.decryptionKey.count, String(describing: plan.headers))

            guard let url = URL(string: plan.url) else {
                throw NSError(domain: "Player", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效播放地址"])
            }

            // 若存在 CENC 解密密钥，通过 CENCMP4Decryptor 进行端侧极速解密为标准明文 MP4
            let playbackURL: URL
            var assetOptions: [String: Any] = [:]
            if !plan.decryptionKey.isEmpty {
                NSLog("🎬 [PlayerVM] 检测到 CENC 加密密钥 (%@)，执行本地原生高速解密...", plan.decryptionKey)
                playbackURL = try await CENCMP4Decryptor.shared.decrypt(
                    remoteURL: url,
                    headers: plan.headers,
                    hexKey: plan.decryptionKey
                )
                NSLog("🎬 [PlayerVM] CENC 解密完成，原生播放目标: %@", playbackURL.path)
            } else {
                playbackURL = url
                if !plan.headers.isEmpty {
                    assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = plan.headers
                }
            }

            let asset = AVURLAsset(url: playbackURL, options: assetOptions.isEmpty ? nil : assetOptions)
            let item = AVPlayerItem(asset: asset)
            startPlaybackWithItem(item: item, seekTo: seekTo)

            // 加载弹幕
            if danmakuEnabled {
                await loadDanmaku()
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func startPlaybackWithItem(item: AVPlayerItem, seekTo: Double) {
        let av = AVPlayer(playerItem: item)
        av.automaticallyWaitsToMinimizeStalling = false
        setupTimeObserver(for: av)
        self.player = av
        NSLog("🎬 [PlayerVM] AVPlayer 创建完成并设置到 self.player")

        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] currentItem, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch currentItem.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.isPlaying = true
                    self.errorMessage = nil
                    let dur = currentItem.duration.seconds
                    let pSize = currentItem.presentationSize
                    NSLog("🎬 [PlayerVM] item.readyToPlay: duration=%.2f, presentationSize=%.0fx%.0f, tracksCount=%ld", dur, pSize.width, pSize.height, currentItem.tracks.count)
                    if pSize.width > 0 && pSize.height > 0 {
                        let minDim = min(pSize.width, pSize.height)
                        let realQuality: Int
                        if minDim >= 2160 { realQuality = 2160 }
                        else if minDim >= 1080 { realQuality = 1080 }
                        else if minDim >= 720 { realQuality = 720 }
                        else if minDim >= 480 { realQuality = 480 }
                        else if minDim >= 360 { realQuality = 360 }
                        else { realQuality = Int(minDim) }
                        self.selectedQuality = realQuality
                    }
                    for (idx, track) in currentItem.tracks.enumerated() {
                        let mediaType = track.assetTrack?.mediaType.rawValue ?? "unknown"
                        NSLog("🎬 [PlayerVM] track[%ld]: mediaType=%@, isEnabled=%d", idx, mediaType, track.isEnabled)
                    }
                    if !dur.isNaN && dur > 0 {
                        self.duration = dur
                        if seekTo > 0 {
                            let safeSeek = min(seekTo, max(0, dur - 3.0))
                            if safeSeek > 0 {
                                let cmTime = CMTime(seconds: safeSeek, preferredTimescale: 600)
                                self.player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                            }
                        }
                    }
                    self.player?.playImmediately(atRate: self.playbackRate)
                case .failed:
                    self.isLoading = false
                    let err = currentItem.error?.localizedDescription ?? "视频流加载失败"
                    NSLog("🎬 [PlayerVM] item.failed: %@", err)
                    self.errorMessage = err
                default:
                    break
                }
            }
        }

        // 监听播放完成
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handlePlayEnded()
            }
        }

        player?.automaticallyWaitsToMinimizeStalling = false
        resetControlsHideTimer()
    }

    private func setupTimeObserver(for player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            if let durationSec = player.currentItem?.duration.seconds, !durationSec.isNaN, durationSec > 0 {
                self.duration = durationSec
                
                // 视频结束前提前显示倒计时 (最后 5 秒)
                let remaining = durationSec - time.seconds
                if remaining <= 5.0 && remaining > 0 && self.currentEpisodeIndex < self.allEpisodes.count {
                    let countdownValue = Int(ceil(remaining))
                    if self.nextEpisodeCountdown != countdownValue {
                        self.nextEpisodeCountdown = countdownValue
                    }
                    
                    // 提前加载下一集信息
                    if self.prefetchTask == nil {
                        self.prefetchNextEpisodePlan()
                    }
                } else {
                    if self.nextEpisodeCountdown != nil && remaining > 5.0 {
                        self.nextEpisodeCountdown = nil
                    }
                }
            }
            self.updateActiveDanmakus()
        }
    }
    
    private func prefetchNextEpisodePlan() {
        let nextIndex = currentEpisodeIndex + 1
        guard nextIndex <= allEpisodes.count else { return }
        
        prefetchTask = Task {
            do {
                let nextEp = allEpisodes.indices.contains(nextIndex - 1) ? allEpisodes[nextIndex - 1] : nil
                let plan = try await repository.resolvePlayback(
                    drama: drama,
                    episode: nextEp,
                    episodeIndex: nextIndex,
                    quality: selectedQuality
                )
                if !Task.isCancelled {
                    self.prefetchedNextPlan = plan
                    self.prefetchedNextEpisodeIndex = nextIndex
                    NSLog("🎬 [PlayerVM] 成功提前加载第%d集的播放方案", nextIndex)
                }
            } catch {
                NSLog("🎬 [PlayerVM] 提前加载下一集失败: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - 控制与遥控器交互
    public func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
        showControls()
    }

    public func seekBy(seconds: Double) {
        guard let p = player else { return }
        let target = max(0, min(currentTime + seconds, duration))
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        p.seek(to: cmTime)
        currentTime = target
        showControls()
    }

    public func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        showControls()
    }

    public func changeQuality(_ q: Int) async {
        guard q != selectedQuality else { return }
        selectedQuality = q
        let currentPos = currentTime
        await preparePlayback(episodeIndex: currentEpisodeIndex, seekTo: currentPos)
    }

    public func nextEpisode() async {
        guard currentEpisodeIndex < allEpisodes.count else { return }
        saveCurrentProgress()
        await preparePlayback(episodeIndex: currentEpisodeIndex + 1, seekTo: 0)
    }

    public func previousEpisode() async {
        guard currentEpisodeIndex > 1 else { return }
        saveCurrentProgress()
        await preparePlayback(episodeIndex: currentEpisodeIndex - 1, seekTo: 0)
    }

    public func selectEpisode(number: Int) async {
        NSLog("🎬 [PlayerVM] selectEpisode 调用: 目标第%d集, 当前第%d集", number, currentEpisodeIndex)
        isEpisodeDrawerVisible = false
        guard number != currentEpisodeIndex else { return }
        saveCurrentProgress()
        await preparePlayback(episodeIndex: number, seekTo: 0)
    }

    public func toggleDanmaku() {
        danmakuEnabled.toggle()
        if !danmakuEnabled {
            activeDanmakus = []
        }
    }

    public func showControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isControlsVisible = true
        }
        resetControlsHideTimer()
    }

    public func hideControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isControlsVisible = false
        }
        controlsHideTimer?.invalidate()
    }

    private func resetControlsHideTimer() {
        guard !keepControlsVisible else { return }
        controlsHideTimer?.invalidate()
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                if self?.isPlaying == true {
                    self?.isControlsVisible = false
                }
            }
        }
    }

    // MARK: - 弹幕管理
    private func loadDanmaku() async {
        guard let plan = plan else { return }
        do {
            danmakuCache = try await repository.loadDanmaku(plan: plan, startMs: 0, durationMs: 120_000)
        } catch {
            danmakuCache = []
        }
    }

    private func updateActiveDanmakus() {
        guard danmakuEnabled else { return }
        let currentMs = Int64(currentTime * 1000)
        activeDanmakus = danmakuCache.filter { item in
            item.timeMs >= currentMs - 2000 && item.timeMs <= currentMs + 2000
        }
    }

    // MARK: - 连播与进度持久化
    private func handlePlayEnded() async {
        if currentEpisodeIndex < allEpisodes.count {
            nextEpisodeCountdown = nil
            await nextEpisode()
        }
    }

    private func startProgressSaveTimer() {
        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.saveCurrentProgress()
            }
        }
    }

    public func saveCurrentProgress() {
        guard duration > 0 else { return }
        store.recordWatch(drama: drama, episode: currentEpisodeIndex, position: currentTime, duration: duration)
    }
}
