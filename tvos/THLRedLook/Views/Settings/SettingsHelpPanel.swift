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
