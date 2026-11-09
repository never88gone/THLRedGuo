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
