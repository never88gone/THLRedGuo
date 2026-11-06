import SwiftUI

// MARK: - 统一胶囊焦点按钮（分类栏、Tab、选集分段、筛选标签）
public struct TVCapsuleButton: View {
    public let title: String
    public var isSelected: Bool = false
    public var isFocused: Bool = false
    public var isCompact: Bool = false
    public var onFocused: (() -> Void)? = nil
    public var onUpCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public var onLeftCommand: (() -> Void)? = nil
    public var onRightCommand: (() -> Void)? = nil
    public let action: () -> Void

    public init(
        title: String,
        isSelected: Bool = false,
        isFocused: Bool = false,
        isCompact: Bool = false,
        isExternalFocused: Bool? = nil,
        onFocused: (() -> Void)? = nil,
        onUpCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        onLeftCommand: (() -> Void)? = nil,
        onRightCommand: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.isFocused = isExternalFocused ?? isFocused
        self.isCompact = isCompact
        self.onFocused = onFocused
        self.onUpCommand = onUpCommand
        self.onDownCommand = onDownCommand
        self.onLeftCommand = onLeftCommand
        self.onRightCommand = onRightCommand
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TVCapsuleButtonLabel(
                title: title,
                isSelected: isSelected,
                externalFocused: isFocused,
                isCompact: isCompact,
                onFocused: onFocused
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            } else if direction == .left {
                onLeftCommand?()
            } else if direction == .right {
                onRightCommand?()
            }
        }
    }
}

private struct TVCapsuleButtonLabel: View {
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
                Color(white: 0.95)
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

#Preview("TVCapsuleButton") {
    HStack(spacing: 16) {
        TVCapsuleButton(title: "全部短剧", isSelected: true, isFocused: true) {}
        TVCapsuleButton(title: "都市爽文", isSelected: false, isFocused: false) {}
    }
    .padding(50)
    .background(TVColors.background)
}
