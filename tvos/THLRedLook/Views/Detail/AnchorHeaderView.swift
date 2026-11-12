import SwiftUI

/// 主播页面顶部信息与关注操作组件
public struct AnchorHeaderView: View {
    public let anchor: Anchor
    public let isFollowed: Bool
    public let onToggleFollow: () -> Void
    public let onBack: () -> Void
    @FocusState private var focusedButton: AnchorHeaderFocus?

    public init(
        anchor: Anchor,
        isFollowed: Bool,
        onToggleFollow: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.anchor = anchor
        self.isFollowed = isFollowed
        self.onToggleFollow = onToggleFollow
        self.onBack = onBack
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 40) {
            // 返回按钮
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(focusedButton == .back ? .white : TVColors.textPrimary)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(focusedButton == .back ? TVColors.activeRed : TVColors.surfaceCard)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(focusedButton == .back ? 0.9 : 0.15), lineWidth: 2)
                    )
            }
            .buttonStyle(TVZeroHighlightButtonStyle())
            .focused($focusedButton, equals: .back)
            .accessibilityIdentifier("anchor.back")

            // 主播头像
            avatarView
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 6)

            // 主播基本信息
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 24) {
                    Text(anchor.name)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(TVColors.textPrimary)
                        .lineLimit(1)

                    // 关注按钮
                    Button(action: onToggleFollow) {
                        HStack(spacing: 8) {
                            Image(systemName: isFollowed ? "checkmark" : "plus")
                                .font(.system(size: 18, weight: .bold))
                            Text(isFollowed ? "已关注" : "关注")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    isFollowed
                                        ? (focusedButton == .follow ? TVColors.surfaceFocused : TVColors.surfaceCard)
                                        : (focusedButton == .follow ? TVColors.activeRedHighlight : TVColors.activeRed)
                                )
                        )
                        .foregroundColor(TVColors.textPrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(focusedButton == .follow ? 0.9 : 0.2), lineWidth: 2)
                        )
                    }
                    .buttonStyle(TVZeroHighlightButtonStyle())
                    .focused($focusedButton, equals: .follow)
                    .accessibilityIdentifier("anchor.follow")
                }

                HStack(spacing: 28) {
                    Text("粉丝: \(anchor.displayFollowerCount)")
                        .font(.system(size: 20))
                        .foregroundColor(TVColors.textSecondary)

                    Text("短剧作品: \(anchor.worksCount) 部")
                        .font(.system(size: 20))
                        .foregroundColor(TVColors.textSecondary)
                }

                Text(anchor.intro)
                    .font(.system(size: 20))
                    .foregroundColor(TVColors.textMuted)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 60)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var avatarView: some View {
        if !anchor.avatar.isEmpty, let url = URL(string: anchor.avatar) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(TVColors.textMuted)
            }
        } else {
            ZStack {
                Circle().fill(TVColors.surfaceFocused)
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(TVColors.textMuted)
                    .padding(20)
            }
        }
    }
}
