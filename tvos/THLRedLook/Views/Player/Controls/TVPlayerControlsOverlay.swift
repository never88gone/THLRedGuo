import SwiftUI

/// 重构后的 tvOS 原生风格播放控制器浮层（参考 ATV-Bilibili-demo 与系统 AVPlayer 质感）
public struct TVPlayerControlsOverlay: View {
    @ObservedObject public var viewModel: PlayerViewModel
    public var forceFocusPlayButton: Bool = false
    public var feedActions: TVVideoFeedActions?
    public let onDismiss: () -> Void

    @State private var selectedTab: TVPlayerBottomTab = .episodes
    @FocusState private var focusedControl: PlayerOverlayFocusTarget?

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
            if let matched = TVPlayerBottomTab.allCases.first(where: { $0.id == tabArg || $0.rawValue == tabArg }) {
                _selectedTab = State(initialValue: matched)
            } else {
                _selectedTab = State(initialValue: initialTab)
            }
        } else {
            _selectedTab = State(initialValue: initialTab)
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // 背景暗化微光渐变，确保文字与视频分离，增加沉浸高级感
            LinearGradient(
                colors: [
                    TVColors.black.opacity(0.8),
                    TVColors.clear,
                    TVColors.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // MARK: - 顶部短剧标题与信息栏
                TVPlayerTopInfoBar(
                    title: viewModel.drama.title,
                    episodeText: "第 \(viewModel.currentEpisodeIndex) 集 · \(PlaybackPlan.qualityLabel(viewModel.selectedQuality))",
                    episodeNumber: viewModel.currentEpisodeIndex,
                    feedActions: feedActions,
                    drama: viewModel.drama,
                    focusedControl: $focusedControl
                )

                // 中间透明区域：点击收起控制栏
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.hideControls()
                    }
                }) {
                    TVColors.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TvTransparentButtonStyle())
                .accessibilityLabel("收起控制栏")
                .accessibilityIdentifier("player.dismissControls")

                // MARK: - 底部核心控制托盘 (类似系统 AVPlayer + ATV-Bilibili-demo 多功能面板)
                VStack(spacing: 16) {
                    // 1. 系统原生 Transport Bar 主控条 (进度条 + 播放按键行)
                    TVPlayerTransportBar(viewModel: viewModel)

                    // 2. 底部功能分段切换条 (选集、相关短剧、互动、设置、弹幕)
                    TVPlayerSegmentBar(selectedTab: $selectedTab)

                    // 3. 动态展示对应功能面板卡片流
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
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
                .background(
                    RoundedRectangle(cornerRadius: 32)
                        .fill(TVColors.transportBarBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 32)
                                .stroke(TVColors.borderSubtle, lineWidth: 1)
                        )
                        .shadow(color: TVColors.black.opacity(0.6), radius: 24, y: -6)
                )
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            if forceFocusPlayButton {
                focusedControl = .playPause
            }
            let args = CommandLine.arguments
            if let idx = args.firstIndex(of: "-testPlayerTab"), idx + 1 < args.count {
                let tabArg = args[idx + 1]
                if let matched = TVPlayerBottomTab.allCases.first(where: { "\($0)" == tabArg || $0.rawValue == tabArg || $0.id == tabArg }) {
                    selectedTab = matched
                }
            }
            NSLog("🎬 [Overlay] onAppear selectedTab: %@", selectedTab.rawValue)
        }
    }
}

// MARK: - 预览
#Preview("TVPlayerControlsOverlay") {
    struct PreviewContainer: View {
        var body: some View {
            let drama = Drama(id: "preview_1", title: "逆天龙皇：王者归来", cover: "", episodes: 80)
            let eps = (1...20).map { Episode(id: "\($0)", title: "第\($0)集", number: $0) }
            let vm = PlayerViewModel(drama: drama, allEpisodes: eps, initialEpisodeIndex: 1)
            TVPlayerControlsOverlay(viewModel: vm) {
                print("Dismiss overlay")
            }
        }
    }
    return PreviewContainer()
}
