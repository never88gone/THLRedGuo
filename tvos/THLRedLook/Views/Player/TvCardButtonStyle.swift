import SwiftUI

// MARK: - tvOS 专属卡片焦点按钮样式
public struct TvCardButtonStyle: ButtonStyle {
    public let isSelected: Bool
    public let isFocused: Bool

    public init(isSelected: Bool = false, isFocused: Bool = false) {
        self.isSelected = isSelected
        self.isFocused = isFocused
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isFocused
                            ? TVColors.white.opacity(0.24)
                            : (isSelected ? TVColors.activeRed.opacity(0.18) : TVColors.white.opacity(0.06))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isFocused ? TVColors.white : (isSelected ? TVColors.activeRed : TVColors.white.opacity(0.10)),
                        lineWidth: isFocused ? 2.5 : 1
                    )
            )
            .shadow(color: isFocused ? TVColors.activeRed.opacity(0.5) : TVColors.clear, radius: 10)
            .scaleEffect(isFocused ? 1.025 : 1.0)
            .animation(.easeInOut(duration: 0.16), value: isFocused)
    }
}
