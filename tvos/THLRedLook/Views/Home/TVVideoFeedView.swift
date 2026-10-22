import SwiftUI
import AVFoundation

public struct TVVideoFeedActions {
    let progressText: String
    let canGoPrevious: Bool
    let canGoNext: Bool
    let isLoading: Bool
    let isFavorite: Bool
    let errorMessage: String?
    let onPrevious: () -> Void
    let onNext: () async -> Bool
    let onFavorite: () -> Void
    let onDetail: (Drama) -> Void
    let onRefresh: () -> Void
}

public struct TVVideoFeedView: View {
    @ObservedObject var viewModel: VideoFeedViewModel
    var isSidebarVisible: Bool = false
    @State private var playbackWakeTrigger: Int = 0
    let focusTrigger: Int
    let onRequestFocusTopNav: () -> Void

    public var body: some View {
        Group {
            if let _ = viewModel.current {
                TVVideoFeedPlaybackView(
                    viewModel: viewModel,
                    isSidebarVisible: isSidebarVisible,
                    focusWakeTrigger: playbackWakeTrigger,
                    onDismiss: {
                        onRequestFocusTopNav()
                    }
                )
            } else if viewModel.isLoading {
                VStack(spacing: 24) {
                    ProgressView("正在准备推荐短视频…")
                        .font(.system(size: 26, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                    TVButton(title: "重试", icon: "arrow.clockwise", isProminent: true) {
                        Task { await viewModel.retry() }
                    }
                    .accessibilityIdentifier("feed.retry")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .focusSection()
        .onAppear {
            if !isSidebarVisible {
                playbackWakeTrigger += 1
            }
            Task {
                await viewModel.start()
            }
        }
        .onChange(of: isSidebarVisible) { _, visible in
            if !visible {
                playbackWakeTrigger += 1
            }
        }
        .onChange(of: focusTrigger) { _, _ in
            playbackWakeTrigger += 1
        }
        .onChange(of: viewModel.current?.id) { _, newId in
            if newId != nil && !isSidebarVisible {
                playbackWakeTrigger += 1
            }
        }
        .onExitCommand {
            onRequestFocusTopNav()
        }
    }
}

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
