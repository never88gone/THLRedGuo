import SwiftUI

// MARK: - 左侧：二级回复列表面板
struct TVCommentReplyPanel: View {
    let mainComment: TVCommentItem
    let replies: [TVCommentReplyItem]
    let totalReplies: Int
    let isLoadingReplies: Bool
    let replyError: String?
    let hasMoreReplies: Bool
    @FocusState.Binding var focusedTarget: CommentFocusTarget?
    let onClose: () -> Void
    let onRetry: () -> Void
    let onLoadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                        Text("收起回复")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(TvButtonStyle(variant: .plain, cornerRadius: 18, isFocused: focusedTarget == .closeRepliesButton))
                .focused($focusedTarget, equals: .closeRepliesButton)
                .onMoveCommand { dir in
                    if dir == .right {
                        focusedTarget = .comment(mainComment.id)
                    }
                }

                Spacer()

                Text("回复 (\(totalReplies > 0 ? totalReplies : replies.count))")
                    .font(.title3)
                    .bold()
                    .foregroundColor(TVColors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 16)

            Divider()
                .background(TVColors.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TVCommentAvatarView(url: mainComment.userAvatar, name: mainComment.userName, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mainComment.userName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(TVColors.textPrimary)
                        Text(TVCommentAvatarView.formatTimestamp(mainComment.createTime))
                            .font(.caption2)
                            .foregroundColor(TVColors.textSecondary)
                    }
                    Spacer()
                    if mainComment.diggCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundColor(TVColors.activeRed)
                            Text(TVCommentAvatarView.formatNumber(mainComment.diggCount))
                                .font(.caption2)
                                .foregroundColor(TVColors.textSecondary)
                        }
                    }
                }

                Text(mainComment.text)
                    .font(.system(size: 15))
                    .foregroundColor(TVColors.textPrimary)
                    .lineLimit(3)
            }
            .padding(16)
            .background(TVColors.white.opacity(0.06))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()
                .background(TVColors.borderSubtle)

            if isLoadingReplies {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView().scaleEffect(1.3)
                    Spacer()
                }
                Spacer()
            } else if let error = replyError {
                Spacer()
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundColor(TVColors.textSecondary)
                        .font(.body)
                    Button("重试", action: onRetry)
                        .buttonStyle(TvButtonStyle(variant: .primary, cornerRadius: 10))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if replies.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("暂无回复")
                        .foregroundColor(TVColors.textSecondary)
                        .font(.headline)
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(replies) { reply in
                            let isFocused = (focusedTarget == .reply(reply.id))
                            Button(action: {}) {
                                TVCommentReplyRowCard(reply: reply, isFocused: isFocused)
                            }
                            .buttonStyle(TvCardButtonStyle(isSelected: false, isFocused: isFocused))
                            .focused($focusedTarget, equals: .reply(reply.id))
                            .id(reply.id)
                            .onMoveCommand { dir in
                                if dir == .right {
                                    focusedTarget = .comment(mainComment.id)
                                }
                            }
                        }

                        if hasMoreReplies {
                            Button("加载更多回复", action: onLoadMore)
                                .buttonStyle(TvButtonStyle(variant: .plain, cornerRadius: 10))
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

#Preview {
    struct Wrapper: View {
        @FocusState var focus: CommentFocusTarget?
        var body: some View {
            TVCommentReplyPanel(
                mainComment: TVCommentItem(
                    id: "c1", text: "主评论内容", userName: "用户A", userAvatar: "",
                    userId: "u1", createTime: 0, diggCount: 10, replyCount: 1
                ),
                replies: [],
                totalReplies: 1,
                isLoadingReplies: false,
                replyError: nil,
                hasMoreReplies: false,
                focusedTarget: $focus,
                onClose: {},
                onRetry: {},
                onLoadMore: {}
            )
            .frame(width: 620, height: 800)
            .background(TVColors.drawerBackground)
        }
    }
    return Wrapper()
}
