import SwiftUI

struct TVSeasonCapsuleCardLabel: View {
    let item: SeasonItem
    let externalFocused: Bool

    @Environment(\.isFocused) private var envIsFocused

    var isFocused: Bool {
        externalFocused || envIsFocused
    }

    var body: some View {
        HStack(spacing: 12) {
            // 小海报缩略图（36x50，圆角 6，内含 PosterArtworkView）
            PosterArtworkView(drama: item.drama, cornerRadius: 6)
                .frame(width: 36, height: 50)
                .clipped()
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isFocused ? (item.isCurrent ? Color.white : TVTheme.focusedBorderColor) : Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: isFocused ? 19 : 18, weight: .bold))
                    .foregroundColor(titleColor)

                if item.isCurrent {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isFocused ? Color.white : Color.red)
                            .frame(width: 6, height: 6)
                        Text("当前播放")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(isFocused ? Color.white : TVColors.activeRedHighlight)
                    }
                } else {
                    Text(item.drama.releaseLabel)
                        .font(.system(size: 13, weight: isFocused ? .semibold : .regular))
                        .foregroundColor(subTitleColor)
                }
            }
            .padding(.trailing, 10)
        }
        .padding(.horizontal, isFocused ? 12 : 10)
        .padding(.vertical, isFocused ? 8 : 6)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderStrokeColor, lineWidth: borderWidth)
        )
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .shadow(color: shadowColor, radius: shadowRadius, y: isFocused ? 4 : 0)
        .animation(TVTheme.focusSpringAnimation, value: isFocused)
    }

    private var titleColor: Color {
        if isFocused {
            return item.isCurrent ? .white : .black
        }
        return .white
    }

    private var subTitleColor: Color {
        if isFocused {
            return item.isCurrent ? .white.opacity(0.9) : Color.black.opacity(0.75)
        }
        return Color.white.opacity(0.65)
    }

    private var borderStrokeColor: Color {
        if isFocused {
            return item.isCurrent ? Color.white : TVTheme.focusedBorderColor
        }
        if item.isCurrent {
            return Color.red.opacity(0.85)
        }
        return Color.white.opacity(0.12)
    }

    private var borderWidth: CGFloat {
        if isFocused {
            return 3.0
        }
        if item.isCurrent {
            return 2.0
        }
        return 1.0
    }

    private var shadowColor: Color {
        if isFocused {
            return item.isCurrent ? Color.red.opacity(0.85) : TVTheme.focusedShadowColor
        }
        if item.isCurrent {
            return Color.red.opacity(0.4)
        }
        return Color.clear
    }

    private var shadowRadius: CGFloat {
        if isFocused {
            return 16.0
        }
        if item.isCurrent {
            return 8.0
        }
        return 0
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            if item.isCurrent {
                TVColors.episodeActiveGradient
            } else {
                TVColors.textPrimaryLight
            }
        } else {
            if item.isCurrent {
                Color.red.opacity(0.25)
            } else {
                TVTheme.surfaceCard
            }
        }
    }
}
