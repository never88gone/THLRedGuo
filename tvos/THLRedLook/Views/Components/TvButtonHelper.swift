import SwiftUI

struct TvButtonHelper: View {
    let configuration: ButtonStyle.Configuration
    let variant: TvButtonVariant
    let cornerRadius: CGFloat
    let isFocusedExternal: Bool

    @Environment(\.isFocused) var envIsFocused

    var isFocused: Bool {
        isFocusedExternal || envIsFocused
    }

    var body: some View {
        configuration.label
            .foregroundColor(foregroundColors)
            .background(backgroundView)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? TVColors.focusedBorderColor : Color.white.opacity(0.12), lineWidth: isFocused ? TVTheme.focusedBorderWidth : 1.0)
            )
            .scaleEffect(isFocused ? TVTheme.defaultScale : 1.0)
            .shadow(color: isFocused ? TVColors.focusedShadowColor : Color.clear, radius: isFocused ? TVTheme.focusedShadowRadius : 0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
    }

    private var foregroundColors: Color {
        if isFocused {
            return .white
        }
        switch variant {
        case .primary:
            return .white
        case .plain:
            return .white.opacity(0.85)
        case .secondary:
            return .white
        case .destructive:
            return .white
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            switch variant {
            case .primary:
                TVColors.primaryHover
            case .plain:
                TVColors.surfaceFocused
            case .secondary:
                Color.white.opacity(0.3)
            case .destructive:
                Color.red
            }
        } else {
            switch variant {
            case .primary:
                TVColors.primary.opacity(0.4)
            case .plain:
                Color.white.opacity(0.08)
            case .secondary:
                TVColors.surfaceCard
            case .destructive:
                Color.red.opacity(0.5)
            }
        }
    }
}
