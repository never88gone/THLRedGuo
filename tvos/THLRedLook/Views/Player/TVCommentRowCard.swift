import SwiftUI

// MARK: - 单条一级评论行卡片
struct TVCommentRowCard: View {
    let comment: TVCommentItem
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                TVCommentAvatarView(url: comment.userAvatar, name: comment.userName, size: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.userName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isFocused ? TVColors.white : TVColors.textPrimary)
                    Text(TVCommentAvatarView.formatTimestamp(comment.createTime))
                        .font(.system(size: 19))
                        .foregroundColor(TVColors.textSecondary)
                }

                Spacer()

                if comment.diggCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20))
                            .foregroundColor(TVColors.activeRed)
                        Text(TVCommentAvatarView.formatNumber(comment.diggCount))
                            .font(.system(size: 20))
                            .foregroundColor(TVColors.textSecondary)
                    }
                }
            }

            Text(comment.text)
                .font(.system(size: 26))
                .lineSpacing(4)
                .foregroundColor(isFocused ? TVColors.white : TVColors.white.opacity(0.92))
                .lineLimit(4)
                .multilineTextAlignment(.leading)

            if comment.replyCount > 0 {
                HStack {
                    Text("\(comment.replyCount) 条回复 >")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(TVColors.activeRed)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(TVColors.activeRed.opacity(0.14))
                        .cornerRadius(10)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(20)
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
