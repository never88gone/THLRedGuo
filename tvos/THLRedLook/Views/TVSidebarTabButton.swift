import SwiftUI

/// 侧边栏单个 Tab 按钮（参考 thldytv 的 SidebarTabButton 规范）
public struct TVSidebarTabButton: View {
    public let tab: TVAppTab
    public let isSelected: Bool
    public let isFocused: Bool
    public let action: () -> Void
    public let onMoveRight: () -> Void

    public init(
        tab: TVAppTab,
        isSelected: Bool,
        isFocused: Bool,
        action: @escaping () -> Void,
        onMoveRight: @escaping () -> Void
    ) {
        self.tab = tab
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.action = action
        self.onMoveRight = onMoveRight
    }

    private var contentColor: Color {
        if isFocused || isSelected {
            return .white
        }
        return Color.white.opacity(0.75)
    }

    private var iconColor: Color {
        if isFocused || isSelected {
            return .white
        }
        return Color.white.opacity(0.6)
    }

    private var buttonBackgroundStyle: AnyShapeStyle {
        if isFocused {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [TVTheme.primary, TVTheme.primaryHover],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        } else if isSelected {
            return AnyShapeStyle(Color.white.opacity(0.14))
        } else {
            return AnyShapeStyle(Color.white.opacity(0.04))
        }
    }

    private var borderColor: Color {
        if isFocused {
            return TVTheme.focusedBorderColor
        } else if isSelected {
            return Color.white.opacity(0.2)
        } else {
            return Color.white.opacity(0.06)
        }
    }

    private var borderWidth: CGFloat {
        isFocused ? 2.5 : 1.0
    }

    private var shadowColor: Color {
        isFocused ? TVTheme.focusedShadowColor : Color.clear
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: tab.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(iconColor)
                    .frame(width: 32)

                Text(tab.title)
                    .font(.system(size: 20, weight: isFocused || isSelected ? .bold : .semibold))
                    .foregroundColor(contentColor)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(buttonBackgroundStyle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(
                color: shadowColor,
                radius: isFocused ? 14 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .right {
                onMoveRight()
            }
        }
    }
}
