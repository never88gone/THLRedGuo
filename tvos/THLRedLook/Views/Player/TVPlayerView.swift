import SwiftUI
import AVKit

public struct TVPlayerView: View {
    @ObservedObject private var accountLibrary = HongguoAccountModel.shared
    @State private var showingAccountSocial = false
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastExitTime: TimeInterval = 0
    public var onDismiss: (() -> Void)? = nil
    public var onSwitchSeason: ((Drama) -> Void)? = nil
    public var feedActions: TVVideoFeedActions?
    public var focusWakeTrigger: Int = 0
    public var isInteractive: Bool = true
    public let drama: Drama
    public let episodes: [Episode]
    public let initialEpisodeIndex: Int
    public let initialPosition: Double
    public let preloadedPlan: PlaybackPlan?
    @State private var isSwitchingFeed = false
    @State private var isPlayerPresented = false
    @State private var quickSeekDelta: Double = 0
    @State private var quickSeekTarget: Double = 0
    @State private var showQuickSeekIndicator: Bool = false
    @State private var quickSeekHideWorkItem: DispatchWorkItem?
    @State private var initialScrubPosition: Double = 0
    @State private var isScrubbing: Bool = false

    public init(
        drama: Drama,
        episodes: [Episode],
        initialEpisodeIndex: Int = 1,
        initialPosition: Double = 0,
        initialShowControls: Bool = false,
        keepControlsVisible: Bool = false,
        initialShowDrawer: Bool = false,
        initialRestoreFocusTarget: PlayerOverlayFocusTarget? = nil,
        onDismiss: (() -> Void)? = nil,
        onSwitchSeason: ((Drama) -> Void)? = nil,
        feedActions: TVVideoFeedActions? = nil,
        focusWakeTrigger: Int = 0,
        isInteractive: Bool = true,
        preloadedPlan: PlaybackPlan? = nil
    ) {
        self.drama = drama
        self.episodes = episodes
        self.initialEpisodeIndex = initialEpisodeIndex
        self.initialPosition = initialPosition
        self.preloadedPlan = preloadedPlan
        self.focusWakeTrigger = focusWakeTrigger
        self.isInteractive = isInteractive
        _viewModel = StateObject(wrappedValue: PlayerViewModel(
            drama: drama,
            allEpisodes: episodes,
            initialEpisodeIndex: initialEpisodeIndex,
            initialPosition: initialPosition,
            initialShowControls: initialShowControls,
            keepControlsVisible: keepControlsVisible,
            initialShowDrawer: initialShowDrawer,
            initialRestoreFocusTarget: initialRestoreFocusTarget,
            preloadedPlan: preloadedPlan,
            isFeedMode: feedActions != nil
        ))
        self.onDismiss = onDismiss
        self.onSwitchSeason = onSwitchSeason
        self.feedActions = feedActions
    }

    public var body: some View {
        ZStack {
            videoSurfaceView
            danmakuOverlayView

            TVPlayerLoadingOverlay(
                isLoading: viewModel.isLoading,
                isBuffering: viewModel.isBuffering,
                isSwitchingFeed: isSwitchingFeed,
                isActuallyPlaying: viewModel.isPlaying || (viewModel.player?.timeControlStatus == .playing),
                isSeamlessTransitioning: viewModel.isSeamlessTransitioning
            )

            if let err = viewModel.errorMessage {
                TVPlayerErrorOverlay(
                    errorMessage: err,
                    isFeedMode: feedActions != nil,
                    canGoNextDrama: feedActions?.canGoNext == true,
                    onBack: { handleExit() },
                    onRetry: {
                        Task { await viewModel.preparePlayback(episodeIndex: viewModel.currentEpisodeIndex, seekTo: viewModel.currentTime) }
                    },
                    onNextDrama: { Task { _ = await nextFeedDrama() } }
                )
            }

            toastOverlayView
            quickSeekOverlayView

            if isInteractive && !viewModel.isControlsVisible && !viewModel.isEpisodeDrawerVisible && viewModel.errorMessage == nil {
                TVPlayerWakeAreaView(
                    playbackAccessibilityValue: playbackAccessibilityValue,
                    onQuickSeek: { delta in handleQuickSeek(by: delta) },
                    onPanBegan: handlePanBegan,
                    onPanChanged: handlePanChanged,
                    onPanEnded: handlePanEnded,
                    onUpCommand: {
                        if let feedActions {
                            if feedActions.canGoPrevious { feedActions.onPrevious() }
                        } else {
                            handlePreviousEpisode()
                        }
                    },
                    onDownCommand: {
                        if feedActions != nil {
                            Task { _ = await nextFeedDrama() }
                        } else {
                            handleNextEpisode()
                        }
                    },
                    onSelect: { viewModel.showControls() },
                    onMenu: onRemoteMenuPressed,
                    onMoveCommand: handlePictureMoveCommand
                )
            }

            controlsOverlayView
            TVPlayerDrawersOverlay(viewModel: viewModel)

            if viewModel.isControlsVisible, let error = accountLibrary.libraryWriteError {
                VStack { Text(error).font(.system(size: 29)).foregroundStyle(.orange).padding(24).background(.black.opacity(0.8)); Spacer() }.padding(.top, 50)
            }
        }
        .focusSection()
        .onAppear {
            isPlayerPresented = true
            if feedActions != nil {
                viewModel.restoreSavedProgress()
                viewModel.onFeedEndReached = { [weak viewModel] in
                    Task { @MainActor in _ = await self.nextFeedDrama() }
                }
            }
            viewModel.onAppear()
            viewModel.setSceneActive(scenePhase == .active)
        }
        .onDisappear {
            isPlayerPresented = false
            viewModel.onDisappear()
        }
        .onChange(of: scenePhase) { _, phase in
            let active = phase == .active && !isSwitchingFeed
            viewModel.setSceneActive(active)
        }
        .onPlayPauseCommand {
            guard !viewModel.isControlsVisible else { return }
            viewModel.togglePlayPause()
        }
        .onExitCommand(perform: onRemoteMenuPressed)
        .onMoveCommand(perform: handlePictureMoveCommand)
        .onChange(of: viewModel.switchSeasonDrama) { _, newDrama in
            if let drama = newDrama {
                viewModel.onDisappear()
                if let feedActions {
                    feedActions.onDetail(drama)
                    viewModel.switchSeasonDrama = nil
                    return
                }
                onSwitchSeason?(drama)
                presentationMode.wrappedValue.dismiss()
            }
        }
        .onChange(of: viewModel.isEpisodeDrawerVisible) { _, isVisible in
            if !isVisible { viewModel.showControls() }
        }
        .onChange(of: viewModel.isDanmakuSettingsVisible) { _, isVisible in
            if !isVisible { viewModel.showControls() }
        }
        .onChange(of: viewModel.isSpeedSheetVisible) { _, isVisible in
            if !isVisible { viewModel.showControls() }
        }
        .onChange(of: viewModel.isQualitySheetVisible) { _, isVisible in
            if !isVisible { viewModel.restoreFocusTarget = .quality; viewModel.showControls() }
        }
        .onChange(of: drama.id) { _, _ in
            Task {
                await viewModel.switchFeedDrama(
                    drama: drama,
                    allEpisodes: episodes,
                    initialEpisodeIndex: initialEpisodeIndex,
                    initialPosition: initialPosition,
                    preloadedPlan: preloadedPlan
                )
            }
        }
        .sheet(isPresented: $showingAccountSocial, onDismiss: { viewModel.showControls() }) {
            TVAccountSocialSheet(drama: viewModel.drama, episode: viewModel.currentEpisodeIndex)
        }
    }

    // MARK: - 子视图组件拆解

    @ViewBuilder
    private var videoSurfaceView: some View {
        TVTheme.backgroundGradient.ignoresSafeArea()

        if let player = viewModel.player {
            AVPlayerView(
                player: player,
                isPlaying: viewModel.wantsPlayback,
                playbackRate: Double(viewModel.playbackRate),
                videoBackgroundStyle: 0,
                onPipControllerReady: { pip in
                    viewModel.bindPictureInPictureController(pip)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        } else if !viewModel.isLoading && viewModel.errorMessage == nil {
            ZStack {
                Color.black.ignoresSafeArea()
                LinearGradient(
                    colors: [TVColors.playerTopGradient, Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var danmakuOverlayView: some View {
        if viewModel.danmakuEnabled {
            TVDanmakuView(
                danmakus: viewModel.activeDanmakus,
                position: viewModel.currentTime,
                anchor: viewModel.playbackClockDate,
                rate: Double(viewModel.playbackRate),
                moving: viewModel.isPlaying && viewModel.player?.timeControlStatus == .playing,
                style: viewModel.danmakuStyle
            )
        }
    }

    @ViewBuilder
    private var toastOverlayView: some View {
        if let toast = viewModel.toastMessage {
            VStack {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                        .font(.system(size: 20))
                    Text(toast)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.black.opacity(0.88)))
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
                .padding(.top, 48)

                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(150)
        }
    }

    @ViewBuilder
    private var quickSeekOverlayView: some View {
        if showQuickSeekIndicator {
            VStack {
                Spacer()
                TVQuickSeekIndicatorView(
                    targetTime: quickSeekTarget,
                    duration: viewModel.duration,
                    delta: quickSeekDelta,
                    isScrubbing: isScrubbing
                )
                .padding(.bottom, 96)
            }
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .zIndex(140)
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var controlsOverlayView: some View {
        if viewModel.isControlsVisible && (viewModel.errorMessage == nil || viewModel.keepControlsVisible) && !viewModel.isEpisodeDrawerVisible && !viewModel.isDanmakuSettingsVisible && !viewModel.isSpeedSheetVisible && !viewModel.isQualitySheetVisible {
            TVPlayerControlsOverlay(viewModel: viewModel, forceFocusPlayButton: viewModel.keepControlsVisible, feedActions: playerFeedActions, onSocial: HongguoAccountModel.shared.loggedIn && viewModel.drama.source == "hongguo" ? { showingAccountSocial = true } : nil) {
                handleExit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    private var playbackAccessibilityValue: String {
        let position = viewModel.currentTime.isFinite
            ? String(format: "%.0f", max(0, viewModel.currentTime.rounded(.down))) : "0"
        let state: String
        if viewModel.isPlaying {
            state = "播放中"
        } else if !viewModel.wantsPlayback {
            state = "已暂停"
        } else if viewModel.isLoading || viewModel.isBuffering {
            state = "加载中"
        } else {
            state = "已暂停"
        }
        return "\(viewModel.drama.title) · 第 \(viewModel.currentEpisodeIndex) 集 · 已播放 \(position) 秒 · \(state)"
    }

    private var playerFeedActions: TVVideoFeedActions? {
        guard let feedActions else { return nil }
        return TVVideoFeedActions(
            progressText: feedActions.progressText,
            canGoPrevious: feedActions.canGoPrevious && !isSwitchingFeed,
            canGoNext: feedActions.canGoNext && !isSwitchingFeed,
            isLoading: feedActions.isLoading || isSwitchingFeed,
            isFavorite: feedActions.isFavorite,
            errorMessage: feedActions.errorMessage,
            onPrevious: { feedActions.onPrevious() },
            onNext: { await nextFeedDrama() },
            onFavorite: feedActions.onFavorite,
            onDetail: { drama in viewModel.onDisappear(); feedActions.onDetail(drama) },
            onRefresh: { viewModel.onDisappear(); feedActions.onRefresh() }
        )
    }

    private func handlePictureMoveCommand(_ direction: MoveCommandDirection) {
        guard isInteractive, !isSwitchingFeed,
              !viewModel.isControlsVisible, !viewModel.isEpisodeDrawerVisible,
              !viewModel.isDanmakuSettingsVisible, !viewModel.isSpeedSheetVisible && !viewModel.isQualitySheetVisible else { return }
        switch direction {
        case .left:
            handleQuickSeek(by: -10)
        case .right:
            handleQuickSeek(by: 10)
        case .up:
            if let feedActions {
                if feedActions.canGoPrevious { feedActions.onPrevious() }
            } else {
                handlePreviousEpisode()
            }
        case .down:
            if feedActions != nil {
                Task { _ = await nextFeedDrama() }
            } else {
                handleNextEpisode()
            }
        default:
            break
        }
    }

    private func handlePreviousEpisode() {
        guard viewModel.currentEpisodeIndex > 1 else {
            viewModel.showToast("已经是第 1 集")
            return
        }
        viewModel.showToast("正在切换至第 \(viewModel.currentEpisodeIndex - 1) 集")
        Task { await viewModel.previousEpisode() }
    }

    private func handleNextEpisode() {
        guard viewModel.currentEpisodeIndex < viewModel.allEpisodes.count else {
            viewModel.showToast("已经是最后一集")
            return
        }
        viewModel.showToast("正在切换至第 \(viewModel.currentEpisodeIndex + 1) 集")
        Task { await viewModel.nextEpisode() }
    }

    private func onRemoteMenuPressed() {
        let now = Date().timeIntervalSince1970
        guard now - lastExitTime > 0.35 else { return }
        lastExitTime = now

        if viewModel.isDanmakuSettingsVisible {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.isDanmakuSettingsVisible = false }
            viewModel.showControls()
        } else if viewModel.isQualitySheetVisible {
            viewModel.restoreFocusTarget = .quality
            viewModel.isQualitySheetVisible = false
            viewModel.showControls()
        } else if viewModel.isSpeedSheetVisible {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.isSpeedSheetVisible = false }
            viewModel.showControls()
        } else if viewModel.isEpisodeDrawerVisible {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.isEpisodeDrawerVisible = false }
            viewModel.showControls()
        } else if viewModel.isControlsVisible {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.hideControls() }
        } else {
            handleExit()
        }
    }

    private func nextFeedDrama() async -> Bool {
        guard let feedActions, feedActions.canGoNext, !isSwitchingFeed else { return false }
        isSwitchingFeed = true
        let changed = await feedActions.onNext()
        isSwitchingFeed = false
        if !changed && isPlayerPresented {
            viewModel.setSceneActive(scenePhase == .active)
            viewModel.showControls()
        }
        return changed
    }

    private func handleExit() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            viewModel.onDisappear()
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func handleQuickSeek(by delta: Double) {
        let base = showQuickSeekIndicator ? quickSeekTarget : viewModel.currentTime
        let maxLimit = viewModel.duration > 0 ? viewModel.duration : 10000.0
        let newTarget = max(0, min(base + delta, maxLimit))
        let totalDelta = newTarget - viewModel.currentTime

        quickSeekTarget = newTarget
        quickSeekDelta = totalDelta
        withAnimation(.easeOut(duration: 0.15)) { showQuickSeekIndicator = true }
        viewModel.seekTo(target: newTarget)

        quickSeekHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { showQuickSeekIndicator = false }
        }
        quickSeekHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }

    private func handlePanBegan() {
        guard !viewModel.isControlsVisible && !viewModel.isEpisodeDrawerVisible else { return }
        initialScrubPosition = viewModel.currentTime
        quickSeekTarget = viewModel.currentTime
        quickSeekDelta = 0
        isScrubbing = true
        quickSeekHideWorkItem?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { showQuickSeekIndicator = true }
    }

    private func handlePanChanged(translationX: CGFloat) {
        guard isScrubbing, viewModel.duration > 0 else { return }
        let deltaSeconds = Double(translationX) * 0.18
        let target = max(0, min(initialScrubPosition + deltaSeconds, viewModel.duration))
        quickSeekTarget = target
        quickSeekDelta = target - initialScrubPosition
    }

    private func handlePanEnded() {
        guard isScrubbing else { return }
        isScrubbing = false
        viewModel.seekTo(target: quickSeekTarget)

        quickSeekHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { showQuickSeekIndicator = false }
        }
        quickSeekHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }
}
