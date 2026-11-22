import SwiftUI
import AVKit

public struct TVPlayerView: View {
    @ObservedObject internal var accountLibrary = HongguoAccountModel.shared
    @StateObject internal var viewModel: PlayerViewModel
    @Environment(\.presentationMode) internal var presentationMode
    @Environment(\.scenePhase) internal var scenePhase
    @State internal var lastExitTime: TimeInterval = 0
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
    @State internal var isSwitchingFeed = false
    @State internal var isPlayerPresented = false
    @State internal var quickSeekDelta: Double = 0
    @State internal var quickSeekTarget: Double = 0
    @State internal var showQuickSeekIndicator: Bool = false
    @State internal var quickSeekHideWorkItem: DispatchWorkItem?
    @State internal var initialScrubPosition: Double = 0
    @State internal var isScrubbing: Bool = false

    public init(
        drama: Drama,
        episodes: [Episode],
        initialEpisodeIndex: Int = 1,
        initialPosition: Double = 0,
        initialShowControls: Bool = false,
        keepControlsVisible: Bool = false,
        initialShowDrawer: Bool = false,
        initialShowCommentDrawer: Bool = false,
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
            initialShowCommentDrawer: initialShowCommentDrawer,
            initialRestoreFocusTarget: initialRestoreFocusTarget,
            preloadedPlan: preloadedPlan,
            isFeedMode: feedActions != nil
        ))
        self.onDismiss = onDismiss
        self.onSwitchSeason = onSwitchSeason
        self.feedActions = feedActions
    }

    public var body: some View {
        Group {
            if feedActions == nil {
                // MARK: - 全屏常规播放模式（对齐 ATV-Bilibili-demo 与系统 AVPlayer 质感）
                ZStack {
                    videoSurfaceView
                    danmakuOverlayView

                    TVPlayerLoadingOverlay(
                        isLoading: viewModel.isLoading,
                        isBuffering: viewModel.isBuffering,
                        isSwitchingFeed: false,
                        isActuallyPlaying: viewModel.isPlaying || (viewModel.player?.timeControlStatus == .playing),
                        isSeamlessTransitioning: false
                    )

                    if let err = viewModel.errorMessage {
                        TVPlayerErrorOverlay(
                            errorMessage: err,
                            isFeedMode: false,
                            canGoNextDrama: false,
                            onBack: { handleExit() },
                            onRetry: {
                                Task { await viewModel.preparePlayback(episodeIndex: viewModel.currentEpisodeIndex, seekTo: viewModel.currentTime) }
                            },
                            onNextDrama: {}
                        )
                    }

                    toastOverlayView
                    quickSeekOverlayView

                    if isInteractive && !viewModel.isControlsVisible && viewModel.errorMessage == nil {
                        TVPlayerWakeAreaView(
                            playbackAccessibilityValue: playbackAccessibilityValue,
                            onQuickSeek: { delta in handleQuickSeek(by: delta) },
                            onPanBegan: handlePanBegan,
                            onPanChanged: handlePanChanged,
                            onPanEnded: handlePanEnded,
                            onUpCommand: { handlePreviousEpisode() },
                            onDownCommand: { handleNextEpisode() },
                            onSelect: { viewModel.showControls() },
                            onMenu: onRemoteMenuPressed,
                            onMoveCommand: handlePictureMoveCommand
                        )
                    }

                    controlsOverlayView
                }
                .focusSection()
                .onPlayPauseCommand {
                    guard !viewModel.isControlsVisible else { return }
                    viewModel.togglePlayPause()
                }
                .onExitCommand(perform: onRemoteMenuPressed)
                .onMoveCommand(perform: handlePictureMoveCommand)
            } else {
                // MARK: - 信息流上下滑切剧模式
                feedPlayerView
            }
        }
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
    }

    @ViewBuilder
    private var feedPlayerView: some View {
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
                    isFeedMode: true,
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
                        if let feedActions, feedActions.canGoPrevious { feedActions.onPrevious() }
                    },
                    onDownCommand: {
                        Task { _ = await nextFeedDrama() }
                    },
                    onSelect: { viewModel.showControls() },
                    onMenu: onRemoteMenuPressed,
                    onMoveCommand: handlePictureMoveCommand
                )
            }

            controlsOverlayView
            TVPlayerDrawersOverlay(viewModel: viewModel)
        }
        .focusSection()
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
                TVColors.black.ignoresSafeArea()
                LinearGradient(
                    colors: [TVColors.playerTopGradient, TVColors.black],
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
                        .foregroundColor(TVColors.yellow)
                        .font(.system(size: 20))
                    Text(toast)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(TVColors.white)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Capsule().fill(TVColors.black.opacity(0.88)))
                .overlay(Capsule().stroke(TVColors.white.opacity(0.2), lineWidth: 1))
                .shadow(color: TVColors.black.opacity(0.6), radius: 12, y: 6)
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
            TVPlayerControlsOverlay(viewModel: viewModel, forceFocusPlayButton: viewModel.keepControlsVisible, feedActions: playerFeedActions) {
                handleExit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }
}

// MARK: - 预览
#Preview {
    TVPlayerView(
        drama: Drama(id: "1", title: "测试短剧", cover: "", episodes: 20, tags: []),
        episodes: [Episode(id: "1", title: "第 1 集", number: 1)]
    )
    .background(TVColors.background)
}
