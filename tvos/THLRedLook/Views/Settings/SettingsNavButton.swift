import SwiftUI

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
                    .fill(isFocused ? TVColors.white : (isSelected ? TVTheme.primary : TVColors.clear))
                    .frame(width: isFocused ? 5 : 4, height: isFocused ? 28 : 22)

                Image(systemName: category.icon)
                    .font(.system(size: isFocused ? 26 : 24, weight: (isFocused || isSelected) ? .bold : .semibold))
                    .foregroundColor(isFocused ? TVColors.white : (isSelected ? TVTheme.primary : TVColors.white.opacity(0.55)))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .font(.system(size: 24, weight: isFocused ? .heavy : (isSelected ? .bold : .medium)))
                        .foregroundColor(isFocused ? TVColors.white : (isSelected ? TVColors.white : TVColors.white.opacity(0.72)))
                    Text(category.subtitle)
                        .font(.system(size: 16))
                        .foregroundColor(isFocused ? TVColors.white.opacity(0.95) : (isSelected ? TVColors.white.opacity(0.75) : TVColors.white.opacity(0.45)))
                }

                Spacer()

                if isFocused {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(TVColors.white)
                } else if isSelected {
                    Circle()
                        .fill(TVTheme.primary)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        isFocused
                            ? AnyShapeStyle(LinearGradient(colors: [TVTheme.primary, TVTheme.primaryHover], startPoint: .leading, endPoint: .trailing))
                            : (isSelected ? AnyShapeStyle(TVColors.categorySelectedBg.opacity(0.92)) : AnyShapeStyle(TVColors.white.opacity(0.03)))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isFocused
                            ? TVColors.white
                            : (isSelected ? TVTheme.primary.opacity(0.45) : TVColors.clear),
                        lineWidth: isFocused ? 3.0 : (isSelected ? 1.5 : 0)
                    )
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .shadow(
                color: isFocused ? TVTheme.primary.opacity(0.65) : TVColors.clear,
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

#Preview {
    SettingsNavButton(category: .about, isSelected: true, isFocused: true, action: {})
        .padding()
        .background(TVColors.black)
}
