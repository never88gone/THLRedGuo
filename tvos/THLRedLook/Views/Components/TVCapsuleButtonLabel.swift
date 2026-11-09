import SwiftUI

struct TVCapsuleButtonLabel: View {
    let title: String
    let isSelected: Bool
    let externalFocused: Bool
    let isCompact: Bool
    let onFocused: (() -> Void)?

    @Environment(\.isFocused) private var envIsFocused

    var isFocused: Bool {
        externalFocused || envIsFocused
    }

    var body: some View {
        Text(title)
            .font(.system(
                size: isCompact ? (isFocused ? 16 : 14) : (isFocused ? 19 : 17),
                weight: (isFocused || isSelected) ? .heavy : .medium
            ))
            .foregroundColor(textColor)
            .padding(.horizontal, isCompact ? (isFocused ? 18 : 14) : (isFocused ? 28 : 24))
            .padding(.vertical, isCompact ? (isFocused ? 9 : 7) : (isFocused ? 13 : 11))
            .background(backgroundView)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderStrokeColor, lineWidth: borderWidth)
            )
            .scaleEffect(isFocused ? (isCompact ? 1.05 : 1.08) : 1.0)
            .shadow(color: shadowColor, radius: isCompact ? (isFocused ? 10 : 0) : shadowRadius, y: isFocused ? (isCompact ? 2 : 4) : 0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
            .onChange(of: isFocused) { focused in
                if focused {
                    onFocused?()
                }
            }
    }

    private var textColor: Color {
        if isFocused {
            return isSelected ? .white : .black
        }
        if isSelected {
            return .white
        }
        return Color.white.opacity(0.85)
    }

    private var borderStrokeColor: Color {
        if isFocused {
            return isSelected ? Color.white : TVColors.focusedBorderColor
        }
        if isSelected {
            return TVColors.borderSelected
        }
        return TVColors.borderSubtle
    }

    private var borderWidth: CGFloat {
        if isFocused {
            return TVTheme.focusedCapsuleBorderWidth
        }
        if isSelected {
            return 2.0
        }
        return 1.0
    }

    private var shadowColor: Color {
        if isFocused {
            return isSelected ? TVColors.focusedShadowStrong : TVColors.focusedShadowColor
        }
        if isSelected {
            return Color.red.opacity(0.4)
        }
        return Color.clear
    }

    private var shadowRadius: CGFloat {
        if isFocused {
            return 16.0
        }
        if isSelected {
            return 8.0
        }
        return 0
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            if isSelected {
                TVColors.capsuleSelectedGradient
            } else {
                TVColors.textPrimaryLight
            }
        } else {
            if isSelected {
                TVColors.capsuleDefaultGradient
            } else {
                TVColors.surfaceCard
            }
        }
    }
}
