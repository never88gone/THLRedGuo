import Foundation
import AVFoundation
import Combine
import SwiftUI

@MainActor
public final class PlayerViewModel: ObservableObject {
    @Published public var player: AVPlayer?
    @Published public var isPlaying: Bool = false
    @Published public private(set) var wantsPlayback: Bool = true
    @Published public private(set) var isBuffering: Bool = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var currentEpisodeIndex: Int
    @Published public var plan: PlaybackPlan?
    @Published public var selectedQuality: Int = 360
    @Published public var playbackRate: Float = 1.0
    @Published public var danmakuEnabled: Bool = true
    @Published public var danmakuStyle: TVDanmakuStyle = TVDanmakuStyle()
    @Published public var activeDanmakus: [DanmakuItem] = []
    @Published public var isControlsVisible: Bool = true
    @Published public var isEpisodeDrawerVisible: Bool = false
    @Published public var isDanmakuSettingsVisible: Bool = false
    @Published public var isSpeedSheetVisible: Bool = false
    @Published public var isLoading: Bool = true
    @Published public var isSeamlessTransitioning: Bool = false
    @Published public var errorMessage: String?
    @Published public var toastMessage: String?
    @Published public var nextEpisodeCountdown: Int?
    @Published public var relatedSeasons: [Drama] = []
    @Published public var switchSeasonDrama: Drama?
    public var restoreFocusTarget: PlayerOverlayFocusTarget?

    @Published public private(set) var drama: Drama
    @Published public var allEpisodes: [Episode]
    public var keepControlsVisible: Bool = false

    private let repository: NativeRepository
    private let store: LocalStore
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var isSeeking = false
    private var seekSequence = 0
    private var isSceneActive = true
    private var resumeAfterInterruption = false
    private var reachedEnd = false
    private var progressSaveTimer: Timer?
    private var controlsHideTimer: Timer?
    private var toastHideTimer: Timer?
    private var bufferingDebounceTimer: Timer?
    private var danmakuCache: [DanmakuItem] = []
    private var danmakuPages: [Int64: [DanmakuItem]] = [:]
    private var danmakuRetryAfter: [Int64: Date] = [:]
    private var danmakuTask: Task<Void, Never>?
    private var danmakuRequestSequence = 0
    public private(set) var playbackClockDate = Date()
    
    private struct PreloadedEpisode {
        let episodeIndex: Int
        let plan: PlaybackPlan
        let playerItem: AVPlayerItem
        let decryptedURL: URL?
    }
    private var prefetchTask: Task<Void, Never>?
    private var preloadedEpisode: PreloadedEpisode?
    private var identityVerified = false
    private var lifecycleTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var playbackGeneration = 0
    private var isVisible = false
    private var closed = false
    private var playIntent: Bool {
        get { wantsPlayback }
        set { wantsPlayback = newValue }
    }
    private var recoveryAttempts = 0
    private var failedURL = ""
    private var decryptedURL: URL?
    private var itemNotifications: [NSObjectProtocol] = []
    private var initializationTimer: Timer?
    private var healthTimer: Timer?
    private var lastProgressTime = Date()
    private var lastObservedPosition = 0.0
    private static let audioSessionQueue = DispatchQueue(label: "THLRedLook.AudioSession")
    private let initialPreloadedPlan: PlaybackPlan?

    public init(
        drama: Drama,
        allEpisodes: [Episode],
        initialEpisodeIndex: Int = 1,
        initialPosition: Double = 0,
        initialShowControls: Bool = false,
        keepControlsVisible: Bool = false,
        initialShowDrawer: Bool = false,
        initialRestoreFocusTarget: PlayerOverlayFocusTarget? = nil,
        preloadedPlan: PlaybackPlan? = nil,
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
        self.restoreFocusTarget = initialRestoreFocusTarget
        self.initialPreloadedPlan = preloadedPlan
        self.repository = repository
        self.store = store
        self.danmakuEnabled = store.danmakuEnabled
        self.danmakuStyle = store.danmakuStyle

        startProgressSaveTimer()
    }

    public func restoreSavedProgress() {
        guard !isVisible, let entry = store.getWatchEntry(dramaId: drama.id) else { return }
        currentEpisodeIndex = entry.episode
        currentTime = entry.position
        duration = entry.duration
    }

    public func onAppear() {
        guard !isVisible else { return }
        isVisible = true
        closed = false
        if progressSaveTimer == nil { startProgressSaveTimer() }

        // 若外部已提前预加载就绪，0ms 瞬间挂载起播，彻底杜绝转圈等待
        if let preloaded = self.initialPreloadedPlan,
           let poolPlayer = VideoCacheManager.shared.cachedPlayer(for: preloaded.url, namespace: "feed") {
            self.plan = preloaded
            self.selectedQuality = preloaded.quality
            VideoCacheManager.shared.focusOnVideo(urlString: preloaded.url, namespace: "feed")
            self.startPlaybackWithPlayer(poolPlayer, seekTo: self.currentTime)
            self.isLoading = false
            NSLog("🎬 [PlayerVM] onAppear 命中预载方案(%@)，实现秒开起播", self.drama.title)

            lifecycleTask = Task { [weak self] in
                guard let self, !self.drama.id.starts(with: "test_") else { return }
                if self.allEpisodes.isEmpty {
                    if let detail = try? await self.repository.loadDetail(drama: self.drama, store: self.store) {
                        guard !Task.isCancelled, !self.closed else { return }
                        self.allEpisodes = detail.episodes
                    }
                }
                await self.loadSeasons()
            }
            return
        }

        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            if !self.drama.id.starts(with: "test_") {
                do {
                    let detail = try await repository.loadDetail(drama: drama, store: store)
                    guard !Task.isCancelled, !closed else { return }
                    drama = detail.drama
                    identityVerified = true
                    if !detail.episodes.isEmpty { allEpisodes = detail.episodes }
                } catch {
                    guard !Task.isCancelled, !closed else { return }
                }
            }
            await preparePlayback(episodeIndex: currentEpisodeIndex, seekTo: currentTime)
            guard !Task.isCancelled, !closed else { return }
            if !self.drama.id.starts(with: "test_") {
                await loadSeasons()
            }
        }
    }

    private func loadSeasons() async {
        let pattern = "第\\s*[0-9零一二两三四五六七八九十百]+\\s*[季部].*$"
        let baseName = drama.title.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !baseName.isEmpty else { return }
        let targetSource = drama.source.lowercased()
        let requestedId = drama.id
        do {
            let result = try await repository.loadCatalog(source: drama.source, query: baseName)
            guard !closed, !Task.isCancelled, drama.id == requestedId else { return }
            store.refreshDramas(result.items)
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
        closed = true
        resumeAfterInterruption = false
        isVisible = false
        playbackGeneration += 1
        lifecycleTask?.cancel()
        lifecycleTask = nil
        preparationTask?.cancel()
        preparationTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        if let preloaded = preloadedEpisode {
            if let dec = preloaded.decryptedURL, dec != decryptedURL {
                CENCMP4Decryptor.shared.removePlaybackCache(at: dec)
            }
            preloadedEpisode = nil
        }
        saveCurrentProgress()
        progressSaveTimer?.invalidate()
        progressSaveTimer = nil
        controlsHideTimer?.invalidate()
        controlsHideTimer = nil
        toastHideTimer?.invalidate()
        toastHideTimer = nil
        releasePlayer()
        plan = nil
    }

    private func releasePlayer() {
        resetDanmaku()
        initializationTimer?.invalidate()
        initializationTimer = nil
        healthTimer?.invalidate()
        healthTimer = nil
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        seekSequence += 1
        isSeeking = false
        itemNotifications.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotifications.removeAll()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        if initialPreloadedPlan == nil {
            player?.replaceCurrentItem(with: nil)
        }
        player = nil
        isPlaying = false
        isBuffering = false
        if let url = decryptedURL {
            CENCMP4Decryptor.shared.removePlaybackCache(at: url)
            decryptedURL = nil
        }
    }

    private func configureAudioSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.audioSessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .moviePlayback)
                    try session.setActive(true)
                } catch {}
                continuation.resume()
            }
        }
    }

    public func showToast(_ message: String) {
        toastHideTimer?.invalidate()
        toastMessage = message
        toastHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.toastMessage = nil
                }
            }
        }
    }

    public func preparePlayback(episodeIndex: Int, seekTo: Double = 0) async {
        await beginPlayback(episodeIndex: episodeIndex, seekTo: seekTo, recovering: false)
    }

    public func switchFeedDrama(
        drama: Drama,
        allEpisodes: [Episode]? = nil,
        initialEpisodeIndex: Int = 1,
        initialPosition: Double = 0,
        preloadedPlan: PlaybackPlan? = nil
    ) async {
        guard !closed else { return }
        saveCurrentProgress()
        playbackGeneration += 1

        prefetchTask?.cancel()
        prefetchTask = nil
        if let cached = preloadedEpisode, let url = cached.decryptedURL, url != decryptedURL {
            CENCMP4Decryptor.shared.removePlaybackCache(at: url)
        }
        preloadedEpisode = nil
        identityVerified = false
        self.drama = drama
        self.allEpisodes = allEpisodes ?? []
        self.currentEpisodeIndex = initialEpisodeIndex
        self.currentTime = max(0, initialPosition)
        self.duration = 0
        self.errorMessage = nil
        self.isSeamlessTransitioning = true // 保持当前画面最后一帧，无黑闪

        if let plan = preloadedPlan,
           let poolPlayer = VideoCacheManager.shared.cachedPlayer(for: plan.url, namespace: "feed") {
            self.plan = plan
            self.selectedQuality = plan.quality
            VideoCacheManager.shared.focusOnVideo(urlString: plan.url, namespace: "feed")
            startPlaybackWithPlayer(poolPlayer, seekTo: initialPosition)
            NSLog("🎬 [PlayerVM] switchFeedDrama 命中全链路预载(%@)，实现秒开起播", drama.title)
            return
        }

        await preparePlayback(episodeIndex: initialEpisodeIndex, seekTo: initialPosition)
        self.isSeamlessTransitioning = false
    }

    private func beginPlayback(episodeIndex: Int, seekTo: Double, recovering: Bool, preservePlayIntent: Bool = false) async {
        guard !closed, episodeIndex > 0, seekTo.isFinite else { return }
        saveCurrentProgress()
        preparationTask?.cancel()
        recoveryTask?.cancel()
        recoveryTask = nil

        if let task = prefetchTask, episodeIndex == currentEpisodeIndex + 1 {
            _ = await task.value
        } else {
            prefetchTask?.cancel()
            prefetchTask = nil
        }

        playbackGeneration += 1
        let generation = playbackGeneration
        if !recovering {
            recoveryAttempts = 0
            failedURL = ""
            if !preservePlayIntent {
                playIntent = isSceneActive
                resumeAfterInterruption = !isSceneActive
            }
        }
        reachedEnd = false

        if !recovering, let preloaded = preloadedEpisode, preloaded.episodeIndex == episodeIndex {
            preloadedEpisode = nil
            currentEpisodeIndex = episodeIndex
            currentTime = max(0, seekTo)
            duration = 0
            nextEpisodeCountdown = nil
            errorMessage = nil
            plan = preloaded.plan
            selectedQuality = preloaded.plan.quality
            if let oldDec = decryptedURL, oldDec != preloaded.decryptedURL {
                CENCMP4Decryptor.shared.removePlaybackCache(at: oldDec)
            }
            decryptedURL = preloaded.decryptedURL

            guard !closed, generation == playbackGeneration, !Task.isCancelled else {
                if let dec = preloaded.decryptedURL {
                    CENCMP4Decryptor.shared.removePlaybackCache(at: dec)
                }
                return
            }
            startPlaybackWithItem(item: preloaded.playerItem, seekTo: seekTo)
            NSLog("🎬 [PlayerVM] 命中第%d集全链路预热，实现无缝秒开起播", episodeIndex)
            updateActiveDanmakus()
            return
        }

        if let preloaded = preloadedEpisode {
            if let dec = preloaded.decryptedURL, dec != decryptedURL {
                CENCMP4Decryptor.shared.removePlaybackCache(at: dec)
            }
            preloadedEpisode = nil
        }

        releasePlayerObservers()
        if !isSeamlessTransitioning {
            player?.pause()
            await configureAudioSession()
        }
        guard !closed, generation == playbackGeneration, !Task.isCancelled else { return }
        currentEpisodeIndex = episodeIndex
        currentTime = max(0, seekTo)
        duration = 0
        nextEpisodeCountdown = nil
        if !isSeamlessTransitioning {
            isLoading = true
        }
        errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.prepareEpisode(episodeIndex: episodeIndex, seekTo: seekTo, generation: generation, recovering: recovering)
        }
        preparationTask = task
        await task.value
        if generation == playbackGeneration { preparationTask = nil }
    }

    private func prepareEpisode(episodeIndex: Int, seekTo: Double, generation: Int, recovering: Bool) async {
        func current() -> Bool { !closed && !Task.isCancelled && generation == playbackGeneration }
        if drama.id.starts(with: "test_") {
            isLoading = false
            isPlaying = true
            duration = 180
            currentTime = 35
            let testQuality = selectedQuality > 0 ? selectedQuality : 1080
            selectedQuality = testQuality
            plan = PlaybackPlan(
                url: "http://localhost/test.mp4",
                quality: testQuality,
                qualities: [1080, 720, 480]
            )
            errorMessage = nil
            recoveryAttempts = 0
            return
        }
        do {
            var episode = allEpisodes.first { $0.number == episodeIndex }
            if episode?.raw == nil || (!identityVerified && HongguoSeriesIdentity.isRounded(drama)) {
                let detail = try await repository.loadDetail(drama: drama, store: store)
                guard current() else { return }
                drama = detail.drama
                identityVerified = true
                allEpisodes = detail.episodes
                episode = allEpisodes.first { $0.number == episodeIndex }
            }
            guard let episode else {
                throw NSError(domain: "Player", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有找到当前分集，请重新加载剧集详情"])
            }
            if let localURL = DownloadService.shared.completedLocalURL(dramaId: drama.id, episodeId: episode.id) {
                startPlaybackWithItem(item: AVPlayerItem(url: localURL), seekTo: seekTo)
                return
            }
            let resolved = try await repository.resolvePlayback(drama: drama, episode: episode, episodeIndex: episodeIndex, quality: selectedQuality, avoidURL: failedURL)
            guard current() else { return }
            plan = resolved
            selectedQuality = resolved.quality
            guard let scheme = URL(string: resolved.url)?.scheme, ["https", "http", "file"].contains(scheme) else {
                throw NSError(domain: "Player", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效播放地址"])
            }
            let prepared = try await PlaybackAssetFactory.prepare(resolved)
            guard current() else {
                if let local = prepared.decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: local) }
                return
            }
            if let old = decryptedURL, old != prepared.decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: old) }
            decryptedURL = prepared.decryptedURL
            startPlaybackWithItem(item: AVPlayerItem(asset: prepared.asset), seekTo: seekTo)
            NSLog("[PlayerVM] prepared episode=%d encrypted=%d recovery=%d", episodeIndex, resolved.decryptionKey.isEmpty ? 0 : 1, recoveryAttempts)
            updateActiveDanmakus()
        } catch {
            guard current(), !(error is CancellationError) else { return }
            requestRecovery(reason: error.localizedDescription)
        }
    }

    func requestRecovery(reason: String) {
        guard !closed, !reachedEnd, recoveryTask == nil else { return }
        guard recoveryAttempts < 5 else {
            initializationTimer?.invalidate()
            healthTimer?.invalidate()
            player?.pause()
            isPlaying = false
            isBuffering = false
            isLoading = false
            errorMessage = "当前分集重试后仍无法播放，请稍后重试。\n" + reason
            return
        }
        recoveryAttempts += 1
        failedURL = plan?.url ?? failedURL
        let episode = currentEpisodeIndex
        let playerTime = player?.currentTime().seconds ?? 0
        let position = max(currentTime, playerTime.isFinite ? playerTime : 0)
        isLoading = true
        errorMessage = nil
        NSLog("[PlayerVM] recovering episode=%d attempt=%d", episode, recoveryAttempts)
        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard let self, !closed, !Task.isCancelled else { return }
            recoveryTask = nil
            await beginPlayback(episodeIndex: episode, seekTo: position, recovering: true)
        }
    }

    func startPlaybackWithItem(item: AVPlayerItem, seekTo: Double) {
        item.preferredForwardBufferDuration = 3
        releasePlayerObservers()
        let av: AVPlayer
        if let existing = player {
            existing.replaceCurrentItem(with: item)
            av = existing
        } else {
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            player = newPlayer
            av = newPlayer
        }
        attachObservers(to: av, item: item, seekTo: seekTo)
    }

    func startPlaybackWithPlayer(_ cachedPlayer: AVPlayer, seekTo: Double) {
        releasePlayerObservers()
        cachedPlayer.isMuted = false
        cachedPlayer.automaticallyWaitsToMinimizeStalling = true
        self.player = cachedPlayer
        if let item = cachedPlayer.currentItem {
            attachObservers(to: cachedPlayer, item: item, seekTo: seekTo)
        }
    }

    private func attachObservers(to av: AVPlayer, item: AVPlayerItem, seekTo: Double) {
        isSeeking = seekTo > 0
        let generation = playbackGeneration
        timeControlObserver = av.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak av] _, _ in
            Task { @MainActor in
                guard let self, let av, self.player === av, generation == self.playbackGeneration, !self.closed else { return }
                let playing = self.playIntent && self.isSceneActive && av.timeControlStatus == .playing
                let buffering = self.playIntent && self.isSceneActive && av.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.isPlaying = playing
                if playing {
                    self.bufferingDebounceTimer?.invalidate()
                    self.bufferingDebounceTimer = nil
                    self.isBuffering = false
                    self.isSeamlessTransitioning = false
                } else if buffering && !self.isSeamlessTransitioning {
                    if self.bufferingDebounceTimer == nil {
                        self.bufferingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                            Task { @MainActor in
                                guard let self, self.player === av, generation == self.playbackGeneration, !self.closed else { return }
                                if self.playIntent && self.isSceneActive && av.timeControlStatus == .waitingToPlayAtSpecifiedRate && !self.isSeamlessTransitioning {
                                    self.isBuffering = true
                                }
                            }
                        }
                    }
                } else {
                    self.bufferingDebounceTimer?.invalidate()
                    self.bufferingDebounceTimer = nil
                    self.isBuffering = false
                }
                self.samplePlaybackClock()
                self.updateActiveDanmakus()
            }
        }
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak av] observed, _ in
            Task { @MainActor in
                guard let self, let av, self.player === av, generation == self.playbackGeneration, !self.closed else { return }
                switch observed.status {
                case .readyToPlay:
                    self.errorMessage = nil
                    let seconds = observed.duration.seconds
                    if seconds.isFinite && seconds > 0 { self.duration = seconds }
                    let size = observed.presentationSize
                    if min(size.width, size.height) > 0 { self.selectedQuality = Int(min(size.width, size.height)) }
                    if seekTo > 0, self.duration > 0 {
                        let position = min(seekTo, max(0, self.duration - 1))
                        await av.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        guard self.player === av, generation == self.playbackGeneration, !self.closed else { return }
                        self.currentTime = position
                    }
                    self.isSeeking = false
                    self.initializationTimer?.invalidate()
                    self.isLoading = false
                    self.isSeamlessTransitioning = false
                    self.samplePlaybackClock()
                    self.lastProgressTime = Date()
                    if self.playIntent && self.isSceneActive { av.playImmediately(atRate: self.playbackRate) }
                    NSLog("[PlayerVM] ready episode=%d duration=%.2f tracks=%d", self.currentEpisodeIndex, self.duration, observed.tracks.count)
                case .failed:
                    self.isSeamlessTransitioning = false
                    self.requestRecovery(reason: observed.error?.localizedDescription ?? "视频流加载失败")
                default:
                    break
                }
            }
        }
        if item.status == .readyToPlay {
            self.errorMessage = nil
            let seconds = item.duration.seconds
            if seconds.isFinite && seconds > 0 { self.duration = seconds }
            let size = item.presentationSize
            if min(size.width, size.height) > 0 { self.selectedQuality = Int(min(size.width, size.height)) }
            if seekTo > 0, self.duration > 0 {
                let position = min(seekTo, max(0, self.duration - 1))
                Task {
                    await av.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    guard self.player === av, generation == self.playbackGeneration, !self.closed else { return }
                    self.currentTime = position
                    self.isSeeking = false
                    self.samplePlaybackClock()
                    self.lastProgressTime = Date()
                    if self.playIntent && self.isSceneActive { av.playImmediately(atRate: self.playbackRate) }
                }
            } else {
                self.isSeeking = false
                self.samplePlaybackClock()
                self.lastProgressTime = Date()
                if self.playIntent && self.isSceneActive { av.playImmediately(atRate: self.playbackRate) }
            }
            self.isLoading = false
            self.isSeamlessTransitioning = false
        }
        timeObserverToken = av.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak av] time in
            Task { @MainActor in
                guard let self, let av, self.player === av, generation == self.playbackGeneration, !self.closed, !self.isSeeking else { return }
                let seconds = av.currentTime().seconds
                guard seconds.isFinite else { return }
                self.currentTime = seconds
                if abs(seconds - self.lastObservedPosition) > 0.05 {
                    self.lastObservedPosition = seconds
                    self.lastProgressTime = Date()
                }
                if let dur = av.currentItem?.duration.seconds, dur.isFinite && dur > 0 { self.duration = dur }
                let remaining = self.duration - seconds
                let shouldPrefetch = (seconds >= 3.0 || (remaining <= 30 && remaining > 0)) && self.currentEpisodeIndex < self.allEpisodes.count
                if shouldPrefetch && self.preloadedEpisode?.episodeIndex != (self.currentEpisodeIndex + 1) && self.prefetchTask == nil {
                    self.prefetchNextEpisode()
                }
                self.nextEpisodeCountdown = nil
                self.updateActiveDanmakus()
            }
        }
        let center = NotificationCenter.default
        itemNotifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player === av, generation == self.playbackGeneration, !self.closed else { return }
                await self.handlePlayEnded()
            }
        })
        for name in [NSNotification.Name.AVPlayerItemFailedToPlayToEndTime, .AVPlayerItemPlaybackStalled] {
            itemNotifications.append(center.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.player === av, generation == self.playbackGeneration, !self.closed, self.playIntent else { return }
                    if name == .AVPlayerItemFailedToPlayToEndTime { self.requestRecovery(reason: "视频读取中断") }
                }
            })
        }
        initializationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player === av, self.isLoading, !self.closed else { return }
                self.requestRecovery(reason: "视频初始化超时")
            }
        }
        lastObservedPosition = seekTo
        lastProgressTime = Date()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player === av, !self.closed else { return }
                guard self.playIntent, UIApplication.shared.applicationState == .active, !self.isLoading else {
                    self.lastProgressTime = Date()
                    return
                }
                if Date().timeIntervalSince(self.lastProgressTime) >= 20 { self.requestRecovery(reason: "视频持续缓冲，正在恢复") }
            }
        }
        resetControlsHideTimer()
    }

    private func releasePlayerObservers() {
        initializationTimer?.invalidate()
        healthTimer?.invalidate()
        bufferingDebounceTimer?.invalidate()
        bufferingDebounceTimer = nil
        statusObserver?.invalidate()
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        itemNotifications.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotifications.removeAll()
        if let token = timeObserverToken { player?.removeTimeObserver(token); timeObserverToken = nil }
    }

    private func prefetchNextEpisode() {
        let nextIndex = currentEpisodeIndex + 1
        guard nextIndex <= allEpisodes.count else { return }
        guard preloadedEpisode?.episodeIndex != nextIndex, prefetchTask == nil else { return }
        let targetEpisode = allEpisodes.indices.contains(nextIndex - 1) ? allEpisodes[nextIndex - 1] : nil
        let targetDrama = self.drama
        let targetQuality = self.selectedQuality
        let currentGen = self.playbackGeneration

        prefetchTask = Task { [weak self] in
            defer {
                Task { @MainActor in
                    self?.prefetchTask = nil
                }
            }
            do {
                let resolvedPlan = try await NativeRepository.preloading.resolvePlayback(
                    drama: targetDrama,
                    episode: targetEpisode,
                    episodeIndex: nextIndex,
                    quality: targetQuality
                )
                guard !Task.isCancelled else { return }

                guard let scheme = URL(string: resolvedPlan.url)?.scheme, ["https", "http", "file"].contains(scheme) else { return }

                let prepared = try await PlaybackAssetFactory.prepare(resolvedPlan)
                let decryptedTempURL = prepared.decryptedURL
                let asset = prepared.asset
                _ = try? await asset.load(.isPlayable, .duration, .tracks)
                guard !Task.isCancelled else {
                    if let temp = decryptedTempURL { CENCMP4Decryptor.shared.removePlaybackCache(at: temp) }
                    return
                }
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 3

                await MainActor.run {
                    guard let self, !self.closed, currentGen == self.playbackGeneration, !Task.isCancelled else {
                        if let temp = decryptedTempURL {
                            CENCMP4Decryptor.shared.removePlaybackCache(at: temp)
                        }
                        return
                    }
                    if let old = self.preloadedEpisode, let oldDec = old.decryptedURL, oldDec != decryptedTempURL {
                        CENCMP4Decryptor.shared.removePlaybackCache(at: oldDec)
                    }
                    self.preloadedEpisode = PreloadedEpisode(
                        episodeIndex: nextIndex,
                        plan: resolvedPlan,
                        playerItem: item,
                        decryptedURL: decryptedTempURL
                    )
                    NSLog("🎬 [PlayerVM] 成功提前加载并解密第%d集(媒体预缓冲就绪)", nextIndex)
                }
            } catch {
                NSLog("🎬 [PlayerVM] 提前预载第%d集失败: %@", nextIndex, error.localizedDescription)
            }
        }
    }

    // MARK: - 控制与遥控器交互
    public func togglePlayPause() {
        if drama.id.starts(with: "test_") {
            playIntent.toggle()
            isPlaying = playIntent
            if isControlsVisible {
                resetControlsHideTimer()
            }
            return
        }
        guard let p = player else { return }
        if playIntent {
            playIntent = false
            p.pause()
            isPlaying = false
            isBuffering = false
        } else {
            playIntent = true
            if reachedEnd {
                reachedEnd = false
                seek(to: 0)
            }
            lastProgressTime = Date()
            if isSceneActive { p.playImmediately(atRate: playbackRate) }
        }
        samplePlaybackClock()
        updateActiveDanmakus()
        if isControlsVisible {
            resetControlsHideTimer()
        }
    }

    public func seekBy(seconds: Double) {
        guard !isLoading, seconds.isFinite, duration.isFinite, duration > 0 else { return }
        let target = max(0, min(currentTime + seconds, duration))
        seek(to: target)
        showControls()
    }

    public func seekDirectly(by seconds: Double) {
        guard !isLoading, seconds.isFinite, duration.isFinite, duration > 0 else { return }
        let target = max(0, min(currentTime + seconds, duration))
        seek(to: target)
    }

    public func seekTo(target: Double) {
        guard !isLoading, target.isFinite, duration.isFinite, duration > 0 else { return }
        let clamped = max(0, min(target, duration))
        seek(to: clamped)
    }

    private func seek(to target: Double) {
        guard let p = player, p.currentItem?.status == .readyToPlay else { return }
        seekSequence += 1
        let sequence = seekSequence
        let generation = playbackGeneration
        isSeeking = true
        currentTime = target
        lastProgressTime = Date()
        updateActiveDanmakus()
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak p] _ in
            Task { @MainActor in
                guard let self, let p, self.player === p, generation == self.playbackGeneration,
                      sequence == self.seekSequence, !self.closed else { return }
                self.isSeeking = false
                self.samplePlaybackClock()
                self.lastObservedPosition = self.currentTime
                self.lastProgressTime = Date()
                self.updateActiveDanmakus()
            }
        }
    }

    public func setRate(_ rate: Float) {
        guard rate.isFinite, rate >= 0.25, rate <= 3 else { return }
        samplePlaybackClock()
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateActiveDanmakus()
        showControls()
    }

    public func changeQuality(_ q: Int) async {
        guard q != selectedQuality else { return }
        samplePlaybackClock()
        let currentPos = currentTime
        selectedQuality = q
        await beginPlayback(episodeIndex: currentEpisodeIndex, seekTo: currentPos, recovering: false, preservePlayIntent: true)
        if selectedQuality < q {
            showToast("当前分集使用 " + PlaybackPlan.qualityLabel(selectedQuality))
        }
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
        store.danmakuEnabled = danmakuEnabled
        updateActiveDanmakus()
    }

    public func updateDanmakuStyle(_ style: TVDanmakuStyle) {
        danmakuStyle = style
        store.danmakuStyle = style
        updateActiveDanmakus()
    }

    public func setDanmakuFontSize(_ size: CGFloat) {
        var next = danmakuStyle
        next.fontSize = size
        updateDanmakuStyle(next)
    }

    public func setDanmakuOpacity(_ op: Double) {
        var next = danmakuStyle
        next.opacity = op
        updateDanmakuStyle(next)
    }

    public func setDanmakuLaneCount(_ lanes: Int) {
        var next = danmakuStyle
        next.laneCount = lanes
        updateDanmakuStyle(next)
    }

    public func setSceneActive(_ active: Bool) {
        guard active != isSceneActive, !closed else { return }
        isSceneActive = active
        if active {
            if resumeAfterInterruption {
                resumeAfterInterruption = false
                playIntent = true
                lastProgressTime = Date()
                if player?.currentItem?.status == .readyToPlay { player?.playImmediately(atRate: playbackRate) }
            }
        } else {
            resumeAfterInterruption = playIntent
            playIntent = false
            player?.pause()
            isPlaying = false
            isBuffering = false
            saveCurrentProgress()
        }
        samplePlaybackClock()
        updateActiveDanmakus()
    }

    private func samplePlaybackClock() {
        guard !isSeeking, let seconds = player?.currentTime().seconds, seconds.isFinite else { return }
        currentTime = max(0, seconds)
        playbackClockDate = Date()
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
    private func resetDanmaku() {
        danmakuRequestSequence += 1
        danmakuTask?.cancel()
        danmakuTask = nil
        danmakuPages.removeAll()
        danmakuRetryAfter.removeAll()
        danmakuCache = []
        activeDanmakus = []
    }

    private func requestDanmaku(start: Int64, durationMs: Int64) {
        guard let plan, !plan.danmakuId.isEmpty, danmakuTask == nil, danmakuPages[start] == nil,
              start < durationMs, danmakuRetryAfter[start, default: .distantPast] <= Date() else { return }
        let generation = playbackGeneration
        danmakuRequestSequence += 1
        let sequence = danmakuRequestSequence
        danmakuTask = Task { [weak self] in
            guard let self else { return }
            defer { if sequence == self.danmakuRequestSequence { self.danmakuTask = nil } }
            do {
                let rows = try await self.repository.loadDanmaku(plan: plan, startMs: start, durationMs: durationMs)
                guard !Task.isCancelled, sequence == self.danmakuRequestSequence, generation == self.playbackGeneration,
                      self.danmakuEnabled, !self.closed, self.plan?.danmakuId == plan.danmakuId else { return }
                self.danmakuPages[start] = rows
                let position = Int64(self.currentTime * 1000)
                let nearest = self.danmakuPages.keys.sorted { abs($0 - position) < abs($1 - position) }
                for key in nearest.dropFirst(6) { self.danmakuPages.removeValue(forKey: key) }
                self.danmakuRetryAfter.removeValue(forKey: start)
                var seen = Set<String>()
                self.danmakuCache = self.danmakuPages.values.flatMap { $0 }.sorted { $0.timeMs < $1.timeMs }.filter { seen.insert($0.id).inserted }
                self.danmakuTask = nil
                self.updateActiveDanmakus()
            } catch {
                guard !Task.isCancelled, sequence == self.danmakuRequestSequence, generation == self.playbackGeneration else { return }
                self.danmakuRetryAfter[start] = Date().addingTimeInterval(15)
            }
        }
    }

    private func updateActiveDanmakus() {
        playbackClockDate = Date()
        guard danmakuEnabled, !closed, currentTime.isFinite, duration.isFinite, duration > 0, duration <= 86400 else {
            activeDanmakus = []
            return
        }
        let currentMs = Int64(max(0, min(currentTime, duration)) * 1000)
        let durationMs = Int64(duration * 1000)
        activeDanmakus = danmakuCache.filter { $0.timeMs > currentMs - 8000 && $0.timeMs <= currentMs }
        let start = currentMs / 30000 * 30000
        requestDanmaku(start: start, durationMs: durationMs)
        if danmakuPages[start] != nil && currentMs >= start + 22000 {
            requestDanmaku(start: start + 30000, durationMs: durationMs)
        }
    }

    // MARK: - 连播与进度持久化
    private func handlePlayEnded() async {
        currentTime = duration
        saveCurrentProgress()
        nextEpisodeCountdown = nil
        if currentEpisodeIndex < allEpisodes.count {
            isSeamlessTransitioning = true
            await nextEpisode()
        } else {
            reachedEnd = true
            playIntent = false
            resumeAfterInterruption = false
            player?.pause()
            isPlaying = false
            updateActiveDanmakus()
            showControls()
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
        guard duration > 0, duration.isFinite else { return }
        samplePlaybackClock()
        store.recordWatch(drama: drama, episode: currentEpisodeIndex, position: currentTime, duration: duration)
    }
}
