import SwiftUI

// MARK: - 单条二级回复行卡片
struct TVCommentReplyRowCard: View {
    let reply: TVCommentReplyItem
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                TVCommentAvatarView(url: reply.userAvatar, name: reply.userName, size: 40)

                HStack(spacing: 8) {
                    Text(reply.userName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(isFocused ? TVColors.white : TVColors.textPrimary)

                    if !reply.replyToUserName.isEmpty {
                        Text("▶")
                            .font(.system(size: 16))
                            .foregroundColor(TVColors.textSecondary)
                        Text(reply.replyToUserName)
                            .font(.system(size: 22))
                            .foregroundColor(TVColors.textSecondary)
                    }
                }

                Spacer()

                if reply.diggCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 19))
                            .foregroundColor(TVColors.activeRed)
                        Text(TVCommentAvatarView.formatNumber(reply.diggCount))
                            .font(.system(size: 19))
                            .foregroundColor(TVColors.textSecondary)
                    }
                }
            }

            Text(reply.text)
                .font(.system(size: 24))
                .lineSpacing(4)
                .foregroundColor(isFocused ? TVColors.white : TVColors.white.opacity(0.90))
                .lineLimit(5)
                .multilineTextAlignment(.leading)

            Text(TVCommentAvatarView.formatTimestamp(reply.createTime))
                .font(.system(size: 18))
                .foregroundColor(TVColors.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    TVCommentReplyRowCard(
        reply: TVCommentReplyItem(
            id: "r1",
            text: "同意，男主演技在线！",
            userName: "影迷",
            userAvatar: "",
            userId: "u2",
            replyToUserName: "追剧达人",
            createTime: Int(Date().timeIntervalSince1970) - 60,
            diggCount: 15
        ),
        isFocused: false
    )
    .background(TVColors.background)
}
