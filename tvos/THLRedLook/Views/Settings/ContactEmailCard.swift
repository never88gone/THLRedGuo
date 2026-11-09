import SwiftUI

// MARK: - 电子邮箱反馈卡片
public struct ContactEmailCard: View {
    @FocusState private var isFocused: Bool

    public init() {}

    public var body: some View {
        Button(action: {}) {
            HStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.orange.opacity(isFocused ? 0.35 : 0.18))
                        .frame(width: 68, height: 68)

                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(isFocused ? .white : .orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text("反馈与技术支持邮箱")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        Text("邮件渠道")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.6))
                            .clipShape(Capsule())
                    }

                    Text("如遇站源失效、多端同步异常或电视端崩溃等问题，可随时向开发者发送邮件附带截图。")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))

                    Text("联系邮箱：support@thltv.com")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(TVTheme.primaryHover)
                        .padding(.top, 2)
                }

                Spacer()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isFocused ? TVColors.contactCardFocusedBg : TVColors.contactCardDefaultBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.06), lineWidth: isFocused ? 2 : 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 20)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityIdentifier("settings.contact.email")
    }
}
