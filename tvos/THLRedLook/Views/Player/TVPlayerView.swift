import SwiftUI
import AVKit

public struct TVPlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.presentationMode) var presentationMode
    @FocusState private var isWakeupFocused: Bool
    @State private var lastExitTime: TimeInterval = 0
    public var onDismiss: (() -> Void)? = nil
    public var onSwitchSeason: ((Drama) -> Void)? = nil

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
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundColor(.yellow)
                    Text("播放失败：\(err)")
                        .font(.headline)
                        .foregroundColor(.white)
                    HStack(spacing: 16) {
                        TVButton(title: "重试", isProminent: true) {
                            Task {
                                await viewModel.preparePlayback(episodeIndex: viewModel.currentEpisodeIndex, seekTo: viewModel.currentTime)
                            }
                        }
                        TVButton(title: "退出") {
                            handleExit()
                        }
                    }
                }
                .padding(40)
                .background(Color.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 16))
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

            // 纯画面播放模式下的遥控器唤醒交互层（点击 Select 呼出浮层，按 Menu 直接退出播放）
            if !viewModel.isControlsVisible && !viewModel.isEpisodeDrawerVisible {
                Button(action: {
                    viewModel.showControls()
                }) {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(TvTransparentButtonStyle())
                .focused($isWakeupFocused)
                .ignoresSafeArea()
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
    }

    private func handleExit() {
        viewModel.onDisappear()
        if let onDismiss = onDismiss {
            onDismiss()
        }
        presentationMode.wrappedValue.dismiss()
    }
}
