import SwiftUI

// MARK: - 统一剧集网格按钮
public struct TVEpisodeButton: View {
    public let episode: Episode
    public var isCurrent: Bool = false
    public var isFocused: Bool = false
    public var onUpCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public let action: () -> Void

    public init(
        episode: Episode,
        isCurrent: Bool = false,
        isFocused: Bool = false,
        isExternalFocused: Bool? = nil,
        onUpCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.episode = episode
        self.isCurrent = isCurrent
        self.isFocused = isExternalFocused ?? isFocused
        self.onUpCommand = onUpCommand
        self.onDownCommand = onDownCommand
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TVEpisodeButtonLabel(
                episode: episode,
                isCurrent: isCurrent,
                externalFocused: isFocused
            )
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            }
        }
    }
}

private struct TVEpisodeButtonLabel: View {
    let episode: Episode
    let isCurrent: Bool
    let externalFocused: Bool

    @Environment(\.isFocused) private var envIsFocused

    var isFocused: Bool {
        externalFocused || envIsFocused
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.system(size: isFocused ? 13 : 11, weight: .bold))
                        .foregroundColor(isFocused ? .white : TVColors.playIconRed)
                }

                Text("\(episode.number)")
                    .font(.system(size: isFocused ? 28 : (isCurrent ? 24 : 22), weight: isFocused ? .heavy : (isCurrent ? .bold : .semibold)))
                    .foregroundColor(textColor)

                if episode.vip {
                    Text("VIP")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(vipTextColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(vipBackgroundView)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74)

            if isCurrent && !isFocused {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .padding(8)
            }
        }
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderStrokeColor, lineWidth: borderWidth)
        )
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .shadow(color: shadowColor, radius: shadowRadius, y: isFocused ? 5 : 0)
        .animation(TVTheme.focusSpringAnimation, value: isFocused)
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private var textColor: Color {
        if isFocused {
            return isCurrent ? .white : .black
        }
        if isCurrent {
            return TVColors.playIconRed
        }
        return Color.white.opacity(0.85)
    }

    private var vipTextColor: Color {
        if isFocused {
            return isCurrent ? .yellow : TVColors.vipTextFocused
        }
        return TVColors.vipAccent
    }

    private var vipBackgroundView: some View {
        if isFocused {
            return isCurrent ? TVColors.tagBackground : TVColors.focusedTagBackground
        }
        return TVColors.tagBackground
    }

    private var borderStrokeColor: Color {
        if isFocused {
            return isCurrent ? Color.white : TVColors.focusedBorderColor
        }
        if isCurrent {
            return Color.red
        }
        return TVColors.borderSubtle
    }

    private var borderWidth: CGFloat {
        if isFocused {
            return TVTheme.focusedBorderWidth
        }
        if isCurrent {
            return 2.5
        }
        return 1.0
    }

    private var shadowColor: Color {
        if isFocused {
            return isCurrent ? TVColors.focusedShadowStrong : TVColors.focusedShadowColor
        }
        if isCurrent {
            return Color.red.opacity(0.45)
        }
        return Color.clear
    }

    private var shadowRadius: CGFloat {
        if isFocused {
            return 16.0
        }
        if isCurrent {
            return 8.0
        }
        return 0
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            if isCurrent {
                TVColors.episodeActiveGradient
            } else {
                Color(white: 0.95)
            }
        } else {
            if isCurrent {
                TVColors.episodeInactiveGradient
            } else {
                TVColors.surfaceCard
            }
        }
    }
}

#Preview("TVEpisodeButton") {
    HStack(spacing: 12) {
        TVEpisodeButton(episode: Episode(id: "1", title: "第 1 集", number: 1, vip: false), isCurrent: true, isFocused: true) {}
        TVEpisodeButton(episode: Episode(id: "2", title: "第 2 集", number: 2, vip: true), isCurrent: false, isFocused: false) {}
    }
    .frame(width: 240)
    .padding(40)
    .background(TVColors.background)
}
