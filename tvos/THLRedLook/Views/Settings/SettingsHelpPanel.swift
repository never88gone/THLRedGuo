import SwiftUI

// MARK: - 帮助说明面板主视图
public struct SettingsHelpPanel: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text("帮助说明")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("了解 Apple TV 遥控器核心手势操作与系统特色功能使用技巧。")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            // 1. 遥控器与手势操作指引
            HelpItemCard(
                title: "Apple TV 遥控器操作指南",
                subtitle: "全屏播放与导航专属按键映射",
                icon: "appletvremote.gen4.fill",
                accentColor: .purple,
                identifier: "settings.help.remote",
                tips: [
                    "左右方向键：单按独立快退/快进 10 秒，弹出轻量胶囊进度条，不遮挡画面",
                    "触控表面滑动：手指在 Siri Remote 触控板横向平滑滑动，可快速大跨度拖拽视频进度",
                    "Select 确认键：播放时点击唤出完整控制菜单（选集、倍速、画质、弹幕设置）",
                    "Menu 返回键：短按收起播放控制浮层，再次短按退出播放返回上级剧集详情页",
                    "播放/暂停键：遥控器实体播放键随时暂停或恢复当前短剧流"
                ]
            )

            // 2. iCloud 多端云端漫游指南
            HelpItemCard(
                title: "iCloud 多端观看记录同步",
                subtitle: "iOS、macOS 与 Apple TV 全生态漫游",
                icon: "icloud.fill",
                accentColor: .blue,
                identifier: "settings.help.icloud",
                tips: [
                    "同一账号：在所有苹果设备登录同一个 Apple ID 即可自动开启",
                    "设置开启：在设置「iCloud 同步」中点击「启用 iCloud 云端同步」开关",
                    "即时漫游：在手机上看到的剧集进度，回到电视大屏无缝自动续播"
                ]
            )

            // 3. 常见播放问题与站源诊断
            HelpItemCard(
                title: "播放故障重试与站源诊断",
                subtitle: "如何自测网络并排查播放异常",
                icon: "wrench.and.screwdriver.fill",
                accentColor: .orange,
                identifier: "settings.help.troubleshooting",
                tips: [
                    "原地重试：播放失败时画面将弹出「重试」与「返回剧集」按钮",
                    "站源诊断：在设置「站源管理」中点击「影视源健康诊断」进行链路体检",
                    "缓存清理：若遇到画面卡顿，可在「存储与缓存」中清理临时播放切片"
                ]
            )
        }
    }
}

// MARK: - 帮助说明卡片（可聚焦，支持遥控器导航与无裁切高亮）
public struct HelpItemCard: View {
    public let title: String
    public let subtitle: String
    public let icon: String
    public var accentColor: Color = .purple
    public let identifier: String
    public let tips: [String]

    @FocusState private var isFocused: Bool

    public init(
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color = .purple,
        identifier: String,
        tips: [String]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accentColor = accentColor
        self.identifier = identifier
        self.tips = tips
    }

    public var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(accentColor.opacity(isFocused ? 0.35 : 0.18))
                            .frame(width: 56, height: 56)

                        Image(systemName: icon)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(isFocused ? .white : accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.68))
                    }

                    Spacer()
                }

                // 指南条目细则
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(isFocused ? accentColor : Color.white.opacity(0.4))
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)

                            Text(tip)
                                .font(.system(size: 15))
                                .foregroundColor(isFocused ? .white.opacity(0.95) : .white.opacity(0.72))
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(.leading, 8)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isFocused ? Color(red: 0.18, green: 0.18, blue: 0.24) : Color(red: 0.11, green: 0.11, blue: 0.15))
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
        .accessibilityIdentifier(identifier)
    }
}
