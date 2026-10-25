import SwiftUI
import AVKit

private enum PlayerWakeFocusArea: Hashable {
    case leftSeek
    case centerWake
    case rightSeek
}

public struct TVPlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var activeWakeFocus: PlayerWakeFocusArea?
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
            preloadedPlan: preloadedPlan
        ))
        self.onDismiss = onDismiss
        self.onSwitchSeason = onSwitchSeason
        self.feedActions = feedActions
    }

    public var body: some View {
        let content = ZStack {
            videoSurfaceView
            danmakuOverlayView
            loadingOverlayView
            errorOverlayView
            toastOverlayView
            quickSeekOverlayView
            wakeButtonView
            controlsOverlayView
            drawersOverlayView
        }
        .focusSection()
        .defaultFocus($activeWakeFocus, isInteractive ? .centerWake : nil)

        let withEvents = applyEventHandlers(to: content)
        return applyStateListeners(to: withEvents)
    }

    // MARK: - 子视图组件拆解（消除复杂泛型嵌套，避免 Release 编译类型推断耗时超标）

    @ViewBuilder
    private var videoSurfaceView: some View {
        TVTheme.backgroundGradient.ignoresSafeArea()

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
    private var loadingOverlayView: some View {
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
    }

    @ViewBuilder
    private var errorOverlayView: some View {
        if let err = viewModel.errorMessage {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.yellow)
                Text("播放失败：\(err)")
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
    private var wakeButtonView: some View {
        if isInteractive && !viewModel.isControlsVisible && !viewModel.isEpisodeDrawerVisible && viewModel.errorMessage == nil {
            ZStack {
                TVRemoteTouchSurfaceView(
                    accessibilityValue: playbackAccessibilityValue,
                    onPanBegan: handlePanBegan,
                    onPanChanged: handlePanChanged,
                    onPanEnded: handlePanEnded,
                    onLeftArrow: { handleQuickSeek(by: -10) },
                    onRightArrow: { handleQuickSeek(by: 10) },
                    onSelect: { viewModel.showControls() },
                    onPlayPause: { viewModel.togglePlayPause() },
                    onMenu: { onRemoteMenuPressed() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 0) {
                    // 左侧步进快退锚点
                    Button(action: {
                        handleQuickSeek(by: -10)
                    }) {
                        Color.black.opacity(0.001)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TVZeroHighlightButtonStyle())
                    .focusEffectDisabled()
                    .focused($activeWakeFocus, equals: .leftSeek)
                    .onExitCommand(perform: onRemoteMenuPressed)
                    .accessibilityIdentifier("player.directRewind")
                    .frame(width: 120)

                    // 中间主唤醒层（对应 player.wake，按 Select 唤出控制浮层）
                    Button(action: {
                        viewModel.showControls()
                    }) {
                        Color.black.opacity(0.001)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TVZeroHighlightButtonStyle())
                    .focusEffectDisabled()
                    .focused($activeWakeFocus, equals: .centerWake)
                    .accessibilityIdentifier("player.wake")
                    .accessibilityLabel("显示播放控制")
                    .accessibilityValue(playbackAccessibilityValue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onPlayPauseCommand {
                        viewModel.togglePlayPause()
                    }
                    .onExitCommand(perform: onRemoteMenuPressed)
                    .onMoveCommand(perform: handlePictureMoveCommand)

                    // 右侧步进快进锚点
                    Button(action: {
                        handleQuickSeek(by: 10)
                    }) {
                        Color.black.opacity(0.001)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TVZeroHighlightButtonStyle())
                    .focusEffectDisabled()
                    .focused($activeWakeFocus, equals: .rightSeek)
                    .onExitCommand(perform: onRemoteMenuPressed)
                    .accessibilityIdentifier("player.directForward")
                    .frame(width: 120)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .onChange(of: activeWakeFocus) { _, newFocus in
                if newFocus == .leftSeek {
                    handleQuickSeek(by: -10)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        activeWakeFocus = .centerWake
                    }
                } else if newFocus == .rightSeek {
                    handleQuickSeek(by: 10)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        activeWakeFocus = .centerWake
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var controlsOverlayView: some View {
        if viewModel.isControlsVisible && (viewModel.errorMessage == nil || viewModel.keepControlsVisible) && !viewModel.isEpisodeDrawerVisible && !viewModel.isDanmakuSettingsVisible && !viewModel.isSpeedSheetVisible {
            TVPlayerControlsOverlay(viewModel: viewModel, forceFocusPlayButton: viewModel.keepControlsVisible, feedActions: playerFeedActions) {
                handleExit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var drawersOverlayView: some View {
        if viewModel.isEpisodeDrawerVisible {
            TVEpisodeDrawer(viewModel: viewModel, isPresented: $viewModel.isEpisodeDrawerVisible)
                .ignoresSafeArea()
                .zIndex(100)
        }

        if viewModel.isDanmakuSettingsVisible {
            TVDanmakuSettingsDrawer(viewModel: viewModel, isPresented: $viewModel.isDanmakuSettingsVisible)
                .ignoresSafeArea()
                .zIndex(100)
        }

        if viewModel.isSpeedSheetVisible {
            TVSpeedSelectionDrawer(viewModel: viewModel, isPresented: $viewModel.isSpeedSheetVisible)
                .ignoresSafeArea()
                .zIndex(100)
        }
    }

    // MARK: - 事件监听与遥控器交互解耦

    private func applyEventHandlers<Content: View>(to content: Content) -> some View {
        content
            .onAppear {
                isPlayerPresented = true
                if feedActions != nil { viewModel.restoreSavedProgress() }
                viewModel.onAppear()
                viewModel.setSceneActive(scenePhase == .active)
                if isInteractive && !viewModel.isControlsVisible {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        activeWakeFocus = .centerWake
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
            .onPlayPauseCommand {
                viewModel.togglePlayPause()
            }
            .onExitCommand(perform: onRemoteMenuPressed)
            .onMoveCommand(perform: handlePictureMoveCommand)
    }

    private func handlePictureMoveCommand(_ direction: MoveCommandDirection) {
        guard isInteractive, !isSwitchingFeed,
              !viewModel.isControlsVisible, !viewModel.isEpisodeDrawerVisible,
              !viewModel.isDanmakuSettingsVisible, !viewModel.isSpeedSheetVisible else { return }
        switch direction {
        case .left:
            handleQuickSeek(by: -10)
        case .right:
            handleQuickSeek(by: 10)
        case .up:
            if let feedActions, feedActions.canGoPrevious { feedActions.onPrevious() }
        case .down:
            if feedActions != nil { Task { _ = await nextFeedDrama() } }
        default:
            break
        }
    }

    private func applyStateListeners<Content: View>(to content: Content) -> some View {
        content
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
            .onChange(of: viewModel.isControlsVisible) { _, isVisible in
                guard isInteractive else { return }
                if !isVisible && !viewModel.isEpisodeDrawerVisible && !viewModel.isDanmakuSettingsVisible && !viewModel.isSpeedSheetVisible {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { activeWakeFocus = .centerWake }
                }
            }
            .onChange(of: isInteractive) { _, interactive in
                if !interactive {
                    activeWakeFocus = nil
                } else if !viewModel.isControlsVisible && !viewModel.isEpisodeDrawerVisible && !viewModel.isDanmakuSettingsVisible && !viewModel.isSpeedSheetVisible {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { activeWakeFocus = .centerWake }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { activeWakeFocus = .centerWake }
                }
            }
            .onChange(of: focusWakeTrigger) { _, _ in
                guard isInteractive else { return }
                if !viewModel.isControlsVisible && !viewModel.isEpisodeDrawerVisible && !viewModel.isDanmakuSettingsVisible && !viewModel.isSpeedSheetVisible {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { activeWakeFocus = .centerWake }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { activeWakeFocus = .centerWake }
                }
            }
            .onChange(of: viewModel.errorMessage) { _, newErr in
                if newErr != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { errorFocusTarget = .backToEpisodes }
                }
            }
            .onChange(of: drama.id) { _, newId in
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

    private func onRemoteMenuPressed() {
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
        let val = "\(viewModel.drama.title) · 第 \(viewModel.currentEpisodeIndex) 集 · 已播放 \(position) 秒 · \(state)"
        NSLog("📺 [WAKE_VALUE] %@", val)
        return val
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
        activeWakeFocus = nil
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            viewModel.onDisappear()
            presentationMode.wrappedValue.dismiss()
        }
    }

    // MARK: - 快捷进度与遥控器触控板手势处理

    private func handleQuickSeek(by delta: Double) {
        let base = showQuickSeekIndicator ? quickSeekTarget : viewModel.currentTime
        let maxLimit = viewModel.duration > 0 ? viewModel.duration : 10000.0
        let newTarget = max(0, min(base + delta, maxLimit))
        let totalDelta = newTarget - viewModel.currentTime
        print("THL_HANDLE_QUICK_SEEK: delta=\(delta), base=\(base), newTarget=\(newTarget), duration=\(viewModel.duration)")

        quickSeekTarget = newTarget
        quickSeekDelta = totalDelta
        withAnimation(.easeOut(duration: 0.15)) {
            showQuickSeekIndicator = true
        }

        viewModel.seekTo(target: newTarget)

        quickSeekHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) {
                showQuickSeekIndicator = false
            }
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
        withAnimation(.easeOut(duration: 0.15)) {
            showQuickSeekIndicator = true
        }
    }

    private func handlePanChanged(translationX: CGFloat) {
        guard isScrubbing, viewModel.duration > 0 else { return }
        // 触控表面手势映射：灵敏平滑，滑动可快速跨度调整视频进度
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
            withAnimation(.easeInOut(duration: 0.25)) {
                showQuickSeekIndicator = false
            }
        }
        quickSeekHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }
}

// MARK: - 快捷调进度悬浮提示组件

public struct TVQuickSeekIndicatorView: View {
    public let targetTime: Double
    public let duration: Double
    public let delta: Double
    public let isScrubbing: Bool

    public var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: delta >= 0 ? "goforward" : "gobackward")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(TVTheme.primary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formatTime(targetTime))
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("/ \(formatTime(duration))")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(TVTheme.textSecondary)
                    }

                    Text(delta >= 0 ? (isScrubbing ? "滑动快进 +\(Int(delta))s" : "快进 +\(Int(delta))s") : (isScrubbing ? "滑动快退 \(Int(delta))s" : "快退 \(Int(delta))s"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(TVTheme.primary)
                }
            }

            // 微缩高精进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)

                    let progress = duration > 0 ? max(0, min(targetTime / duration, 1.0)) : 0
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [TVTheme.primary, TVTheme.primaryHover],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * CGFloat(progress)), height: 6)
                }
            }
            .frame(width: 300, height: 6)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 22)
        .background(
            Material.regular
        )
        .background(
            Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.92)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.85), radius: 28, x: 0, y: 10)
        .accessibilityIdentifier("player.quickSeek")
    }

    private func formatTime(_ sec: Double) -> String {
        guard !sec.isNaN && sec >= 0 else { return "00:00" }
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 遥控器触控板滑动与手势捕获组件 (tvOS Siri Remote Touch & Gesture Surface)

public struct TVRemoteTouchSurfaceView: UIViewRepresentable {
    public var accessibilityValue: String? = nil
    public var onPanBegan: () -> Void
    public var onPanChanged: (CGFloat) -> Void
    public var onPanEnded: () -> Void
    public var onLeftArrow: (() -> Void)? = nil
    public var onRightArrow: (() -> Void)? = nil
    public var onSelect: (() -> Void)? = nil
    public var onPlayPause: (() -> Void)? = nil
    public var onMenu: (() -> Void)? = nil

    public func makeUIView(context: Context) -> TVTouchCapturingView {
        let view = TVTouchCapturingView()
        updateProps(view)
        return view
    }

    public func updateUIView(_ uiView: TVTouchCapturingView, context: Context) {
        updateProps(uiView)
    }

    private func updateProps(_ view: TVTouchCapturingView) {
        view.accessibilityValue = accessibilityValue
        view.onPanBegan = onPanBegan
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onSelect = onSelect
        view.onPlayPause = onPlayPause
        view.onMenu = onMenu
    }
}

public class TVTouchCapturingView: UIView, UIGestureRecognizerDelegate {
    var onPanBegan: (() -> Void)?
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onSelect: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onMenu: (() -> Void)?

    public override var canBecomeFocused: Bool {
        return false
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = false

        // 1. Siri Remote 触控表面滑动手势
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        // 2. 遥控器 Left 按键专用手势
        let leftTap = UITapGestureRecognizer(target: self, action: #selector(handleLeftPress))
        leftTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.leftArrow.rawValue)]
        leftTap.cancelsTouchesInView = false
        leftTap.delegate = self
        addGestureRecognizer(leftTap)

        // 3. 遥控器 Right 按键专用手势
        let rightTap = UITapGestureRecognizer(target: self, action: #selector(handleRightPress))
        rightTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.rightArrow.rawValue)]
        rightTap.cancelsTouchesInView = false
        rightTap.delegate = self
        addGestureRecognizer(rightTap)

        // 4. 遥控器 Select 确认按键手势
        let selectTap = UITapGestureRecognizer(target: self, action: #selector(handleSelectPress))
        selectTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        selectTap.cancelsTouchesInView = false
        selectTap.delegate = self
        addGestureRecognizer(selectTap)

        // 5. 遥控器 Play/Pause 按键手势
        let playPauseTap = UITapGestureRecognizer(target: self, action: #selector(handlePlayPausePress))
        playPauseTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        playPauseTap.cancelsTouchesInView = false
        playPauseTap.delegate = self
        addGestureRecognizer(playPauseTap)

        // 6. 遥控器 Menu 按键手势
        let menuTap = UITapGestureRecognizer(target: self, action: #selector(handleMenuPress))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        menuTap.cancelsTouchesInView = false
        menuTap.delegate = self
        addGestureRecognizer(menuTap)

        // 7. 遥控器触控板轻扫手势 (Swipe Right: 快进, Swipe Left: 快退)
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleRightPress))
        swipeRight.direction = .right
        swipeRight.cancelsTouchesInView = false
        swipeRight.delegate = self
        addGestureRecognizer(swipeRight)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleLeftPress))
        swipeLeft.direction = .left
        swipeLeft.cancelsTouchesInView = false
        swipeLeft.delegate = self
        addGestureRecognizer(swipeLeft)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleMenuPress() {
        print("THL_GESTURE_MENU_PRESS_CAPTURED")
        onMenu?()
    }

    @objc private func handleLeftPress() {
        print("THL_GESTURE_LEFT_PRESS_CAPTURED")
        onLeftArrow?()
    }

    @objc private func handleRightPress() {
        print("THL_GESTURE_RIGHT_PRESS_CAPTURED")
        onRightArrow?()
    }

    @objc private func handleSelectPress() {
        print("THL_GESTURE_SELECT_PRESS_CAPTURED")
        onSelect?()
    }

    @objc private func handlePlayPausePress() {
        print("THL_GESTURE_PLAYPAUSE_PRESS_CAPTURED")
        onPlayPause?()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onPanBegan?()
        case .changed:
            let translation = recognizer.translation(in: self)
            onPanChanged?(translation.x)
        case .ended, .cancelled:
            onPanEnded?()
        default:
            break
        }
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.type {
            case .leftArrow:
                print("THL_PRESSES_BEGAN_LEFT_ARROW")
                onLeftArrow?()
                handled = true
            case .rightArrow:
                print("THL_PRESSES_BEGAN_RIGHT_ARROW")
                onRightArrow?()
                handled = true
            case .select:
                print("THL_PRESSES_BEGAN_SELECT")
                onSelect?()
                handled = true
            case .playPause:
                print("THL_PRESSES_BEGAN_PLAY_PAUSE")
                onPlayPause?()
                handled = true
            case .menu:
                print("THL_PRESSES_BEGAN_MENU")
                if let onMenu {
                    onMenu()
                    handled = true
                }
            default:
                break
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
}
