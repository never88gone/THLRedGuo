import SwiftUI

// MARK: - 联系方式面板主视图
public struct SettingsContactPanel: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text("联系方式")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("如有任何功能建议、体验反馈或技术问题，欢迎加入官方群组或通过邮件联系我们。")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            // 1. Telegram 官方交流与反馈卡片（大屏扫码）
            ContactTelegramCard()

            // 2. 电子邮箱与反馈渠道卡片
            ContactEmailCard()
        }
    }
}

// MARK: - Telegram 官方交流与反馈卡片（大屏扫码）
public struct ContactTelegramCard: View {
    @FocusState private var isFocused: Bool

    public init() {}

    public var body: some View {
        Button(action: {}) {
            HStack(spacing: 28) {
                // 二维码图片展示区
                Image("telegram_qr")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 156, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)

                // 右侧说明
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(TVTheme.primary)

                        Text("Telegram 官方交流群")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)

                        Text("@TANGHULUTVOS")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.75))
                            .clipShape(Capsule())
                    }

                    Text("手机打开 Telegram 扫描左侧二维码，即可加入官方群组；也可直接在客户端搜索 @tanghulutvos 关注反馈。")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.75))
                        .lineSpacing(4)

                    Text("群组链接：https://t.me/tanghulutvos")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(TVTheme.primaryHover)
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(isFocused ? Color(red: 0.16, green: 0.18, blue: 0.25) : Color(red: 0.10, green: 0.11, blue: 0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.08), lineWidth: isFocused ? 2 : 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 22)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityIdentifier("settings.contact.telegram")
    }
}

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
                    .fill(isFocused ? Color(red: 0.18, green: 0.17, blue: 0.22) : Color(red: 0.11, green: 0.11, blue: 0.15))
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
