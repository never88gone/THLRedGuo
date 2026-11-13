import SwiftUI

/// 主播页面顶部信息与关注操作组件
public struct AnchorHeaderView: View {
    public let anchor: Anchor
    public let isFollowed: Bool
    public let followEnabled: Bool
    public let onToggleFollow: () -> Void
    private let focus: FocusState<AnchorHeaderFocus?>.Binding
    private let onDownCommand: () -> Void

    public init(
        anchor: Anchor,
        isFollowed: Bool,
        followEnabled: Bool = true,
        focus: FocusState<AnchorHeaderFocus?>.Binding,
        onToggleFollow: @escaping () -> Void,
        onDownCommand: @escaping () -> Void
    ) {
        self.anchor = anchor
        self.isFollowed = isFollowed
        self.followEnabled = followEnabled
        self.onToggleFollow = onToggleFollow
        self.focus = focus
        self.onDownCommand = onDownCommand
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 40) {
            avatarView
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 24) {
                    Text(anchor.name)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(TVColors.textPrimary)
                        .lineLimit(1)

                    if HongguoAccountModel.shared.loggedIn {
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
                                            ? (focus.wrappedValue == .follow ? TVColors.surfaceFocused : TVColors.surfaceCard)
                                            : (focus.wrappedValue == .follow ? TVColors.activeRedHighlight : TVColors.activeRed)
                                    )
                            )
                            .foregroundColor(TVColors.textPrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(focus.wrappedValue == .follow ? 0.9 : 0.2), lineWidth: 2)
                            )
                        }
                        .buttonStyle(TVZeroHighlightButtonStyle())
                        .focused(focus, equals: .follow)
                        .accessibilityIdentifier("anchor.follow")
                        .disabled(!followEnabled)
                        .onMoveCommand { if $0 == .down { onDownCommand() } }
                    }
                }

                HStack(spacing: 28) {
                    if anchor.followerCount != nil { Text("粉丝: \(anchor.displayFollowerCount)") }
                    if let count = anchor.worksCount { Text("作品: \(count)") }
                }.font(.system(size: 20)).foregroundColor(TVColors.textSecondary)

                Text(anchor.intro.isEmpty ? "暂无简介" : anchor.intro)
                    .font(.system(size: 20))
                    .foregroundColor(TVColors.textMuted)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 60)
        .padding(.top, 40)
        .padding(.bottom, 20)
        .focusSection()
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
