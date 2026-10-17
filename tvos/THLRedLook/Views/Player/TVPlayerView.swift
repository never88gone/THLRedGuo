import SwiftUI
import AVKit

public struct TVPlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.presentationMode) var presentationMode
    @FocusState private var isWakeupFocused: Bool
    @State private var lastExitTime: TimeInterval = 0
    public var onDismiss: (() -> Void)? = nil
    public var onSwitchSeason: ((Drama) -> Void)? = nil

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
        onSwitchSeason: ((Drama) -> Void)? = nil
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
                TVDanmakuView(danmakus: viewModel.activeDanmakus)
            }

            // 正在缓冲/加载遮罩
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.8)
                    Text("正在准备视频流...")
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
                    if err.contains("找不到所请求的URL") || err.contains("404") || err.lowercased().contains("not found") {
                        return "本集暂无官方公网流（官方通常仅开放前 3~4 集免费试看）\n请返回选集切换其他集数观看"
                    }
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
                                Text("返回选集")
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

            // 自动连播倒计时浮层
            if let countdown = viewModel.nextEpisodeCountdown {
                VStack(spacing: 12) {
                    Text("即将播放第 \(viewModel.currentEpisodeIndex + 1) 集")
                        .font(.title3)
                        .bold()
                    Text("\(countdown) 秒后自动连播")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                .padding(28)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 16))
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
                .ignoresSafeArea()
                .onMoveCommand { _ in
                    viewModel.showControls()
                }
                .onExitCommand {
                    handleExit()
                }
            }

            // 遥控器悬浮控制条（有错误提示或打开选集抽屉时隐藏控制条，防止焦点冲突与视觉重叠）
            if viewModel.isControlsVisible && (viewModel.errorMessage == nil || viewModel.keepControlsVisible) && !viewModel.isEpisodeDrawerVisible {
                TVPlayerControlsOverlay(viewModel: viewModel, forceFocusPlayButton: viewModel.keepControlsVisible) {
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
        }
        .onAppear {
            viewModel.onAppear()
            if !viewModel.isControlsVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isWakeupFocused = true
                }
            }
        }
        .onDisappear {
            viewModel.onDisappear()
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

            if viewModel.isEpisodeDrawerVisible {
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
        .onChange(of: viewModel.isControlsVisible) { _, isVisible in
            if !isVisible && !viewModel.isEpisodeDrawerVisible {
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

    private func handleExit() {
        viewModel.onDisappear()
        if let onDismiss = onDismiss {
            onDismiss()
        }
        presentationMode.wrappedValue.dismiss()
    }
}
