import SwiftUI

struct TVButtonLabel: View {
    let title: String
    let icon: String?
    let isProminent: Bool
    let isFocused: Bool
    @Environment(\.isFocused) private var envIsFocused

    var body: some View {
        let effectiveFocused = isFocused || envIsFocused
        HStack(spacing: 12) {
            if let ic = icon {
                Image(systemName: ic)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(effectiveFocused ? .white : (isProminent ? .white : TVColors.primary))
            }
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(effectiveFocused ? .white : TVColors.textPrimary)
            }
        }
        .padding(.horizontal, title.isEmpty ? 26 : 34)
        .padding(.vertical, 18)
        .frame(minHeight: 66)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isProminent
                        ? (effectiveFocused ? AnyShapeStyle(TVColors.prominentGradient) : AnyShapeStyle(TVColors.primary))
                        : (effectiveFocused ? AnyShapeStyle(LinearGradient(colors: [TVColors.buttonFocusedGradStart, TVColors.buttonFocusedGradEnd], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(TVColors.buttonNeutral))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    effectiveFocused ? Color.white : (isProminent ? Color.clear : TVColors.borderSubtle),
                    lineWidth: effectiveFocused ? 3.0 : 1.0
                )
        )
        .scaleEffect(effectiveFocused ? 1.08 : 1.0)
        .shadow(
            color: effectiveFocused ? TVColors.focusedShadowStrong : Color.clear,
            radius: effectiveFocused ? 18 : 0,
            x: 0,
            y: effectiveFocused ? 4 : 0
        )
        .animation(TVTheme.focusSpringAnimation, value: effectiveFocused)
    }
}
