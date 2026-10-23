import SwiftUI

public enum SettingsCategory: String, CaseIterable, Identifiable {
    case sources = "sources"
    case sync = "sync"
    case cache = "cache"
    case help = "help"
    case contact = "contact"
    case about = "about"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sources: return "站源管理"
        case .sync: return "iCloud 同步"
        case .cache: return "存储与缓存"
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
        case .help: return "questionmark.circle.fill"
        case .contact: return "paperplane.fill"
        case .about: return "info.circle.fill"
        }
    }
}

// MARK: - 左侧导航按钮（无白底纯净焦点，带双态清晰指示）
public struct SettingsNavButton: View {
    public let category: SettingsCategory
    public let isSelected: Bool
    public let isFocused: Bool
    public let action: () -> Void

    public init(
        category: SettingsCategory,
        isSelected: Bool,
        isFocused: Bool,
        action: @escaping () -> Void
    ) {
        self.category = category
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // 左侧选中条指示器
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? TVTheme.primary : Color.clear)
                    .frame(width: 4, height: 26)

                Image(systemName: category.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isFocused ? .white : (isSelected ? TVTheme.primary : .gray))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.system(size: 19, weight: (isSelected || isFocused) ? .bold : .medium))
                        .foregroundColor(isFocused ? .white : (isSelected ? .white : .white.opacity(0.75)))
                    Text(category.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(isFocused ? .white.opacity(0.9) : (isSelected ? .white.opacity(0.7) : .gray))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isFocused ? .white : TVTheme.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isFocused
                            ? TVTheme.primary
                            : (isSelected ? Color(red: 0.22, green: 0.14, blue: 0.17) : Color.clear)
                    )
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 16)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .accessibilityIdentifier("settings.nav.\(category.rawValue)")
    }
}
