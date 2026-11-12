import SwiftUI

/// 主播展示卡片（用于我的页面-关注主播列表）
public struct AnchorCardView: View {
    public let anchor: Anchor
    public let isFocused: Bool

    public init(anchor: Anchor, isFocused: Bool = false) {
        self.anchor = anchor
        self.isFocused = isFocused
    }

    public var body: some View {
        VStack(spacing: 14) {
            // 圆形头像
            avatarView
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            isFocused ? TVColors.activeRed : Color.white.opacity(0.18),
                            lineWidth: isFocused ? 3 : 1
                        )
                )
                .shadow(
                    color: isFocused ? TVColors.focusedShadowStrong : Color.black.opacity(0.3),
                    radius: isFocused ? 12 : 6,
                    x: 0,
                    y: 4
                )
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isFocused)

            // 主播名称
            Text(anchor.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(isFocused ? .white : TVColors.textPrimary)
                .lineLimit(1)

            // 粉丝数量
            Text(anchor.intro.isEmpty ? "主播详情" : anchor.intro)
                .font(.system(size: 16))
                .foregroundColor(TVColors.textMuted)
                .lineLimit(1)
        }
        .frame(width: 180, height: 210)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isFocused ? TVColors.surfaceFocused : TVColors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isFocused ? TVColors.activeRed : Color.white.opacity(0.1), lineWidth: isFocused ? 2.5 : 1)
        )
    }

    @ViewBuilder
    private var avatarView: some View {
        if ProcessInfo.processInfo.environment["DISABLE_REMOTE_IMAGES"] != "1", !anchor.avatar.isEmpty, let url = URL(string: anchor.avatar) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(TVColors.textMuted)
            }
        } else {
            ZStack {
                Circle().fill(TVColors.surfaceDark)
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(TVColors.textMuted)
                    .padding(16)
            }
        }
    }
}
