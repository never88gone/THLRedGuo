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

// MARK: - 极简关于信息卡片（只放图标、版本号、编译号）
public struct AboutCompactInfoCard: View {
    public let appVersion: String
    public let appBuild: String

    @FocusState private var isFocused: Bool

    public init(appVersion: String, appBuild: String) {
        self.appVersion = appVersion
        self.appBuild = appBuild
    }

    public var body: some View {
        Button(action: {}) {
            HStack(spacing: 32) {
                // 应用图标
                ZStack {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 120, height: 120)

                    Image("applogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                        .shadow(color: TVTheme.primary.opacity(0.4), radius: 16, x: 0, y: 8)
                }

                // 版本号与编译号
                VStack(alignment: .leading, spacing: 10) {
                    Text("糖葫芦Haw")
                        .font(.system(size: 38, weight: .heavy))
                        .foregroundColor(.white)

                    HStack(spacing: 20) {
                        HStack(spacing: 8) {
                            Text("版本号:")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                            Text("v\(appVersion)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 8) {
                            Text("编译号:")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                            Text(appBuild)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(TVTheme.primaryHover)
                        }
                    }
                }

                Spacer()
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                isFocused ? Color(red: 0.22, green: 0.14, blue: 0.18) : Color(red: 0.15, green: 0.11, blue: 0.14),
                                isFocused ? Color(red: 0.15, green: 0.12, blue: 0.18) : Color(red: 0.11, green: 0.10, blue: 0.13)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
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
        .accessibilityIdentifier("settings.about.compact_info")
    }
}

// MARK: - 免责说明与合规声明卡片
public struct AboutDisclaimerCard: View {
    @FocusState private var isFocused: Bool

    public init() {}

    public var body: some View {
        Button(action: {}) {
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 26))
                    .foregroundColor(isFocused ? TVTheme.primary : .white.opacity(0.65))
                    .frame(width: 32)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("免责声明")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    Text("1. 本项目为独立 Apple tvOS 客户端系统，仅供大屏原生开发技术学习与非商业研究使用；\n2. 短剧及流媒体数据均来源于网络公开接口，开发者不搭建中转服务、不存储任何音视频内容；版权归原版权方所有；\n3. 视频解析与播放均在 Apple TV 设备本地沙箱闭环执行，零隐私数据上报，使用者需对自配内容自行承担法律责任。")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.65))
                        .lineSpacing(5)
                }
                Spacer()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isFocused ? Color(red: 0.18, green: 0.18, blue: 0.22) : Color(red: 0.11, green: 0.11, blue: 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.06), lineWidth: 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 18)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityIdentifier("settings.about.disclaimer")
    }
}
