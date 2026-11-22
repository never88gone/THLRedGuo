import SwiftUI

// MARK: - 单条一级评论行卡片
struct TVCommentRowCard: View {
    let comment: TVCommentItem
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                TVCommentAvatarView(url: comment.userAvatar, name: comment.userName, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.userName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isFocused ? TVColors.white : TVColors.textPrimary)
                    Text(TVCommentAvatarView.formatTimestamp(comment.createTime))
                        .font(.caption2)
                        .foregroundColor(TVColors.textSecondary)
                }

                Spacer()

                if comment.diggCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(TVColors.activeRed)
                        Text(TVCommentAvatarView.formatNumber(comment.diggCount))
                            .font(.caption2)
                            .foregroundColor(TVColors.textSecondary)
                    }
                }
            }

            Text(comment.text)
                .font(.system(size: 15))
                .foregroundColor(isFocused ? TVColors.white : TVColors.white.opacity(0.92))
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if comment.replyCount > 0 {
                HStack {
                    Text("\(comment.replyCount) 条回复 >")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(TVColors.activeRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(TVColors.activeRed.opacity(0.14))
                        .cornerRadius(8)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    TVCommentRowCard(
        comment: TVCommentItem(
            id: "c1",
            text: "剧情太精彩了，根本停不下来！",
            userName: "追剧达人",
            userAvatar: "",
            userId: "u1",
            createTime: Int(Date().timeIntervalSince1970) - 300,
            diggCount: 128,
            replyCount: 12
        ),
        isFocused: false
    )
    .background(TVColors.background)
}
