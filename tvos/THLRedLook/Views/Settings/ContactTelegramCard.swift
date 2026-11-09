import SwiftUI

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
                    .fill(isFocused ? TVColors.contactFocusedBg : TVColors.contactDefaultBg)
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
