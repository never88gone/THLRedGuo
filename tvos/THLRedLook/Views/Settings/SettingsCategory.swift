import SwiftUI

public enum SettingsCategory: String, CaseIterable, Identifiable {
    case sources = "sources"
    case sync = "sync"
    case cache = "cache"
    case releaseNotes = "releaseNotes"
    case help = "help"
    case contact = "contact"
    case about = "about"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sources: return "站源管理"
        case .sync: return "iCloud 同步"
        case .cache: return "存储与缓存"
        case .releaseNotes: return "更新内容"
        case .help: return "帮助说明"
        case .contact: return "联系方式"
        case .about: return "系统与关于"
        }
    }

    public var subtitle: String {
        switch self {
        case .sources: return "当前活跃影视源"
        case .sync: return "多端观看记录与配置同步"
        case .cache: return "沙盒空间占用与清理"
        case .releaseNotes: return "版本演进与功能更新日志"
        case .help: return "遥控器操作与核心指南"
        case .contact: return "官方群组与反馈渠道"
        case .about: return "版本号与免责声明"
        }
    }

    public var icon: String {
        switch self {
        case .sources: return "antenna.radiowaves.left.and.right"
        case .sync: return "icloud.fill"
        case .cache: return "internaldrive.fill"
        case .releaseNotes: return "sparkles.rectangle.stack.fill"
        case .help: return "questionmark.circle.fill"
        case .contact: return "paperplane.fill"
        case .about: return "info.circle.fill"
        }
    }
}
