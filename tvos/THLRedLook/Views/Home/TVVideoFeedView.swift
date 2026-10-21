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
    @State private var isWatching = false
    @State private var isVisible = false
    @State private var didRequestAutomaticPlayback = false
    @State private var pendingPlayback = false
    @FocusState private var isRetryFocused: Bool
    let focusTrigger: Int
    let onRequestFocusTopNav: () -> Void

    public var body: some View {
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
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; pendingPlayback = false }
        .task {
            guard !didRequestAutomaticPlayback else { return }
            didRequestAutomaticPlayback = true
            guard !isWatching, !Task.isCancelled else { return }
            pendingPlayback = true
            await viewModel.start()
            guard !Task.isCancelled else { return }
            presentPlaybackIfReady()
        }
        .onChange(of: focusTrigger) { _, _ in requestPlayback() }
        .onChange(of: viewModel.current?.id) { _, _ in presentPlaybackIfReady() }
        .onChange(of: viewModel.errorMessage) { _, error in
            if isVisible && pendingPlayback && viewModel.current == nil && error != nil { isRetryFocused = true }
        }
        .onExitCommand { returnToNavigation() }
        .fullScreenCover(isPresented: $isWatching, onDismiss: returnToNavigation) {
            TVVideoFeedPlaybackView(viewModel: viewModel) { isWatching = false }
        }
    }

    private func returnToNavigation() {
        pendingPlayback = false
        isRetryFocused = false
        onRequestFocusTopNav()
    }

    private func requestPlayback() {
        guard !isWatching else { return }
        pendingPlayback = true
        if viewModel.current != nil { presentPlaybackIfReady() }
        else if viewModel.errorMessage != nil { isRetryFocused = true }
    }

    private func presentPlaybackIfReady() {
        guard isVisible, pendingPlayback, viewModel.current != nil else { return }
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
    let onDismiss: () -> Void

    public var body: some View {
        NavigationStack {
            Group {
                if let item = viewModel.current {
                    let history = store.history.first { $0.drama.id == item.id }
                    TVPlayerView(
                        drama: item.drama,
                        episodes: viewModel.feedEpisodes[item.id] ?? [],
                        initialEpisodeIndex: history?.episode ?? item.episode,
                        initialPosition: history?.position ?? item.position,
                        initialShowControls: false,
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
                            onDetail: { detailDrama = $0 },
                            onRefresh: { Task { await viewModel.refresh() } }
                        ),
                        preloadedPlan: viewModel.feedPlans[item.id]
                    )
                    .id(item.id)
                } else if viewModel.isLoading {
                    ProgressView("正在准备下一条推荐…")
                } else if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .navigationDestination(item: $detailDrama) { drama in
                DramaDetailView(drama: drama)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                viewModel.preloadAround(index: viewModel.currentIndex)
            }
        }
    }
}
