import SwiftUI

// MARK: - Apple TV 大屏统一字体与排版规范系统 (遵循 10-Foot UI 标准)
public enum TVTypography {
    // MARK: - 基础字号规范
    /// 微型角标、VIP 徽章、卡片状态标签 (16pt)
    public static let badge: CGFloat = 16.0
    /// 辅助说明、进度文字、次级信息 (18pt)
    public static let caption: CGFloat = 18.0
    /// 模态副标题、按 Menu 返回气泡、设置项副标题 (20pt)
    public static let subheadline: CGFloat = 20.0
    /// 普通正文、抽屉选项描述 (22pt)
    public static let body: CGFloat = 22.0
    /// 标准按钮文字、顶部类型标签、卡片主标题 (24pt ~ 26pt)
    public static let buttonRegular: CGFloat = 26.0
    public static let cardTitle: CGFloat = 24.0
    /// 重点主按钮 (立即播放)、大型分类 Tab (28pt ~ 30pt)
    public static let buttonLarge: CGFloat = 28.0
    public static let tabLarge: CGFloat = 28.0
    /// 页面级副标题、弹窗主标题 (34pt)
    public static let title: CGFloat = 34.0
    /// 页面超大标题 (42pt)
    public static let largeTitle: CGFloat = 42.0

    // MARK: - 按钮尺寸与内边距标准
    public static let buttonHeightSmall: CGFloat = 56.0
    public static let buttonHeightRegular: CGFloat = 68.0
    public static let buttonHeightLarge: CGFloat = 76.0
}
