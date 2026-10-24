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
                // 左侧选中条指示器（获焦时为纯白发光条，选中未获焦时为品牌红指示条，未选中时隐藏）
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(isFocused ? Color.white : (isSelected ? TVTheme.primary : Color.clear))
                    .frame(width: isFocused ? 5 : 4, height: isFocused ? 28 : 22)

                Image(systemName: category.icon)
                    .font(.system(size: isFocused ? 22 : 20, weight: (isFocused || isSelected) ? .bold : .semibold))
                    .foregroundColor(isFocused ? .white : (isSelected ? TVTheme.primary : Color.white.opacity(0.55)))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.system(size: 19, weight: isFocused ? .heavy : (isSelected ? .bold : .medium)))
                        .foregroundColor(isFocused ? .white : (isSelected ? Color.white : Color.white.opacity(0.72)))
                    Text(category.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(isFocused ? Color.white.opacity(0.95) : (isSelected ? Color.white.opacity(0.75) : Color.white.opacity(0.45)))
                }

                Spacer()

                if isFocused {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                } else if isSelected {
                    Circle()
                        .fill(TVTheme.primary)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        isFocused
                            ? AnyShapeStyle(LinearGradient(colors: [TVTheme.primary, TVTheme.primaryHover], startPoint: .leading, endPoint: .trailing))
                            : (isSelected ? AnyShapeStyle(Color(red: 0.22, green: 0.12, blue: 0.16).opacity(0.92)) : AnyShapeStyle(Color.white.opacity(0.03)))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isFocused
                            ? Color.white
                            : (isSelected ? TVTheme.primary.opacity(0.45) : Color.clear),
                        lineWidth: isFocused ? 3.0 : (isSelected ? 1.5 : 0)
                    )
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .shadow(
                color: isFocused ? TVTheme.primary.opacity(0.65) : Color.clear,
                radius: isFocused ? 16 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .accessibilityIdentifier("settings.nav.\(category.rawValue)")
    }
}
