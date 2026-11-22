import SwiftUI

/// tvOS 系统原生风格 Transport Bar（对齐 Apple TV 原生 AVPlayer 与 ATV-Bilibili-demo 质感）
public struct TVPlayerTransportBar: View {
    @ObservedObject public var viewModel: PlayerViewModel
    @Binding public var selectedTab: TVPlayerBottomTab
    @Binding public var isPanelExpanded: Bool
    public var onDismiss: () -> Void

    @FocusState private var focusedCapsule: TVPlayerBottomTab?

    public init(
        viewModel: PlayerViewModel,
        selectedTab: Binding<TVPlayerBottomTab>,
        isPanelExpanded: Binding<Bool>,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self._selectedTab = selectedTab
        self._isPanelExpanded = isPanelExpanded
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - 1. 顶部视频元数据（剧名、集数、清晰度）
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(viewModel.drama.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(TVColors.white)
                    .lineLimit(1)

                Text("第 \(viewModel.currentEpisodeIndex) 集 · \(PlaybackPlan.qualityLabel(viewModel.selectedQuality))")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(TVColors.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 54)

            // MARK: - 2. 系统原生细长高光进度条
            HStack(spacing: 16) {
                Text(formatTime(viewModel.currentTime))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(TVColors.white)
                    .frame(width: 76, alignment: .trailing)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // 底槽轨道
                        Capsule()
                            .fill(TVColors.transportBarScrubberBg)
                            .frame(height: 6)

                        // 缓冲进度
                        Capsule()
                            .fill(TVColors.transportBarScrubberBuffer)
                            .frame(
                                width: viewModel.duration > 0
                                    ? geo.size.width * CGFloat(min(1.0, max(0, (viewModel.currentTime + 10) / viewModel.duration)))
                                    : 0,
                                height: 6
                            )

                        // 已播放高亮条
                        Capsule()
                            .fill(TVColors.activeRed)
                            .frame(
                                width: viewModel.duration > 0
                                    ? geo.size.width * CGFloat(min(1.0, max(0, viewModel.currentTime / viewModel.duration)))
                                    : 0,
                                height: 6
                            )

                        // 游标小白点
                        if viewModel.duration > 0 {
                            Circle()
                                .fill(TVColors.white)
                                .frame(width: 12, height: 12)
                                .shadow(color: TVColors.black.opacity(0.6), radius: 3)
                                .offset(x: max(0, min(geo.size.width - 12, geo.size.width * CGFloat(viewModel.currentTime / viewModel.duration) - 6)))
                        }
                    }
                }
                .frame(height: 6)

                // 剩余倒计时时间（如 -02:15）
                Text(formatRemainingTime(current: viewModel.currentTime, total: viewModel.duration))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(TVColors.textSecondary)
                    .frame(width: 86, alignment: .leading)
            }
            .padding(.horizontal, 54)

            // MARK: - 3. 系统原生菜单胶囊按钮栏（对应 transportBarCustomMenuItems 与面板入口）
            HStack(spacing: 16) {
                ForEach(TVPlayerBottomTab.allCases) { tab in
                    tabCapsuleButton(tab: tab)
                }

                Spacer()

                // 播放/暂停状态指示快捷键
                Button(action: {
                    viewModel.togglePlayPause()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.wantsPlayback ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(viewModel.wantsPlayback ? "暂停" : "播放")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(TVColors.surfaceCard)
                    .cornerRadius(20)
                }
                .buttonStyle(TvCardButtonStyle())
            }
            .padding(.horizontal, 54)
        }
        .padding(.vertical, 16)
    }

    // MARK: - 胶囊按钮组件
    @ViewBuilder
    private func tabCapsuleButton(tab: TVPlayerBottomTab) -> some View {
        Button(action: {
            if selectedTab == tab && isPanelExpanded {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isPanelExpanded = false
                }
            } else {
                selectedTab = tab
                withAnimation(.easeInOut(duration: 0.25)) {
                    isPanelExpanded = true
                }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(selectedTab == tab && isPanelExpanded ? TVColors.red : TVColors.white)

                Text(tab.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(TVColors.white)

                if selectedTab == tab && isPanelExpanded {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(TVColors.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(selectedTab == tab && isPanelExpanded ? TVColors.surfaceFocused : TVColors.surfaceCard)
            )
            .overlay(
                Capsule()
                    .stroke(
                        focusedCapsule == tab ? TVColors.liquidGlassActiveBorder : (selectedTab == tab && isPanelExpanded ? TVColors.red.opacity(0.8) : TVColors.liquidGlassBorder),
                        lineWidth: focusedCapsule == tab ? 2.5 : 1.0
                    )
            )
        }
        .buttonStyle(TvCardButtonStyle())
        .focused($focusedCapsule, equals: tab)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let s = Int(seconds.rounded(.down))
        let m = s / 60
        let sec = s % 60
        return String(format: "%02d:%02d", m, sec)
    }

    private func formatRemainingTime(current: Double, total: Double) -> String {
        guard current.isFinite && total.isFinite && total >= current else { return "-00:00" }
        let remaining = Int((total - current).rounded(.down))
        let m = remaining / 60
        let sec = remaining % 60
        return String(format: "-%02d:%02d", m, sec)
    }
}

// MARK: - 预览
#Preview("TVPlayerTransportBar Preview") {
    struct PreviewContainer: View {
        @State var tab: TVPlayerBottomTab = .episodes
        @State var expanded: Bool = false
        var body: some View {
            let drama = Drama(id: "1", title: "都市逆袭之王者归来", cover: "", episodes: 80)
            let eps = (1...20).map { Episode(id: "\($0)", title: "第 \($0) 集", number: $0) }
            let vm = PlayerViewModel(drama: drama, allEpisodes: eps, initialEpisodeIndex: 1)
            TVPlayerTransportBar(
                viewModel: vm,
                selectedTab: $tab,
                isPanelExpanded: $expanded,
                onDismiss: {}
            )
            .background(TVColors.black)
        }
    }
    return PreviewContainer()
}
