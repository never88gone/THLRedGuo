import SwiftUI

public struct TVPlayerTopInfoBar: View {
    @ObservedObject private var likeStore = UserLikeStore.shared
    @ObservedObject private var accountModel = HongguoAccountModel.shared
    public let title: String
    public let episodeText: String
    public let episodeNumber: Int
    public let onSocial: (() -> Void)?
    public let feedActions: TVVideoFeedActions?
    public let drama: Drama
    @FocusState.Binding public var focusedControl: PlayerOverlayFocusTarget?

    public init(
        title: String,
        episodeText: String,
        episodeNumber: Int = 1,
        onSocial: (() -> Void)?,
        feedActions: TVVideoFeedActions?,
        drama: Drama,
        focusedControl: FocusState<PlayerOverlayFocusTarget?>.Binding
    ) {
        self.title = title
        self.episodeText = episodeText
        self.episodeNumber = episodeNumber
        self.onSocial = onSocial
        self.feedActions = feedActions
        self.drama = drama
        self._focusedControl = focusedControl
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .accessibilityIdentifier("player.title")
                        .font(.title3)
                        .bold()
                        .foregroundColor(TVTheme.textPrimary)
                    Text(episodeText)
                        .accessibilityIdentifier("player.episode")
                        .font(.subheadline)
                        .foregroundColor(TVTheme.textSecondary)
                }

                Spacer()
                if accountModel.loggedIn {
                    let isLiked = likeStore.isLiked(dramaId: drama.id, episode: episodeNumber)
                    barButton(
                        title: isLiked ? "已点赞" : "点赞",
                        icon: isLiked ? "heart.fill" : "heart",
                        target: .like
                    ) {
                        Task {
                            await likeStore.toggleLike(drama: drama, episode: episodeNumber)
                        }
                    }
                    .onMoveCommand { direction in
                        if direction == .down { focusedControl = .playPause }
                    }
                }
                if let onSocial {
                    barButton(title: "点赞与关注", icon: "heart", target: .social, action: onSocial)
                        .onMoveCommand { direction in
                            if direction == .down { focusedControl = .playPause }
                        }
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, 42)

            if let feedActions {
                Text(feedActions.progressText)
                    .font(.system(size: 22))
                    .accessibilityIdentifier("feed.progress")
                HStack(spacing: 18) {
                    barButton(title: "上一部", icon: "arrow.up", target: .previousDrama, action: feedActions.onPrevious)
                        .disabled(!feedActions.canGoPrevious)
                        .opacity(feedActions.canGoPrevious ? 1 : 0.45)
                    barButton(title: "下一部", icon: "arrow.down", target: .nextDrama) {
                        Task { _ = await feedActions.onNext() }
                    }
                    .disabled(!feedActions.canGoNext)
                    .opacity(feedActions.canGoNext ? 1 : 0.45)
                    barButton(title: feedActions.isFavorite ? "已收藏" : "收藏", icon: "bookmark", target: .favorite, action: feedActions.onFavorite)
                    if accountModel.loggedIn {
                        let isFeedLiked = likeStore.isLiked(dramaId: drama.id, episode: episodeNumber)
                        barButton(
                            title: isFeedLiked ? "已点赞" : "点赞",
                            icon: isFeedLiked ? "heart.fill" : "heart",
                            target: .like
                        ) {
                            Task {
                                await likeStore.toggleLike(drama: drama, episode: episodeNumber)
                            }
                        }
                    }
                    barButton(title: "剧集详情", icon: "info.circle", target: .detail) {
                        feedActions.onDetail(drama)
                    }
                    barButton(title: "换一批", icon: "arrow.clockwise", target: .refreshFeed, action: feedActions.onRefresh)
                        .disabled(feedActions.isLoading)
                    Spacer()
                }
                .padding(.horizontal, 56)
                .padding(.top, 18)
                .onMoveCommand { direction in
                    if direction == .down { focusedControl = .playPause }
                }
                Text(feedActions.errorMessage ?? "画面模式下按上下键切换短剧，点按显示控制")
                    .font(.system(size: 22))
                    .foregroundStyle(feedActions.errorMessage == nil ? .white.opacity(0.8) : .yellow)
                    .padding(.top, 12)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, 24)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.88), Color.black.opacity(0.45), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: [.top, .horizontal])
        )
    }

    @ViewBuilder
    private func barButton(
        title: String,
        icon: String? = nil,
        target: PlayerOverlayFocusTarget,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = (focusedControl == target)
        Button(action: action) {
            HStack(spacing: 12) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 18, weight: .bold))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .padding(.horizontal, title.isEmpty ? 20 : 28)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? TVTheme.surfaceFocused : TVTheme.surfaceCard)
            )
            .foregroundColor(TVTheme.textPrimary)
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 14)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($focusedControl, equals: target)
        .accessibilityIdentifier("player.\(target)")
        .focusEffectDisabled()
    }
}
