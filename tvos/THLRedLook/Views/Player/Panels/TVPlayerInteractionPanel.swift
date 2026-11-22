import SwiftUI

/// 播放器互动卡片面板（对应 ATV-Bilibili-demo 互动卡片流）
public struct TVPlayerInteractionPanel: View {
    @ObservedObject public var viewModel: PlayerViewModel
    @FocusState private var focusedInteraction: String?

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                // 1. 点赞卡片
                likeCard

                // 2. 追剧/收藏卡片
                followCard

                // 3. 评论抽屉卡片
                commentsCard

                // 4. 短剧简介与详情
                infoCard
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 12)
        }
        .frame(height: 160)
    }

    private var likeCard: some View {
        let isLiked = UserLikeStore.shared.isLiked(dramaId: viewModel.drama.id, episode: viewModel.currentEpisodeIndex)
        return actionCard(
            id: "like",
            icon: isLiked ? "heart.fill" : "heart",
            iconColor: isLiked ? TVColors.activeRed : TVColors.white,
            title: isLiked ? "已点赞本集" : "点赞本集",
            subtitle: "第 \(viewModel.currentEpisodeIndex) 集 · 喜欢请点赞"
        ) {
            Task {
                await UserLikeStore.shared.toggleLike(drama: viewModel.drama, episode: viewModel.currentEpisodeIndex)
            }
        }
    }

    private var followCard: some View {
        let isFollowing = LocalStore.shared.followState(for: viewModel.drama.id) != .none
        return actionCard(
            id: "favorite",
            icon: isFollowing ? "star.fill" : "star",
            iconColor: isFollowing ? TVColors.vipAccent : TVColors.white,
            title: isFollowing ? "已在追剧书架" : "追剧加入书架",
            subtitle: "全 \(viewModel.drama.episodes) 集 · 更新即时提醒"
        ) {
            let nextState: FollowState = isFollowing ? .none : .watching
            LocalStore.shared.setFollowState(drama: viewModel.drama, state: nextState)
            viewModel.showToast(isFollowing ? "已取消追剧" : "已加入追剧书架")
        }
    }

    private var commentsCard: some View {
        actionCard(
            id: "comments",
            icon: "bubble.left.and.bubble.right.fill",
            iconColor: TVColors.white,
            title: "剧友热评",
            subtitle: "查看与发表本剧精选评论"
        ) {
            viewModel.isCommentDrawerVisible = true
        }
    }

    private var infoCard: some View {
        actionCard(
            id: "info",
            icon: "info.circle.fill",
            iconColor: TVColors.white,
            title: "短剧详情",
            subtitle: viewModel.drama.description.isEmpty ? "查看短剧完整大纲与演员" : viewModel.drama.description
        ) {
            viewModel.showToast(viewModel.drama.description.isEmpty ? "暂无详细简介" : viewModel.drama.description)
        }
    }

    private func actionCard(
        id: String,
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(TVColors.white)

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(TVColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 240, height: 120)
            .background(TVColors.panelCardBg)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        focusedInteraction == id
                            ? TVColors.liquidGlassActiveBorder
                            : TVColors.liquidGlassBorder,
                        lineWidth: focusedInteraction == id ? 3 : 1
                    )
            )
            .scaleEffect(focusedInteraction == id ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focusedInteraction)
        }
        .buttonStyle(.card)
        .focused($focusedInteraction, equals: id)
    }
}

// MARK: - 预览
#Preview("TVPlayerInteractionPanel") {
    struct PreviewContainer: View {
        var body: some View {
            let drama = Drama(id: "preview_1", title: "逆天龙皇", description: "一代战神龙王归隐都市，谁料受尽白眼...", cover: "", episodes: 80)
            let vm = PlayerViewModel(drama: drama, allEpisodes: [])
            TVPlayerInteractionPanel(viewModel: vm)
                .padding(.vertical, 40)
                .background(TVColors.transportBarBg)
        }
    }
    return PreviewContainer()
}
