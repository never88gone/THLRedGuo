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
    @Published public var currentTime: Double = 0 {
        didSet { playbackClockDate = Date() }
    }
    @Published public var duration: Double = 0
    @Published public var currentEpisodeIndex: Int
    @Published public var plan: PlaybackPlan?
    @Published public var selectedQuality: Int = 0
    @Published public private(set) var requestedQuality: Int = 0
    @Published public var playbackRate: Float = 1.0
    public var isControlsVisible: Bool {
        get { visibilityCoordinator.isControlsVisible }
        set { visibilityCoordinator.isControlsVisible = newValue }
    }
    @Published public var isEpisodeDrawerVisible: Bool = false
    @Published public var isDanmakuSettingsVisible: Bool = false
    @Published public var isSpeedSheetVisible: Bool = false
    @Published public var isQualitySheetVisible: Bool = false
    @Published public var isLoading: Bool = true
    @Published public var isSeamlessTransitioning: Bool = false
    @Published public var errorMessage: String?
    public var toastMessage: String? {
        get { visibilityCoordinator.toastMessage }
        set { visibilityCoordinator.toastMessage = newValue }
    }
    @Published public var nextEpisodeCountdown: Int?
    @Published public var relatedSeasons: [Drama] = []
    @Published public var switchSeasonDrama: Drama?
    public var restoreFocusTarget: PlayerOverlayFocusTarget?
    @Published public private(set) var drama: Drama
    @Published public var allEpisodes: [Episode]
    public var keepControlsVisible: Bool = false
    public var onFeedEndReached: (() -> Void)? = nil
    public private(set) var playbackClockDate = Date()

    // 独立功能服务组件（根据功能拆分，杜绝扩展）
    let danmakuManager: PlayerDanmakuManager
    private let visibilityCoordinator: PlayerControlsVisibilityCoordinator
    private let seekCoordinator = PlayerSeekCoordinator()
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
        guard isPictureInPictureSupported else { showToast("当前设备不支持系统画中画"); return }
        guard let p = self.player else { showToast("播放器准备中，请稍候..."); return }
        showToast("已开启画中画，返回主界面可持续悬浮播放")
        TVPictureInPictureCoordinator.shared.startPictureInPicture(
            player: p, drama: self.drama, currentEpisodeIndex: self.currentEpisodeIndex,
            allEpisodes: self.allEpisodes, initialPosition: self.currentTime, playbackPlan: self.plan
        )
    }

    public var isSeeking: Bool { seekCoordinator.isSeeking }
    private var playbackGeneration = 0
    private var preparationTask: Task<Void, Never>?
    private var isSceneActive = true
    private var resumeAfterInterruption = false
    private var reachedEnd = false
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
        self.visibilityCoordinator = PlayerControlsVisibilityCoordinator(initialVisible: initialShowDrawer ? false : initialShowControls)
        self.isEpisodeDrawerVisible = initialShowDrawer; self.keepControlsVisible = keepControlsVisible
        self.restoreFocusTarget = initialRestoreFocusTarget; self.initialPreloadedPlan = preloadedPlan
        self.isFeedMode = isFeedMode
        self.danmakuManager = PlayerDanmakuManager(store: store, repository: repository)
        self.prefetchCoordinator = PlayerPrefetchCoordinator(preloadingRepository: preloadingRepository ?? .preloading)
        self.recoveryCoordinator = PlayerRecoveryCoordinator(diagnostics: diagnostics)
        self.playbackPreparer = PlayerPlaybackPreparer(repository: repository, store: store)
        self.progressTracker = PlayerProgressTracker(store: store)

        visibilityCoordinator.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
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

        if let preloaded = initialPreloadedPlan, preloaded.isReusable(), !allEpisodes.isEmpty,
           let poolPlayer = VideoCacheManager.shared.takePlayer(for: preloaded.url, namespace: "feed") {
            plan = preloaded; selectedQuality = preloaded.quality
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
            progressTracker.stopTimer(); visibilityCoordinator.invalidate()
            return
        }
        playbackGeneration += 1; preparationTask?.cancel(); preparationTask = nil
        closed = true; resumeAfterInterruption = false; isVisible = false
        recoveryCoordinator.cancel()
        prefetchCoordinator.clearPreloaded(currentDecryptedURL: decryptedURL)
        saveCurrentProgress(force: true)
        progressTracker.stopTimer(); visibilityCoordinator.invalidate()
        releasePlayer()
        pipCoordinator.unregister()
        plan = nil
    }

    private func releasePlayer() {
        remoteCoordinator.teardown(); danmakuManager.reset(); observerManager.release()
        seekCoordinator.cancel(); player?.pause(); player?.replaceCurrentItem(with: nil)
        player = nil; isPlaying = false; isBuffering = false
        if let url = decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: url); decryptedURL = nil }
    }

    public func preparePlayback(episodeIndex: Int, seekTo: Double = 0) async {
        await beginPlayback(episodeIndex: episodeIndex, seekTo: seekTo, recovering: false)
    }

    private func beginPlayback(episodeIndex: Int, seekTo: Double, recovering: Bool, preserveIntent: Bool = false) async {
        guard !closed, episodeIndex > 0, seekTo.isFinite else { return }
        saveCurrentProgress(force: true)
        playbackGeneration += 1
        let generation = playbackGeneration
        preparationTask?.cancel(); recoveryCoordinator.cancel()
        if !recovering { recoveryCoordinator.reset() }
        if !recovering && !preserveIntent { playIntent = isSceneActive; resumeAfterInterruption = !isSceneActive }
        prefetchCoordinator.cancel(); reachedEnd = false
        observerManager.release(); player?.pause(); player?.currentItem?.cancelPendingSeeks()
        seekCoordinator.cancel(); danmakuManager.reset()
        currentEpisodeIndex = episodeIndex; currentTime = max(0, seekTo); duration = 0
        isPlaying = false; isBuffering = false; isLoading = true; errorMessage = nil; plan = nil
        if !recovering, let preloaded = prefetchCoordinator.consumePreloaded(for: episodeIndex, currentDecryptedURL: decryptedURL) {
            plan = preloaded.plan; selectedQuality = preloaded.plan.quality
            let old = decryptedURL; decryptedURL = preloaded.decryptedURL
            startPlaybackWithItem(item: preloaded.playerItem, seekTo: seekTo)
            if let old, old != decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: old) }
            return
        }
        prefetchCoordinator.clearPreloaded(currentDecryptedURL: decryptedURL)
        let task = Task { [weak self] in
            guard let self else { return }
            await remoteCoordinator.configureAudioSession()
            guard !closed, generation == playbackGeneration, !Task.isCancelled else { return }
            do {
                let result = try await playbackPreparer.prepareEpisode(drama: drama, allEpisodes: allEpisodes, episodeIndex: episodeIndex, requestedQuality: requestedQuality, avoidURL: recoveryCoordinator.failedURL)
                guard !closed, generation == playbackGeneration, !Task.isCancelled else {
                    if let url = result.decryptedURL, url != decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: url) }
                    return
                }
                if let resolvedDrama = result.drama { drama = resolvedDrama }
                if let episodes = result.episodes { allEpisodes = episodes }
                plan = result.plan; selectedQuality = result.plan.quality
                let old = decryptedURL; decryptedURL = result.decryptedURL
                startPlaybackWithItem(item: result.playerItem, seekTo: seekTo)
                if let old, old != decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: old) }
            } catch {
                guard !closed, generation == playbackGeneration, !Task.isCancelled, !(error is CancellationError) else { return }
                handlePlaybackError(error: error)
            }
        }
        preparationTask = task
        await task.value
        if generation == playbackGeneration { preparationTask = nil }
    }

    public func switchFeedDrama(drama: Drama, allEpisodes: [Episode]? = nil, initialEpisodeIndex: Int = 1, initialPosition: Double = 0, preloadedPlan: PlaybackPlan? = nil) async {
        guard !closed else { return }
        saveCurrentProgress(force: true)
        playbackGeneration += 1; preparationTask?.cancel(); preparationTask = nil
        recoveryCoordinator.reset()
        prefetchCoordinator.clearPreloaded(currentDecryptedURL: decryptedURL)
        observerManager.release()
        player?.pause(); player?.replaceCurrentItem(with: nil)
        if let old = decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: old); decryptedURL = nil }
        danmakuManager.reset(); seekCoordinator.cancel()
        self.drama = drama; self.allEpisodes = allEpisodes ?? []
        currentEpisodeIndex = initialEpisodeIndex; currentTime = max(0, initialPosition); duration = 0
        errorMessage = nil; plan = nil; isPlaying = false; isBuffering = false; isLoading = true
        isSeamlessTransitioning = false; reachedEnd = false; playIntent = isSceneActive
        if let plan = preloadedPlan, plan.isReusable(), !self.allEpisodes.isEmpty,
           let cached = VideoCacheManager.shared.takePlayer(for: plan.url, namespace: "feed") {
            self.plan = plan; selectedQuality = plan.quality
            startPlaybackWithPlayer(cached, seekTo: initialPosition)
            return
        }
        await preparePlayback(episodeIndex: initialEpisodeIndex, seekTo: initialPosition)
    }

    private func handlePlaybackError(error: Error, code: String = "") {
        guard !closed else { return }
        let generation = playbackGeneration
        recoveryCoordinator.requestRecovery(
            reason: error.localizedDescription, code: code, error: error, drama: drama, episodeIndex: currentEpisodeIndex, currentTime: currentTime, planURL: plan?.url,
            onRetry: { [weak self] ep, pos in
                guard let self, !self.closed, generation == self.playbackGeneration else { return }
                await self.beginPlayback(episodeIndex: ep, seekTo: pos, recovering: true)
            },
            onExceeded: { [weak self] msg in
                self?.playIntent = false; self?.observerManager.release(); self?.player?.pause(); self?.isPlaying = false; self?.isBuffering = false; self?.isLoading = false; self?.errorMessage = msg
            }
        )
    }

    func requestRecovery(reason: String, code: String = "", error: Error? = nil) {
        handlePlaybackError(error: error ?? NSError(domain: "THLRedLook.Player", code: -1, userInfo: [NSLocalizedDescriptionKey: reason]), code: code)
    }
    func startPlaybackWithItem(item: AVPlayerItem, seekTo: Double) {
        observerManager.release()
        let av = player ?? AVPlayer(playerItem: item)
        if player != nil { av.pause(); av.rate = 0; av.replaceCurrentItem(with: item) }
        else { av.automaticallyWaitsToMinimizeStalling = true; player = av }
        setupObserver(av: av, item: item, seekTo: seekTo)
    }
    private func startPlaybackWithPlayer(_ cachedPlayer: AVPlayer, seekTo: Double) {
        observerManager.release(); player?.pause()
        cachedPlayer.isMuted = false; cachedPlayer.automaticallyWaitsToMinimizeStalling = true
        self.player = cachedPlayer
        if let item = cachedPlayer.currentItem { setupObserver(av: cachedPlayer, item: item, seekTo: seekTo) }
    }

    private func setupObserver(av: AVPlayer, item: AVPlayerItem, seekTo: Double) {
        let generation = playbackGeneration
        observerManager.attach(
            to: av, item: item, seekTo: seekTo, playbackRate: playbackRate, isFeedMode: isFeedMode,
            shouldPlay: { [weak self] in self?.playIntent == true && self?.isSceneActive == true && self?.isSeeking == false },
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
                self.recoveryCoordinator.recordAdvance(sec - self.currentTime, playing: self.playIntent && self.isSceneActive && av.timeControlStatus == .playing)
                self.currentTime = sec
                if self.isLoading { self.isLoading = false }
                let rem = self.duration - sec
                if sec >= 3 && rem <= 20 && rem > 0 && self.currentEpisodeIndex < self.allEpisodes.count {
                    self.prefetchCoordinator.prefetchNextEpisode(currentEpisodeIndex: self.currentEpisodeIndex, allEpisodes: self.allEpisodes, drama: self.drama, requestedQuality: self.requestedQuality, generation: generation)
                }
                self.danmakuManager.updateActiveDanmakus(currentTime: self.currentTime, duration: self.duration, plan: self.plan)
            },
            onItemEnded: { [weak self] in Task { @MainActor in
                guard let self, !self.closed, generation == self.playbackGeneration else { return }
                await self.handlePlayEnded()
            } },
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
            let generation = playbackGeneration
            Task { [weak self, weak p] in
                guard let self, let p else { return }
                await self.remoteCoordinator.configureAudioSession()
                guard !self.closed, self.playIntent, self.player === p, self.isSceneActive, generation == self.playbackGeneration else { return }
                p.playImmediately(atRate: self.playbackRate); p.play()
                if self.playbackRate > 0 { p.rate = self.playbackRate }
            }
        }
        samplePlaybackClock()
        danmakuManager.updateActiveDanmakus(currentTime: currentTime, duration: duration, plan: plan)
        if isControlsVisible { resetControlsHideTimer() }
    }

    public func seekBy(seconds: Double) {
        showControls()
        seek(to: max(0, min(currentTime + seconds, duration)))
    }
    public func seekDirectly(by seconds: Double) { seek(to: max(0, min(currentTime + seconds, duration))) }
    public func seekTo(target: Double) {
        guard !isLoading, target.isFinite, duration > 0 else { return }
        seek(to: max(0, min(target, duration)))
    }
    public func setDanmakuFontSize(_ size: CGFloat) { danmakuManager.danmakuStyle.fontSize = size }
    public func setDanmakuOpacity(_ op: Double) { danmakuManager.danmakuStyle.opacity = op }
    public func setDanmakuLaneCount(_ lanes: Int) { danmakuManager.danmakuStyle.laneCount = lanes }

    private func seek(to target: Double) {
        seekCoordinator.seek(
            to: target,
            player: player,
            duration: duration,
            generation: playbackGeneration,
            onStart: { [weak self] clamped in
                guard let self else { return }
                self.currentTime = clamped
                self.danmakuManager.updateActiveDanmakus(currentTime: self.currentTime, duration: self.duration, plan: self.plan)
            },
            onComplete: { [weak self] gen, _ in
                guard let self, !self.closed, gen == self.playbackGeneration else { return }
                self.samplePlaybackClock()
                self.danmakuManager.updateActiveDanmakus(currentTime: self.currentTime, duration: self.duration, plan: self.plan)
            }
        )
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
        await beginPlayback(episodeIndex: currentEpisodeIndex, seekTo: currentTime, recovering: false, preserveIntent: true)
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
        currentTime = max(0, sec)
    }

    public func showControls() {
        visibilityCoordinator.showControls(keepControlsVisible: keepControlsVisible) { [weak self] in self?.isPlaying == true }
    }

    public func hideControls() {
        visibilityCoordinator.hideControls()
    }

    private func resetControlsHideTimer() {
        visibilityCoordinator.resetControlsHideTimer(keepControlsVisible: keepControlsVisible) { [weak self] in self?.isPlaying == true }
    }

    private func handlePlayEnded() async {
        guard !closed, !reachedEnd else { return }
        reachedEnd = true
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
        guard !isLoading, player?.currentItem?.status == .readyToPlay else { return }
        samplePlaybackClock()
        progressTracker.recordProgress(drama: drama, episode: currentEpisodeIndex, position: currentTime, duration: duration, danmakuId: plan?.danmakuId, force: force)
    }

    public func showToast(_ message: String) {
        visibilityCoordinator.showToast(message)
    }
}
