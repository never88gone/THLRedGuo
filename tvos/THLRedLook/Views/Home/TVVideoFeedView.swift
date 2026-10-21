import SwiftUI

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
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var isWatching = false
    @State private var pendingContentFocus = false
    @FocusState private var focusedAction: String?
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
                Text(item.drama.description)
                    .font(.system(size: 25))
                    .foregroundStyle(TVTheme.textSecondary)
                    .lineLimit(3)
                Text("全屏观看 · 上下键切换短剧 · 点按显示选集和弹幕控制")
                    .font(.system(size: 24))
                    .foregroundStyle(TVTheme.textSecondary)
                HStack(spacing: 24) {
                    action("开始观看", icon: "play.fill", id: "watch") { isWatching = true }
                    action("换一批", icon: "arrow.clockwise", id: "refresh") { pendingContentFocus = true; Task { await viewModel.refresh() } }
                        .disabled(viewModel.isLoading)
                }
            } else if viewModel.isLoading {
                ProgressView("正在加载首页推荐…")
            }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.yellow).font(.system(size: 25))
                action("重试", icon: "arrow.clockwise", id: "retry") { pendingContentFocus = true; Task { await viewModel.retry() } }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 64)
        .padding(.top, 40)
        .task { await viewModel.start() }
        .onChange(of: focusTrigger) { _, _ in pendingContentFocus = true; focusContent() }
        .onChange(of: viewModel.isLoading) { _, loading in
            if !loading && pendingContentFocus { focusContent() }
        }
        .onExitCommand { returnToNavigation() }
        .fullScreenCover(isPresented: $isWatching, onDismiss: { focusedAction = "watch" }) {
            TVVideoFeedPlaybackView(viewModel: viewModel) { isWatching = false }
        }
    }

    private func returnToNavigation() {
        pendingContentFocus = false
        focusedAction = nil
        onRequestFocusTopNav()
    }

    private func focusContent() {
        if viewModel.current != nil { focusedAction = "watch"; pendingContentFocus = false }
        else if viewModel.errorMessage != nil { focusedAction = "retry"; pendingContentFocus = false }
    }

    private func action(_ title: String, icon: String, id: String, perform: @escaping () -> Void) -> some View {
        TVButton(title: title, icon: icon, isProminent: id == "watch", isExternalFocused: focusedAction == id, action: perform)
            .focused($focusedAction, equals: id)
            .accessibilityIdentifier("feed.\(id)")
            .onMoveCommand { direction in
                if direction == .up { returnToNavigation() }
            }
    }
}

private struct TVVideoFeedPlaybackView: View {
    @ObservedObject var viewModel: VideoFeedViewModel
    @ObservedObject private var store = LocalStore.shared
    @State private var detailDrama: Drama?
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let item = viewModel.current {
                    let history = store.history.first { $0.drama.id == item.id }
                    TVPlayerView(
                        drama: item.drama,
                        episodes: [],
                        initialEpisodeIndex: history?.episode ?? item.episode,
                        initialPosition: history?.position ?? item.position,
                        initialShowControls: true,
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
                        )
                    )
                    .id(item.id)
                } else {
                    VStack(spacing: 24) {
                        if viewModel.isLoading { ProgressView("正在加载推荐…") }
                        if let error = viewModel.errorMessage { Text(error) }
                        Button("重试") { Task { await viewModel.retry() } }.accessibilityIdentifier("feed.retry")
                        Button("返回", action: onDismiss)
                    }
                    .onExitCommand(perform: onDismiss)
                }
            }
            .navigationDestination(item: $detailDrama) { drama in DramaDetailView(drama: drama) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
