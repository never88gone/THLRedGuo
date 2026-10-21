import SwiftUI
import AVKit

public struct TVPlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isWakeupFocused: Bool
    @State private var lastExitTime: TimeInterval = 0
    public var onDismiss: (() -> Void)? = nil
    public var onSwitchSeason: ((Drama) -> Void)? = nil
    public var feedActions: TVVideoFeedActions?
    @State private var isSwitchingFeed = false
    @State private var isPlayerPresented = false

    enum PlayerErrorFocusTarget: Hashable {
        case backToEpisodes
        case retry
    }
    @FocusState private var errorFocusTarget: PlayerErrorFocusTarget?

    public init(
        drama: Drama,
        episodes: [Episode],
        initialEpisodeIndex: Int = 1,
        initialPosition: Double = 0,
        initialShowControls: Bool = true,
        keepControlsVisible: Bool = false,
        initialShowDrawer: Bool = false,
        onDismiss: (() -> Void)? = nil,
        onSwitchSeason: ((Drama) -> Void)? = nil,
        feedActions: TVVideoFeedActions? = nil
    ) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(
            drama: drama,
            allEpisodes: episodes,
            initialEpisodeIndex: initialEpisodeIndex,
            initialPosition: initialPosition,
            initialShowControls: initialShowControls,
            keepControlsVisible: keepControlsVisible,
            initialShowDrawer: initialShowDrawer
        ))
        self.onDismiss = onDismiss
        self.onSwitchSeason = onSwitchSeason
        self.feedActions = feedActions
    }

    public var body: some View {
        ZStack {
            TVTheme.backgroundGradient.ignoresSafeArea()

            // 视频画面渲染：采用纯净解耦的底层 AVPlayerView，不拦截系统焦点与遥控器事件
            if let player = viewModel.player {
                AVPlayerView(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else if !viewModel.isLoading && viewModel.errorMessage == nil {
                ZStack {
                    Color.black.ignoresSafeArea()
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.04, blue: 0.08), Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    ).ignoresSafeArea()
                }
            }

            // 弹幕层
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

            // 正在缓冲/加载遮罩
            if (viewModel.isLoading || viewModel.isBuffering || isSwitchingFeed) && !viewModel.isSeamlessTransitioning {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.8)
                    Text(isSwitchingFeed ? "正在切换推荐…" : viewModel.isLoading ? "正在准备视频流..." : "正在缓冲...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // 播放错误提示
            if let err = viewModel.errorMessage {
                let friendlyMsg: String = {
                    return "播放失败：\(err)"
                }()

                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow)
                    Text(friendlyMsg)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .lineSpacing(6)
                        .padding(.horizontal, 24)

                    HStack(spacing: 24) {
                        Button(action: {
                            handleExit()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.backward.circle.fill")
                                Text(feedActions == nil ? "返回选集" : "返回推荐")
                            }
                            .font(.system(size: 18, weight: .bold))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(errorFocusTarget == .backToEpisodes ? TVTheme.primaryHover : TVTheme.primary)
                            )
                            .foregroundColor(.white)
                            .tvFocusBorder(isFocused: errorFocusTarget == .backToEpisodes, cornerRadius: 14)
                        }
                        .buttonStyle(TVZeroHighlightButtonStyle())
                        .focused($errorFocusTarget, equals: .backToEpisodes)

                        Button(action: {
                            Task {
                                await viewModel.preparePlayback(episodeIndex: viewModel.currentEpisodeIndex, seekTo: viewModel.currentTime)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("重试")
                            }
                            .font(.system(size: 18, weight: .bold))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(errorFocusTarget == .retry ? TVTheme.surfaceFocused : TVTheme.surfaceCard)
                            )
                            .foregroundColor(.white)
                            .tvFocusBorder(isFocused: errorFocusTarget == .retry, cornerRadius: 14)
                        }
                        .buttonStyle(TVZeroHighlightButtonStyle())
                        .focused($errorFocusTarget, equals: .retry)
                        if let feedActions, feedActions.canGoNext {
                            Button("下一部") { Task { _ = await nextFeedDrama() } }
                                .accessibilityIdentifier("player.errorNextDrama")
                        }
                    }
                }
                .padding(40)
                .background(Color.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.8), radius: 30)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        errorFocusTarget = .backToEpisodes
                    }
                }
            }



            // 轻量状态提示 Toast 浮层（救流/切换模式提示，不阻断观看）
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
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.88))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
                    .padding(.top, 48)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(150)
            }

            // 纯画面播放模式下的遥控器唤醒交互层（点击 Select 或任何方向键呼出浮层，按 Menu 直接退出播放）
            if !viewModel.isControlsVisible && !viewModel.isEpisodeDrawerVisible && viewModel.errorMessage == nil {
                Button(action: {
                    viewModel.showControls()
                }) {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(TvTransparentButtonStyle())
                .focused($isWakeupFocused)
                .accessibilityIdentifier("player.wake")
                .accessibilityLabel("显示播放控制")
                .accessibilityValue(playbackAccessibilityValue)
                .ignoresSafeArea()
                .onMoveCommand { direction in
                    if feedActions != nil && direction == .down {
                        Task { _ = await nextFeedDrama() }
                    } else if let feedActions, direction == .up, feedActions.canGoPrevious {
                        viewModel.onDisappear()
                        feedActions.onPrevious()
                    } else {
                        viewModel.showControls()
                    }
                }

            }

            // 遥控器悬浮控制条（有错误提示或打开抽屉时隐藏控制条，防止焦点冲突与视觉重叠）
            if viewModel.isControlsVisible && (viewModel.errorMessage == nil || viewModel.keepControlsVisible) && !viewModel.isEpisodeDrawerVisible && !viewModel.isDanmakuSettingsVisible && !viewModel.isSpeedSheetVisible {
                TVPlayerControlsOverlay(viewModel: viewModel, forceFocusPlayButton: viewModel.keepControlsVisible, feedActions: playerFeedActions) {
                    handleExit()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            // 选集抽屉
            if viewModel.isEpisodeDrawerVisible {
                TVEpisodeDrawer(viewModel: viewModel, isPresented: $viewModel.isEpisodeDrawerVisible)
                    .ignoresSafeArea()
                    .zIndex(100)
            }

            // 弹幕设置抽屉
            if viewModel.isDanmakuSettingsVisible {
                TVDanmakuSettingsDrawer(viewModel: viewModel, isPresented: $viewModel.isDanmakuSettingsVisible)
                    .ignoresSafeArea()
                    .zIndex(100)
            }

            // 倍速选择抽屉
            if viewModel.isSpeedSheetVisible {
                TVSpeedSelectionDrawer(viewModel: viewModel, isPresented: $viewModel.isSpeedSheetVisible)
                    .ignoresSafeArea()
                    .zIndex(100)
            }
        }
        .onAppear {
            isPlayerPresented = true
            if feedActions != nil { viewModel.restoreSavedProgress() }
            viewModel.onAppear()
            viewModel.setSceneActive(scenePhase == .active)
            if !viewModel.isControlsVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isWakeupFocused = true
                }
            }
        }
        .onDisappear {
            isPlayerPresented = false
            viewModel.onDisappear()
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.setSceneActive(phase == .active && !isSwitchingFeed)
        }
        // 遥控器硬件 Play/Pause 按键直接映射
        .onPlayPauseCommand {
            viewModel.togglePlayPause()
        }
        // 遥控器 Menu 退出逻辑（带有时间戳防抖，优先关闭抽屉与控制条，绝不误穿透退出播放）
        .onExitCommand {
            let now = Date().timeIntervalSince1970
            guard now - lastExitTime > 0.35 else { return }
            lastExitTime = now

            if viewModel.isDanmakuSettingsVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isDanmakuSettingsVisible = false
                }
                viewModel.showControls()
            } else if viewModel.isSpeedSheetVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isSpeedSheetVisible = false
                }
                viewModel.showControls()
            } else if viewModel.isEpisodeDrawerVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isEpisodeDrawerVisible = false
                }
                viewModel.showControls()
            } else if viewModel.isControlsVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.hideControls()
                }
            } else {
                handleExit()
            }
        }
        .onChange(of: viewModel.switchSeasonDrama) { _, newDrama in
            if let drama = newDrama {
                viewModel.onDisappear()
                if let feedActions {
                    feedActions.onDetail(drama)
                    viewModel.switchSeasonDrama = nil
                    return
                }
                if let onSwitchSeason = onSwitchSeason {
                    onSwitchSeason(drama)
                }
                presentationMode.wrappedValue.dismiss()
            }
        }
        .onChange(of: viewModel.isEpisodeDrawerVisible) { _, isVisible in
            if !isVisible {
                viewModel.showControls()
            }
        }
        .onChange(of: viewModel.isDanmakuSettingsVisible) { _, isVisible in
            if !isVisible {
                viewModel.showControls()
            }
        }
        .onChange(of: viewModel.isSpeedSheetVisible) { _, isVisible in
            if !isVisible {
                viewModel.showControls()
            }
        }
        .onChange(of: viewModel.isControlsVisible) { _, isVisible in
            if !isVisible && !viewModel.isEpisodeDrawerVisible && !viewModel.isDanmakuSettingsVisible && !viewModel.isSpeedSheetVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isWakeupFocused = true
                }
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newErr in
            if newErr != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    errorFocusTarget = .backToEpisodes
                }
            }
        }
    }

    private var playbackAccessibilityValue: String {
        let position = viewModel.currentTime.isFinite
            ? String(format: "%.0f", max(0, viewModel.currentTime.rounded(.down))) : "0"
        let state = viewModel.isPlaying ? "播放中" : viewModel.isLoading || viewModel.isBuffering ? "加载中" : "已暂停"
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
            onPrevious: { viewModel.onDisappear(); feedActions.onPrevious() },
            onNext: { await nextFeedDrama() },
            onFavorite: feedActions.onFavorite,
            onDetail: { drama in viewModel.onDisappear(); feedActions.onDetail(drama) },
            onRefresh: { viewModel.onDisappear(); feedActions.onRefresh() }
        )
    }

    private func nextFeedDrama() async -> Bool {
        guard let feedActions, feedActions.canGoNext, !isSwitchingFeed else { return false }
        isSwitchingFeed = true
        viewModel.setSceneActive(false)
        let changed = await feedActions.onNext()
        isSwitchingFeed = false
        if changed {
            viewModel.onDisappear()
        } else if isPlayerPresented {
            viewModel.setSceneActive(scenePhase == .active)
            viewModel.showControls()
        }
        return changed
    }

    private func handleExit() {
        viewModel.onDisappear()
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }
}
