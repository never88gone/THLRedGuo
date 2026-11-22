import SwiftUI

/// 播放器 Transport Bar 主控条（对齐 Apple TV 原生 AVPlayer 控制风格）
public struct TVPlayerTransportBar: View {
    @ObservedObject public var viewModel: PlayerViewModel
    @FocusState private var focusedButton: PlayerOverlayFocusTarget?

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 20) {
            // MARK: - 原生风格进度条 (Scrubber Bar)
            HStack(spacing: 16) {
                Text(formatTime(viewModel.currentTime))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(TVColors.white)
                    .frame(width: 80, alignment: .trailing)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // 背景底槽
                        Capsule()
                            .fill(TVColors.transportBarScrubberBg)
                            .frame(height: 8)

                        // 缓冲进度条
                        Capsule()
                            .fill(TVColors.transportBarScrubberBuffer)
                            .frame(
                                width: viewModel.duration > 0
                                    ? geo.size.width * CGFloat(min(1.0, max(0, (viewModel.currentTime + 8) / viewModel.duration)))
                                    : 0,
                                height: 8
                            )

                        // 实际已播放进度条
                        Capsule()
                            .fill(TVColors.activeRed)
                            .frame(
                                width: viewModel.duration > 0
                                    ? geo.size.width * CGFloat(min(1.0, max(0, viewModel.currentTime / viewModel.duration)))
                                    : 0,
                                height: 8
                            )
                    }
                }
                .frame(height: 8)

                Text(formatTime(viewModel.duration))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(TVColors.textSecondary)
                    .frame(width: 80, alignment: .leading)
            }
            .padding(.horizontal, 48)

            // MARK: - 核心播放按键组 (居中对称排列，贴合系统 AVPlayer 质感)
            HStack(spacing: 28) {
                // 1. 上一集
                transportButton(
                    id: .prevEpisode,
                    icon: "backward.end.fill",
                    label: "上一集",
                    disabled: viewModel.currentEpisodeIndex <= 1
                ) {
                    Task { await viewModel.previousEpisode() }
                }

                // 2. 快退 10 秒
                transportButton(
                    id: .seekBackward,
                    icon: "gobackward.10",
                    label: "快退10秒"
                ) {
                    viewModel.seekBy(seconds: -10)
                }

                // 3. 核心大播放/暂停主键
                Button(action: {
                    viewModel.togglePlayPause()
                }) {
                    ZStack {
                        Circle()
                            .fill(TVColors.prominentGradient)
                            .frame(width: 72, height: 72)
                            .shadow(color: TVColors.focusedShadowColor, radius: 10, y: 4)

                        Image(systemName: viewModel.wantsPlayback ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(TVColors.white)
                    }
                    .overlay(
                        Circle()
                            .stroke(
                                focusedButton == .playPause
                                    ? TVColors.liquidGlassActiveBorder
                                    : TVColors.clear,
                                lineWidth: 3.5
                            )
                    )
                    .scaleEffect(focusedButton == .playPause ? 1.15 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: focusedButton)
                }
                .buttonStyle(.card)
                .focused($focusedButton, equals: .playPause)
                .accessibilityLabel(viewModel.wantsPlayback ? "暂停" : "播放")

                // 4. 快进 10 秒
                transportButton(
                    id: .seekForward,
                    icon: "goforward.10",
                    label: "快进10秒"
                ) {
                    viewModel.seekBy(seconds: 10)
                }

                // 5. 下一集
                transportButton(
                    id: .nextEpisode,
                    icon: "forward.end.fill",
                    label: "下一集",
                    disabled: viewModel.currentEpisodeIndex >= viewModel.allEpisodes.count
                ) {
                    Task { await viewModel.nextEpisode() }
                }

                // 6. 画中画
                transportButton(
                    id: .pip,
                    icon: "pip.enter",
                    label: "画中画"
                ) {
                    viewModel.startPictureInPicture()
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func transportButton(
        id: PlayerOverlayFocusTarget,
        icon: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(disabled ? TVColors.textMuted : TVColors.white)
                .frame(width: 54, height: 54)
                .background(TVColors.panelCardBg)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            focusedButton == id
                                ? TVColors.liquidGlassActiveBorder
                                : TVColors.liquidGlassBorder,
                            lineWidth: focusedButton == id ? 2.5 : 1
                        )
                )
                .scaleEffect(focusedButton == id ? 1.12 : 1.0)
                .animation(.easeOut(duration: 0.15), value: focusedButton)
        }
        .buttonStyle(.card)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
        .focused($focusedButton, equals: id)
        .accessibilityLabel(label)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 预览
#Preview("TVPlayerTransportBar") {
    struct PreviewContainer: View {
        var body: some View {
            let drama = Drama(id: "preview_1", title: "逆天龙皇", cover: "", episodes: 80)
            let vm = PlayerViewModel(drama: drama, allEpisodes: [])
            vm.duration = 120
            vm.currentTime = 45
            return TVPlayerTransportBar(viewModel: vm)
                .padding(40)
                .background(TVColors.transportBarBg)
        }
    }
    return PreviewContainer()
}
