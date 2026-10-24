import SwiftUI

/// 针对 tvOS 系统 NavigationSplitView 提供的自定义替代方案（参考 thldytv 规范）
/// 采用全屏内容底层 + 左侧悬浮高奢毛玻璃抽屉侧边栏，规避系统自带原生导航栏的焦点 Bug 与高度挤占
public struct TVCustomSplitView<Sidebar: View, Detail: View>: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self._columnVisibility = columnVisibility
        self.sidebar = sidebar
        self.detail = detail
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            // 主内容区域：占满全屏，无边框与顶部栏挤压，极致沉浸
            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(columnVisibility != .detailOnly)
                .focusSection()
                .zIndex(0)

            // 侧边栏浮层：当 columnVisibility != .detailOnly 时展开
            if columnVisibility != .detailOnly {
                HStack(spacing: 0) {
                    sidebar()
                        .frame(width: 380)
                        .background(
                            Material.regular
                        )
                        .background(
                            Color(red: 0.08, green: 0.07, blue: 0.09).opacity(0.88)
                        )
                        .cornerRadius(26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1.2)
                        )
                        .shadow(color: Color.black.opacity(0.85), radius: 36, x: 12, y: 0)
                        .padding(.leading, 48)
                        .padding(.vertical, 36)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .focusSection()

                    Spacer()
                }
                .zIndex(10)
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: columnVisibility)
    }
}
