import SwiftUI

/// 播放器底部功能分段切换条（类似系统 AVPlayer 底部选项卡）
public struct TVPlayerSegmentBar: View {
    @Binding public var selectedTab: TVPlayerBottomTab
    public var onSelectTab: ((TVPlayerBottomTab) -> Void)?
    @FocusState private var focusedTab: TVPlayerBottomTab?

    public init(
        selectedTab: Binding<TVPlayerBottomTab>,
        onSelectTab: ((TVPlayerBottomTab) -> Void)? = nil
    ) {
        self._selectedTab = selectedTab
        self.onSelectTab = onSelectTab
    }

    public var body: some View {
        HStack(spacing: 16) {
            ForEach(TVPlayerBottomTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button(action: {
                    selectedTab = tab
                    onSelectTab?(tab)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? TVColors.white : TVColors.tabInactiveText)

                        Text(tab.title)
                            .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? TVColors.white : TVColors.tabInactiveText)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if isSelected {
                                TVColors.activeRed
                            } else {
                                TVColors.panelCardBg
                            }
                        }
                    )
                    .cornerRadius(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                focusedTab == tab
                                    ? TVColors.liquidGlassActiveBorder
                                    : TVColors.liquidGlassBorder,
                                lineWidth: focusedTab == tab ? 2.5 : 1
                            )
                    )
                    .scaleEffect(focusedTab == tab ? 1.08 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: focusedTab)
                }
                .buttonStyle(.card)
                .focused($focusedTab, equals: tab)
            }
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - 预览
#Preview("TVPlayerSegmentBar") {
    struct PreviewWrapper: View {
        @State private var tab: TVPlayerBottomTab = .episodes
        var body: some View {
            TVPlayerSegmentBar(selectedTab: $tab)
                .padding(40)
                .background(TVColors.transportBarBg)
        }
    }
    return PreviewWrapper()
}
