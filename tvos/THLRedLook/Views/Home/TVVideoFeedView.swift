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
    @State private var isWatching = false
    @State private var isVisible = false
    @State private var pendingPlayback = false
    @State private var playbackSessionId = UUID()
    @FocusState private var isRetryFocused: Bool
    let focusTrigger: Int
    let onRequestFocusTopNav: () -> Void

    public var body: some View {
        Group {
            if isWatching {
                TVVideoFeedPlaybackView(viewModel: viewModel) {
                    returnToNavigation()
                }
                .id(playbackSessionId)
            } else {
                VStack(alignment: .leading, spacing: 26) {
                    Label("首页视频推荐", systemImage: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 34, weight: .bold))
                    if let item = viewModel.current {
                        Text(item.drama.title)
                            .font(.system(size: 46, weight: .bold))
                            .lineLimit(2)
                            .accessibilityIdentifier("feed.title")
                        Text("播放进度已保留，按下或点按“推荐”继续播放")
                            .font(.system(size: 25))
                            .foregroundStyle(TVTheme.textSecondary)
                    } else if viewModel.isLoading {
                        ProgressView("正在加载首页推荐…")
                    }
                    if let error = viewModel.errorMessage {
                        Text(error).foregroundStyle(.yellow).font(.system(size: 25))
                        TVButton(title: "重试", icon: "arrow.clockwise", isProminent: true, isExternalFocused: isRetryFocused) {
                            pendingPlayback = true
                            Task {
                                await viewModel.retry()
                                presentPlaybackIfReady()
                            }
                        }
                        .focused($isRetryFocused)
                        .accessibilityIdentifier("feed.retry")
                        .disabled(viewModel.isLoading)
                        .onMoveCommand { direction in
                            if direction == .up { returnToNavigation() }
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 64)
                .padding(.top, 40)
            }
        }
        .onAppear {
            isVisible = true
            if focusTrigger > 0 {
                requestPlayback()
            } else {
                Task { await viewModel.start() }
            }
        }
        .onDisappear {
            isVisible = false
            pendingPlayback = false
            isWatching = false
        }
        .onChange(of: isSidebarVisible) { _, visible in
            if visible {
                pendingPlayback = false
                isRetryFocused = false
                isWatching = false
            } else {
                requestPlayback()
            }
        }
        .onChange(of: focusTrigger) { _, _ in
            requestPlayback()
        }
        .onChange(of: viewModel.errorMessage) { _, error in
            if isVisible && pendingPlayback && viewModel.current == nil && error != nil {
                isRetryFocused = true
            }
        }
        .onExitCommand { returnToNavigation() }
    }

    private func returnToNavigation() {
        guard isWatching || pendingPlayback else { return }
        pendingPlayback = false
        isRetryFocused = false
        isWatching = false
        onRequestFocusTopNav()
    }

    private func requestPlayback() {
        guard !isSidebarVisible, !isWatching else { return }
        pendingPlayback = true
        if viewModel.current != nil {
            presentPlaybackIfReady()
        } else if viewModel.errorMessage != nil {
            isRetryFocused = true
        } else {
            Task {
                await viewModel.start()
                if !isSidebarVisible {
                    presentPlaybackIfReady()
                }
            }
        }
    }

    private func presentPlaybackIfReady() {
        guard !isSidebarVisible, isVisible, pendingPlayback, viewModel.current != nil else { return }
        playbackSessionId = UUID()
        pendingPlayback = false
        isRetryFocused = false
        isWatching = true
    }
}

/// 沉浸式短视频推荐全屏流式播放器（参考 thldytv 的 AVPlayerContainerView 与预加载机制）
/// 复用统一的高性能播放器视口，彻底消除切换时的重复销毁重建与转圈等待，实现毫秒级快速切片
public struct TVVideoFeedPlaybackView: View {
    @ObservedObject var viewModel: VideoFeedViewModel
    @ObservedObject private var store = LocalStore.shared
    @State private var detailDrama: Drama?
    @State private var restoreDetailControlFocus: Bool = false
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
