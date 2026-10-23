import SwiftUI

/// 侧边栏导航主视图（参考 thldytv 的 SidebarView 与 SidebarTabButton）
/// 取代旧式顶部导航栏，提供垂直排布的高性能焦点导航与沉浸式抽屉控制
public struct TVSidebarView: View {
    @Binding public var selectedTab: TVAppTab
    public var focusedNavTab: FocusState<TVAppTab?>.Binding
    public let onSelectTab: (TVAppTab) -> Void
    public let onMoveRight: (TVAppTab) -> Void
    public var onRefreshCurrentTab: (() -> Void)? = nil

    public init(
        selectedTab: Binding<TVAppTab>,
        focusedNavTab: FocusState<TVAppTab?>.Binding,
        onSelectTab: @escaping (TVAppTab) -> Void,
        onMoveRight: @escaping (TVAppTab) -> Void,
        onRefreshCurrentTab: (() -> Void)? = nil
    ) {
        self._selectedTab = selectedTab
        self.focusedNavTab = focusedNavTab
        self.onSelectTab = onSelectTab
        self.onMoveRight = onMoveRight
        self.onRefreshCurrentTab = onRefreshCurrentTab
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部 Logo 与应用名称区（采用真实 App 图标，与全局品牌视觉统一）
            HStack(spacing: 16) {
                Image("applogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
                    )
                    .shadow(color: TVTheme.primary.opacity(0.4), radius: 10, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text("糖葫芦")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(1.2)
                    Text("红果短剧")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TVTheme.textSecondary)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 40)
            .padding(.bottom, 32)

            // Tab 导航列表（垂直排列）
            VStack(alignment: .leading, spacing: 12) {
                ForEach(TVAppTab.allCases) { tab in
                    let isFocused = (focusedNavTab.wrappedValue == tab)
                    TVSidebarTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        isFocused: isFocused,
                        action: {
                            selectedTab = tab
                            onSelectTab(tab)
                        },
                        onMoveRight: {
                            selectedTab = tab
                            onMoveRight(tab)
                        }
                    )
                    .focused(focusedNavTab, equals: tab)
                    .accessibilityIdentifier("nav.\(tab.rawValue)")
                }
            }
            .padding(.horizontal, 20)
            .focusSection()
            .defaultFocus(focusedNavTab, selectedTab)

            Spacer()

            // 底部版本与平台标识
            VStack(alignment: .leading, spacing: 4) {
                Text("THLRedLook v1.0.0")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.45))
                Text("Apple TVOS • 原生独立播放")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.3))
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPlayPauseCommand {
            onRefreshCurrentTab?()
        }
    }
}

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
            HStack(spacing: 16) {
                Image(systemName: tab.icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(iconColor)
                    .frame(width: 36)

                Text(tab.title)
                    .font(.system(size: 22, weight: isFocused || isSelected ? .bold : .semibold))
                    .foregroundColor(contentColor)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
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
