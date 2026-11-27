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
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .bold))
                        Text("收起回复")
                            .font(.system(size: 22, weight: .bold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
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

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    TVCommentAvatarView(url: mainComment.userAvatar, name: mainComment.userName, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mainComment.userName)
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(TVColors.textPrimary)
                        Text(TVCommentAvatarView.formatTimestamp(mainComment.createTime))
                            .font(.system(size: 19))
                            .foregroundColor(TVColors.textSecondary)
                    }
                    Spacer()
                    if mainComment.diggCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 19))
                                .foregroundColor(TVColors.activeRed)
                            Text(TVCommentAvatarView.formatNumber(mainComment.diggCount))
                                .font(.system(size: 19))
                                .foregroundColor(TVColors.textSecondary)
                        }
                    }
                }

                Text(mainComment.text)
                    .font(.system(size: 24))
                    .lineSpacing(4)
                    .foregroundColor(TVColors.textPrimary)
                    .lineLimit(4)
            }
            .padding(20)
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
