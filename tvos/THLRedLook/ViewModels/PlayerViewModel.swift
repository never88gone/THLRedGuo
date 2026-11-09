import Foundation
import AVFoundation
import AVKit
import MediaPlayer
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
    @Published public var selectedQuality: Int = 0
    @Published public private(set) var requestedQuality: Int = 0
    @Published public var playbackRate: Float = 1.0
    @Published public var isControlsVisible: Bool = true
    @Published public var isEpisodeDrawerVisible: Bool = false
    @Published public var isDanmakuSettingsVisible: Bool = false
    @Published public var isSpeedSheetVisible: Bool = false
    @Published public var isQualitySheetVisible: Bool = false
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
    public var onFeedEndReached: (() -> Void)? = nil
    public var playbackClockDate = Date()

    // 独立功能服务组件（根据功能拆分，杜绝扩展）
    let danmakuManager: PlayerDanmakuManager
    private let remoteCoordinator = PlayerRemoteCommandCoordinator()
    private let prefetchCoordinator: PlayerPrefetchCoordinator
    private let recoveryCoordinator: PlayerRecoveryCoordinator
    private let playbackPreparer: PlayerPlaybackPreparer
    private let observerManager = PlayerObserverManager()
    private let progressTracker: PlayerProgressTracker
    private let pipCoordinator = PlayerPiPCoordinator()

    public var isPictureInPictureSupported: Bool { pipCoordinator.isSupported }
    public var pipController: AVPictureInPictureController? {
        get { pipCoordinator.pipController }
        set { pipCoordinator.pipController = newValue }
    }
    public var danmakuEnabled: Bool {
        get { danmakuManager.danmakuEnabled }
        set { danmakuManager.danmakuEnabled = newValue }
    }
    public var danmakuStyle: TVDanmakuStyle {
        get { danmakuManager.danmakuStyle }
        set { danmakuManager.danmakuStyle = newValue }
    }
    public var activeDanmakus: [DanmakuItem] { danmakuManager.activeDanmakus }
    public var qualityOptions: [Int] { [0] + Set(plan?.qualities.filter { $0 > 0 } ?? []).sorted(by: >) }

    public func toggleDanmaku() { danmakuManager.toggleDanmaku() }

    public func startPictureInPicture() {
        guard isPictureInPictureSupported else {
            showToast("当前设备不支持系统画中画")
            return
        }
        guard let p = self.player else {
            showToast("播放器准备中，请稍候...")
            return
        }
        showToast("已开启画中画，返回主界面可持续悬浮播放")
        TVPictureInPictureCoordinator.shared.startPictureInPicture(
            player: p,
            drama: self.drama,
            currentEpisodeIndex: self.currentEpisodeIndex,
            allEpisodes: self.allEpisodes,
            initialPosition: self.currentTime,
            playbackPlan: self.plan
        )
    }

    private var isSeeking = false
    private var isSceneActive = true
    private var resumeAfterInterruption = false
    private var reachedEnd = false
    private var controlsHideTimer: Timer?
    private var toastHideTimer: Timer?
    private var isVisible = false
    private var closed = false
    private var playIntent: Bool {
        get { wantsPlayback }
        set { wantsPlayback = newValue }
    }
    private var decryptedURL: URL?
    private let initialPreloadedPlan: PlaybackPlan?
    private let isFeedMode: Bool
    private var lastTogglePlayPauseTime: Date = .distantPast
    private var cancellables = Set<AnyCancellable>()

    public init(
        drama: Drama, allEpisodes: [Episode], initialEpisodeIndex: Int = 1,
        initialPosition: Double = 0, initialShowControls: Bool = false, keepControlsVisible: Bool = false,
        initialShowDrawer: Bool = false, initialRestoreFocusTarget: PlayerOverlayFocusTarget? = nil,
        preloadedPlan: PlaybackPlan? = nil, isFeedMode: Bool = false,
        repository: NativeRepository = .shared, preloadingRepository: NativeRepository? = nil,
        store: LocalStore = .shared, diagnostics: SourceDiagnostics = .shared
    ) {
        self.drama = drama; self.allEpisodes = allEpisodes
        self.currentEpisodeIndex = initialEpisodeIndex; self.currentTime = initialPosition
        self.isControlsVisible = initialShowDrawer ? false : initialShowControls
        self.isEpisodeDrawerVisible = initialShowDrawer; self.keepControlsVisible = keepControlsVisible
        self.restoreFocusTarget = initialRestoreFocusTarget; self.initialPreloadedPlan = preloadedPlan
        self.isFeedMode = isFeedMode
        self.danmakuManager = PlayerDanmakuManager(store: store, repository: repository)
        self.prefetchCoordinator = PlayerPrefetchCoordinator(preloadingRepository: preloadingRepository ?? .preloading)
        self.recoveryCoordinator = PlayerRecoveryCoordinator(diagnostics: diagnostics)
        self.playbackPreparer = PlayerPlaybackPreparer(repository: repository, store: store)
        self.progressTracker = PlayerProgressTracker(store: store)

        danmakuManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        progressTracker.startTimer { [weak self] in self?.saveCurrentProgress() }
    }

    public func restoreSavedProgress() {
        guard !isVisible, let entry = progressTracker.restoreSavedProgress(dramaId: drama.id) else { return }
        currentEpisodeIndex = entry.episode; currentTime = entry.position; duration = entry.duration
    }

    public func bindPictureInPictureController(_ controller: AVPictureInPictureController) {
        self.pipController = controller
        pipCoordinator.register(player: player, drama: drama, currentEpisodeIndex: currentEpisodeIndex, allEpisodes: allEpisodes, currentTime: currentTime, plan: plan)
    }

    public func onAppear() {
        guard !isVisible else { return }
        isVisible = true; closed = false
        remoteCoordinator.setup(
            onPlay: { [weak self] in if self?.playIntent == false { self?.togglePlayPause() } },
            onPause: { [weak self] in if self?.playIntent == true { self?.togglePlayPause() } },
            onToggle: { [weak self] in self?.togglePlayPause() }
        )
        progressTracker.startTimer { [weak self] in self?.saveCurrentProgress() }

        if let restored = pipCoordinator.checkRestorePiP(dramaId: drama.id) {
            currentTime = restored.position; currentEpisodeIndex = restored.episode
            if let p = restored.plan { plan = p; selectedQuality = p.quality }
            startPlaybackWithPlayer(restored.player, seekTo: 0)
            isLoading = false; isPlaying = (restored.player.timeControlStatus == .playing)
            return
        }

        if let preloaded = initialPreloadedPlan, preloaded.isReusable(),
           let poolPlayer = VideoCacheManager.shared.cachedPlayer(for: preloaded.url, namespace: "feed") {
            plan = preloaded; selectedQuality = preloaded.quality
            VideoCacheManager.shared.focusOnVideo(urlString: preloaded.url, namespace: "feed")
            startPlaybackWithPlayer(poolPlayer, seekTo: currentTime); isLoading = false
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.preparePlayback(episodeIndex: self.currentEpisodeIndex, seekTo: self.currentTime)
        }
    }

    public func onDisappear() {
        if pipCoordinator.isPiPActive || pipCoordinator.isStartingPiP {
            isVisible = false; saveCurrentProgress(force: true)
            progressTracker.stopTimer(); controlsHideTimer?.invalidate(); controlsHideTimer = nil
            return
        }

        closed = true; resumeAfterInterruption = false; isVisible = false
        recoveryCoordinator.cancel()
        prefetchCoordinator.clearPreloaded(currentDecryptedURL: decryptedURL)
        saveCurrentProgress(force: true)
        progressTracker.stopTimer(); controlsHideTimer?.invalidate(); controlsHideTimer = nil
        releasePlayer()
        pipCoordinator.unregister()
        plan = nil
    }

    private func releasePlayer() {
        remoteCoordinator.teardown()
        danmakuManager.reset()
        observerManager.release()
        isSeeking = false
        player?.pause()
        if initialPreloadedPlan == nil { player?.replaceCurrentItem(with: nil) }
        player = nil; isPlaying = false; isBuffering = false
        if let url = decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: url); decryptedURL = nil }
    }

    public func preparePlayback(episodeIndex: Int, seekTo: Double = 0) async {
        guard !closed, episodeIndex > 0, seekTo.isFinite else { return }
        saveCurrentProgress(force: true); recoveryCoordinator.cancel(); prefetchCoordinator.cancel(); reachedEnd = false

        if let preloaded = prefetchCoordinator.consumePreloaded(for: episodeIndex, currentDecryptedURL: decryptedURL) {
            currentEpisodeIndex = episodeIndex; currentTime = max(0, seekTo); duration = 0; errorMessage = nil
            plan = preloaded.plan; selectedQuality = preloaded.plan.quality
            if let oldDec = decryptedURL, oldDec != preloaded.decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: oldDec) }
            decryptedURL = preloaded.decryptedURL
            startPlaybackWithItem(item: preloaded.playerItem, seekTo: seekTo)
            danmakuManager.updateActiveDanmakus(currentTime: currentTime, duration: duration, plan: plan)
            return
        }

        plan = nil; observerManager.release()
        if !isSeamlessTransitioning { player?.pause(); await remoteCoordinator.configureAudioSession() }
        guard !closed else { return }
        currentEpisodeIndex = episodeIndex; currentTime = max(0, seekTo); duration = 0; isLoading = true; errorMessage = nil

        do {
            let result = try await playbackPreparer.prepareEpisode(drama: drama, allEpisodes: allEpisodes, episodeIndex: episodeIndex, requestedQuality: requestedQuality, avoidURL: recoveryCoordinator.failedURL)
            guard !closed else { return }
            plan = result.plan; selectedQuality = result.plan.quality
            if let old = decryptedURL, old != result.decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: old) }
            decryptedURL = result.decryptedURL
            startPlaybackWithItem(item: result.playerItem, seekTo: seekTo)
            danmakuManager.updateActiveDanmakus(currentTime: currentTime, duration: duration, plan: plan)
        } catch {
            guard !closed, !(error is CancellationError) else { return }
            handlePlaybackError(error: error)
        }
    }

    public func switchFeedDrama(
        drama: Drama,
        allEpisodes: [Episode]? = nil,
        initialEpisodeIndex: Int = 1,
        initialPosition: Double = 0,
        preloadedPlan: PlaybackPlan? = nil
    ) async {
        guard !closed else { return }
        saveCurrentProgress(force: true)
        prefetchCoordinator.clearPreloaded(currentDecryptedURL: decryptedURL)
        if let old = decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: old); decryptedURL = nil }
        self.drama = drama; self.allEpisodes = allEpisodes ?? []
        self.currentEpisodeIndex = initialEpisodeIndex; self.currentTime = max(0, initialPosition); self.duration = 0
        self.errorMessage = nil; self.isSeamlessTransitioning = true

        if let plan = preloadedPlan, plan.isReusable(),
           let poolPlayer = VideoCacheManager.shared.cachedPlayer(for: plan.url, namespace: "feed") {
            self.plan = plan; self.selectedQuality = plan.quality
            VideoCacheManager.shared.focusOnVideo(urlString: plan.url, namespace: "feed")
            startPlaybackWithPlayer(poolPlayer, seekTo: initialPosition)
            self.isSeamlessTransitioning = false; self.isLoading = false
            return
        }
        await preparePlayback(episodeIndex: initialEpisodeIndex, seekTo: initialPosition)
        self.isSeamlessTransitioning = false
    }

    private func handlePlaybackError(error: Error) {
        recoveryCoordinator.requestRecovery(
            reason: error.localizedDescription, error: error, drama: drama, episodeIndex: currentEpisodeIndex, currentTime: currentTime, planURL: plan?.url,
            onRetry: { [weak self] ep, pos in await self?.preparePlayback(episodeIndex: ep, seekTo: pos) },
            onExceeded: { [weak self] msg in
                self?.player?.pause(); self?.isPlaying = false; self?.isBuffering = false; self?.isLoading = false; self?.errorMessage = msg
            }
        )
    }

    func requestRecovery(reason: String, code: String = "", error: Error? = nil) {
        handlePlaybackError(error: error ?? NSError(domain: "THLRedLook.Player", code: -1, userInfo: [NSLocalizedDescriptionKey: reason]))
    }

    func startPlaybackWithItem(item: AVPlayerItem, seekTo: Double) {
        let av = player ?? AVPlayer(playerItem: item)
        if player != nil { av.pause(); av.rate = 0; av.replaceCurrentItem(with: item) }
        else { av.automaticallyWaitsToMinimizeStalling = true; player = av }
        setupObserver(av: av, item: item, seekTo: seekTo)
    }

    private func startPlaybackWithPlayer(_ cachedPlayer: AVPlayer, seekTo: Double) {
        cachedPlayer.isMuted = false; cachedPlayer.automaticallyWaitsToMinimizeStalling = true
        self.player = cachedPlayer
        if let item = cachedPlayer.currentItem { setupObserver(av: cachedPlayer, item: item, seekTo: seekTo) }
    }

    private func setupObserver(av: AVPlayer, item: AVPlayerItem, seekTo: Double) {
        observerManager.attach(
            to: av, item: item, seekTo: seekTo, playbackRate: playbackRate, isFeedMode: isFeedMode,
            onPlayingChanged: { [weak self] playing in
                guard let self else { return }
                self.isPlaying = playing && self.playIntent && self.isSceneActive
                if self.isPlaying { self.isLoading = false; self.isSeamlessTransitioning = false }
                self.samplePlaybackClock()
                self.danmakuManager.updateActiveDanmakus(currentTime: self.currentTime, duration: self.duration, plan: self.plan)
            },
            onBufferingChanged: { [weak self] buffering in
                guard let self else { return }
                self.isBuffering = buffering && self.playIntent && self.isSceneActive && !self.isSeamlessTransitioning
            },
            onReadyToPlay: { [weak self] dur, quality in
                guard let self else { return }
                self.errorMessage = nil; self.duration = dur
                if quality > 0 { self.selectedQuality = quality }
                self.isLoading = false; self.isSeamlessTransitioning = false
                if self.playIntent && self.isSceneActive {
                    av.playImmediately(atRate: self.playbackRate); av.play()
                    if self.playbackRate > 0 { av.rate = self.playbackRate }
                }
            },
            onTimeUpdated: { [weak self] sec in
                guard let self, !self.isSeeking else { return }
                self.currentTime = sec
                if self.isLoading { self.isLoading = false }
                let rem = self.duration - sec
                if sec >= 3 && rem <= 20 && rem > 0 && self.currentEpisodeIndex < self.allEpisodes.count {
                    self.prefetchCoordinator.prefetchNextEpisode(
                        currentEpisodeIndex: self.currentEpisodeIndex, allEpisodes: self.allEpisodes, drama: self.drama, requestedQuality: self.requestedQuality, generation: 0
                    )
                }
                self.danmakuManager.updateActiveDanmakus(currentTime: self.currentTime, duration: self.duration, plan: self.plan)
            },
            onItemEnded: { [weak self] in Task { @MainActor in await self?.handlePlayEnded() } },
            onError: { [weak self] error in self?.handlePlaybackError(error: error) }
        )
        resetControlsHideTimer()
    }

    public func togglePlayPause() {
        let now = Date()
        guard now.timeIntervalSince(lastTogglePlayPauseTime) > 0.3 else { return }
        lastTogglePlayPauseTime = now
        guard let p = player else { return }
        if playIntent {
            playIntent = false; p.pause(); p.rate = 0; isPlaying = false; isBuffering = false
        } else {
            isSceneActive = true; playIntent = true
            if reachedEnd { reachedEnd = false; seek(to: 0) }
            p.playImmediately(atRate: playbackRate); p.play()
            if playbackRate > 0 { p.rate = playbackRate }
            Task { [weak self, weak p] in
                guard let self, let p else { return }
                await self.remoteCoordinator.configureAudioSession()
                guard !self.closed, self.playIntent else { return }
                p.playImmediately(atRate: self.playbackRate); p.play()
                if self.playbackRate > 0 { p.rate = self.playbackRate }
            }
        }
        samplePlaybackClock()
        danmakuManager.updateActiveDanmakus(currentTime: currentTime, duration: duration, plan: plan)
        if isControlsVisible { resetControlsHideTimer() }
    }

    public func seekBy(seconds: Double) {
        let target = max(0, min(currentTime + seconds, duration))
        showControls()
        seek(to: target)
    }

    public func seekDirectly(by seconds: Double) {
        let target = max(0, min(currentTime + seconds, duration))
        seek(to: target)
    }

    public func setDanmakuFontSize(_ size: CGFloat) {
        danmakuManager.danmakuStyle.fontSize = size
    }

    public func setDanmakuOpacity(_ op: Double) {
        danmakuManager.danmakuStyle.opacity = op
    }

    public func setDanmakuLaneCount(_ lanes: Int) {
        danmakuManager.danmakuStyle.laneCount = lanes
    }

    public func seekTo(target: Double) {
        guard !isLoading, target.isFinite, duration > 0 else { return }
        seek(to: max(0, min(target, duration)))
    }

    private func seek(to target: Double) {
        guard let p = player, p.currentItem?.status == .readyToPlay else { return }
        isSeeking = true; currentTime = target
        danmakuManager.updateActiveDanmakus(currentTime: currentTime, duration: duration, plan: plan)
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeeking = false; self.samplePlaybackClock()
                self.danmakuManager.updateActiveDanmakus(currentTime: self.currentTime, duration: self.duration, plan: self.plan)
            }
        }
    }

    public func setRate(_ rate: Float) {
        guard rate.isFinite, rate >= 0.25, rate <= 3 else { return }
        samplePlaybackClock(); playbackRate = rate
        if isPlaying { player?.rate = rate }
        danmakuManager.updateActiveDanmakus(currentTime: currentTime, duration: duration, plan: plan)
        showControls()
    }

    public func changeQuality(_ q: Int) async {
        guard qualityOptions.contains(q), q != requestedQuality else { return }
        samplePlaybackClock(); requestedQuality = q
        await preparePlayback(episodeIndex: currentEpisodeIndex, seekTo: currentTime)
    }

    public func nextEpisode() async {
        guard currentEpisodeIndex < allEpisodes.count else { return }
        await preparePlayback(episodeIndex: currentEpisodeIndex + 1, seekTo: 0)
    }

    public func previousEpisode() async {
        guard currentEpisodeIndex > 1 else { return }
        await preparePlayback(episodeIndex: currentEpisodeIndex - 1, seekTo: 0)
    }

    public func selectEpisode(number: Int) async {
        isEpisodeDrawerVisible = false
        guard number != currentEpisodeIndex else { return }
        await preparePlayback(episodeIndex: number, seekTo: 0)
    }

    public func setSceneActive(_ active: Bool) {
        guard active != isSceneActive, !closed else { return }
        isSceneActive = active
        if active {
            Task { await remoteCoordinator.configureAudioSession() }
            if resumeAfterInterruption {
                resumeAfterInterruption = false; playIntent = true
                player?.playImmediately(atRate: playbackRate); player?.play()
                if playbackRate > 0 { player?.rate = playbackRate }
            }
        } else {
            resumeAfterInterruption = playIntent; playIntent = false
            player?.pause(); isPlaying = false; isBuffering = false
            saveCurrentProgress(force: true)
        }
        samplePlaybackClock()
        danmakuManager.updateActiveDanmakus(currentTime: currentTime, duration: duration, plan: plan)
    }

    private func samplePlaybackClock() {
        guard !isSeeking, let sec = player?.currentTime().seconds, sec.isFinite else { return }
        currentTime = max(0, sec); playbackClockDate = Date()
    }

    public func showControls() {
        withAnimation(.easeInOut(duration: 0.25)) { isControlsVisible = true }
        resetControlsHideTimer()
    }

    public func hideControls() {
        withAnimation(.easeInOut(duration: 0.25)) { isControlsVisible = false }
        controlsHideTimer?.invalidate()
    }

    private func resetControlsHideTimer() {
        guard !keepControlsVisible else { return }
        controlsHideTimer?.invalidate()
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { if self?.isPlaying == true { self?.isControlsVisible = false } }
        }
    }

    private func handlePlayEnded() async {
        currentTime = duration
        if currentEpisodeIndex < allEpisodes.count {
            isSeamlessTransitioning = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, !self.closed, self.isSeamlessTransitioning else { return }
                self.isSeamlessTransitioning = false
            }
            await nextEpisode()
        } else if isFeedMode, let onFeedEndReached {
            onFeedEndReached()
        } else {
            saveCurrentProgress(force: true)
            reachedEnd = true; playIntent = false; resumeAfterInterruption = false
            player?.pause(); isPlaying = false
            danmakuManager.updateActiveDanmakus(currentTime: currentTime, duration: duration, plan: plan)
            showControls()
        }
    }

    public func saveCurrentProgress(force: Bool = false) {
        samplePlaybackClock()
        progressTracker.recordProgress(drama: drama, episode: currentEpisodeIndex, position: currentTime, duration: duration, danmakuId: plan?.danmakuId, force: force)
    }

    public func showToast(_ message: String) {
        toastHideTimer?.invalidate(); toastMessage = message
        toastHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.3)) { self?.toastMessage = nil } }
        }
    }
}
