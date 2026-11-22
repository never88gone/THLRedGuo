import SwiftUI

/// tvOS 原生系统风格播放控制器浮层（参考 ATV-Bilibili-demo 与系统 AVPlayer 质感）
public struct TVPlayerControlsOverlay: View {
    @ObservedObject public var viewModel: PlayerViewModel
    public var forceFocusPlayButton: Bool = false
    public var feedActions: TVVideoFeedActions?
    public let onDismiss: () -> Void

    @State private var selectedTab: TVPlayerBottomTab = .episodes
    @State private var isPanelExpanded: Bool = false

    public init(
        viewModel: PlayerViewModel,
        forceFocusPlayButton: Bool = false,
        initialTab: TVPlayerBottomTab = .episodes,
        feedActions: TVVideoFeedActions? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.forceFocusPlayButton = forceFocusPlayButton
        self.feedActions = feedActions
        self.onDismiss = onDismiss

        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "-testPlayerTab"), idx + 1 < args.count {
            let tabArg = args[idx + 1]
            if let matched = TVPlayerBottomTab.allCases.first(where: { "\($0)" == tabArg || $0.rawValue == tabArg || $0.id == tabArg }) {
                _selectedTab = State(initialValue: matched)
                _isPanelExpanded = State(initialValue: true)
            } else {
                _selectedTab = State(initialValue: initialTab)
                _isPanelExpanded = State(initialValue: false)
            }
        } else {
            _selectedTab = State(initialValue: initialTab)
            _isPanelExpanded = State(initialValue: false)
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // 背景暗化微光渐变，确保文字与视频分离，通透不遮挡
            LinearGradient(
                colors: [
                    TVColors.clear,
                    TVColors.black.opacity(0.3),
                    TVColors.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                // MARK: - 可展开的系统级毛玻璃卡片抽屉 (Info Panel)
                if isPanelExpanded {
                    panelDrawer
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // MARK: - 系统原生 Transport Bar 主控条
                TVPlayerTransportBar(
                    viewModel: viewModel,
                    selectedTab: $selectedTab,
                    isPanelExpanded: $isPanelExpanded,
                    onDismiss: onDismiss
                )
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            let args = CommandLine.arguments
            if let idx = args.firstIndex(of: "-testPlayerTab"), idx + 1 < args.count {
                let tabArg = args[idx + 1]
                if let matched = TVPlayerBottomTab.allCases.first(where: { "\($0)" == tabArg || $0.rawValue == tabArg || $0.id == tabArg }) {
                    selectedTab = matched
                    isPanelExpanded = true
                }
            }
        }
    }

    // MARK: - 系统毛玻璃抽屉面板
    @ViewBuilder
    private var panelDrawer: some View {
        VStack(spacing: 0) {
            // 抽屉内部横向卡片流
            Group {
                switch selectedTab {
                case .episodes:
                    TVPlayerEpisodesPanel(viewModel: viewModel)
                case .related:
                    TVPlayerRelatedPanel(viewModel: viewModel)
                case .interaction:
                    TVPlayerInteractionPanel(viewModel: viewModel)
                case .settings:
                    TVPlayerSettingsPanel(viewModel: viewModel)
                case .danmaku:
                    TVPlayerDanmakuPanel(viewModel: viewModel)
                }
            }
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TVColors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(TVColors.liquidGlassBorder, lineWidth: 1)
                )
                .shadow(color: TVColors.black.opacity(0.7), radius: 24, y: 10)
        )
        .padding(.horizontal, 54)
        .padding(.bottom, 12)
    }
}

// MARK: - 预览
#Preview("TVPlayerControlsOverlay Preview") {
    struct PreviewContainer: View {
        var body: some View {
            let drama = Drama(id: "preview_1", title: "逆天龙皇：王者归来", cover: "", episodes: 80)
            let eps = (1...20).map { Episode(id: "\($0)", title: "第 1 集", number: 1) }
            let vm = PlayerViewModel(drama: drama, allEpisodes: eps, initialEpisodeIndex: 1)
            TVPlayerControlsOverlay(viewModel: vm) {
                print("Dismiss overlay")
            }
            .background(TVColors.black)
        }
    }
    return PreviewContainer()
}
