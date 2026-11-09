import SwiftUI

/// 沉浸式短视频推荐全屏流式播放器（参考 thldytv 的 AVPlayerContainerView 与预加载机制）
/// 复用统一的高性能播放器视口，彻底消除切换时的重复销毁重建与转圈等待，实现毫秒级快速切片
public struct TVVideoFeedPlaybackView: View {
    @ObservedObject var viewModel: VideoFeedViewModel
    @ObservedObject private var store = LocalStore.shared
    @State private var detailDrama: Drama?
    @State private var restoreDetailControlFocus: Bool = false
    var isSidebarVisible: Bool = false
    var focusWakeTrigger: Int = 0
    let onDismiss: () -> Void

    public init(
        viewModel: VideoFeedViewModel,
        isSidebarVisible: Bool = false,
        focusWakeTrigger: Int = 0,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.isSidebarVisible = isSidebarVisible
        self.focusWakeTrigger = focusWakeTrigger
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Group {
            if let drama = detailDrama {
                DramaDetailView(drama: drama, onDismiss: {
                    detailDrama = nil
                })
            } else if let item = viewModel.current {
                let history = store.history.first { $0.drama.id == item.id }
                let effectiveEpisode = history?.episode ?? item.episode
                let effectivePosition = history?.position ?? item.position
                let effectivePlan = (effectiveEpisode == item.episode) ? viewModel.feedPlans[item.id] : nil
                TVPlayerView(
                    drama: item.drama,
                    episodes: viewModel.feedEpisodes[item.id] ?? [],
                    initialEpisodeIndex: effectiveEpisode,
                    initialPosition: effectivePosition,
                    initialShowControls: restoreDetailControlFocus,
                    initialRestoreFocusTarget: restoreDetailControlFocus ? .detail : nil,
                    onDismiss: onDismiss,
                    feedActions: TVVideoFeedActions(
                        progressText: "推荐 · 第 \(viewModel.currentIndex + 1) 部 · 已加载 \(viewModel.items.count) 部",
                        canGoPrevious: viewModel.canGoPrevious,
                        canGoNext: viewModel.canGoNext,
                        isLoading: viewModel.isLoading,
                        isFavorite: store.followState(for: item.id) != .none,
                        errorMessage: viewModel.errorMessage,
                        onPrevious: { viewModel.previous() },
                        onNext: {
                            let previousId = viewModel.current?.id
                            await viewModel.next()
                            return viewModel.current?.id != previousId
                        },
                        onFavorite: {
                            store.setFollowState(drama: item.drama, state: store.followState(for: item.id) == .none ? .watching : .none)
                        },
                        onDetail: { drama in
                            restoreDetailControlFocus = true
                            detailDrama = drama
                        },
                        onRefresh: { Task { await viewModel.refresh() } }
                    ),
                    focusWakeTrigger: focusWakeTrigger,
                    isInteractive: !isSidebarVisible,
                    preloadedPlan: effectivePlan
                )
            } else if viewModel.isLoading {
                ProgressView("正在准备下一条推荐…")
            } else if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .onChange(of: detailDrama) { oldDrama, newDrama in
            if oldDrama != nil && newDrama == nil {
                DispatchQueue.main.async {
                    restoreDetailControlFocus = false
                }
            }
        }
        .onAppear {
            viewModel.preloadAround(index: viewModel.currentIndex)
        }
    }
}
