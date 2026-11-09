import SwiftUI

// MARK: - 系统与关于面板（极简纯粹：仅图标、版本号、编译号与免责说明）
public struct SettingsAboutPanel: View {
    public init() {}

    private var appVersionNumber: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text("系统与关于")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("Apple tvOS 纯原生独立大屏端短剧体验系统。")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            // 1. 核心版本信息卡片（图标 + 版本号 + 编译号）
            AboutCompactInfoCard(
                appVersion: appVersionNumber,
                appBuild: appBuildNumber
            )

            // 2. 免责声明与合规承诺卡片
            AboutDisclaimerCard()
        }
    }
}
