import SwiftUI

/// 播放器底部功能分栏枚举（对齐 ATV-Bilibili-demo 与系统 AVPlayer 底部浮层）
public enum TVPlayerBottomTab: String, CaseIterable, Identifiable {
    case episodes = "选集"
    case related = "相关短剧"
    case interaction = "互动"
    case settings = "设置"
    case danmaku = "弹幕"

    public var id: String { rawValue }

    public var title: String { rawValue }

    public var iconName: String {
        switch self {
        case .episodes:
            return "list.number"
        case .related:
            return "sparkles.tv"
        case .interaction:
            return "heart.circle"
        case .settings:
            return "gearshape"
        case .danmaku:
            return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - 预览
#Preview("TVPlayerBottomTab Preview") {
    VStack(spacing: 20) {
        ForEach(TVPlayerBottomTab.allCases) { tab in
            HStack(spacing: 12) {
                Image(systemName: tab.iconName)
                    .foregroundColor(TVColors.red)
                Text(tab.title)
                    .foregroundColor(TVColors.white)
            }
            .padding()
            .background(TVColors.surfaceCard)
            .cornerRadius(12)
        }
    }
    .padding(40)
    .background(TVColors.backgroundGradient)
}
