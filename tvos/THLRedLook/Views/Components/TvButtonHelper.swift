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
                    .stroke(isFocused ? TVColors.focusedBorderColor : TVColors.white.opacity(0.12), lineWidth: isFocused ? TVTheme.focusedBorderWidth : 1.0)
            )
            .scaleEffect(isFocused ? TVTheme.defaultScale : 1.0)
            .shadow(color: isFocused ? TVColors.focusedShadowColor : TVColors.clear, radius: isFocused ? TVTheme.focusedShadowRadius : 0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
    }

    private var foregroundColors: Color {
        if isFocused {
            return TVColors.white
        }
        switch variant {
        case .primary:
            return TVColors.white
        case .plain:
            return TVColors.white.opacity(0.85)
        case .secondary:
            return TVColors.white
        case .destructive:
            return TVColors.white
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
                TVColors.white.opacity(0.3)
            case .destructive:
                TVColors.red
            }
        } else {
            switch variant {
            case .primary:
                TVColors.primary.opacity(0.4)
            case .plain:
                TVColors.white.opacity(0.08)
            case .secondary:
                TVColors.surfaceCard
            case .destructive:
                TVColors.red.opacity(0.5)
            }
        }
    }
}

#Preview {
    Button("测试按钮") {}
        .buttonStyle(TvButtonStyle(variant: .primary))
        .padding(40)
        .background(TVColors.background)
}
