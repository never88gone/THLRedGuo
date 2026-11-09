import SwiftUI

@MainActor
struct SourceDiagnosticEntryCardView: View {
    let entry: SourceDiagnosticEntry
    let isFocused: Bool
    let onSelect: () -> Void
    var onUpCommand: (() -> Void)? = nil
    var onDownCommand: (() -> Void)? = nil

    @Environment(\.isFocused) private var envIsFocused

    private var activeFocused: Bool {
        isFocused || envIsFocused
    }

    private var cardBackground: Color {
        if activeFocused {
            return entry.failed ? TVColors.diagnosticFailedBg : TVColors.diagnosticSuccessBg
        } else {
            return entry.failed ? Color.red.opacity(0.12) : Color.white.opacity(0.06)
        }
    }

    private var cardBorderColor: Color {
        if activeFocused {
            return Color.white
        } else {
            return entry.failed ? Color.red.opacity(0.4) : Color.white.opacity(0.08)
        }
    }

    private var cardShadowColor: Color {
        guard activeFocused else { return Color.clear }
        return entry.failed ? Color.red.opacity(0.45) : Color.white.opacity(0.3)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                Text(entry.text)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)

                if !entry.errorDetail.isEmpty {
                    errorDetailRow
                }

                if !entry.suggestion.isEmpty {
                    suggestionRow
                }

                if !entry.logId.isEmpty {
                    HStack(spacing: 6) {
                        Text("LogID:")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.cyan)
                        Text(entry.logId)
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.85))
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(cardBorderColor, lineWidth: activeFocused ? 3.5 : 1)
            )
            .shadow(color: cardShadowColor, radius: activeFocused ? 12 : 0)
            .animation(TVTheme.focusSpringAnimation, value: activeFocused)
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

    private var headerRow: some View {
        HStack(spacing: 14) {
            let statusText: String = (entry.failed ? "失败 · " : "完成 · ") + entry.stage
            let statusColor: Color = entry.failed ? TVColors.diagnosticFailedText : TVColors.diagnosticSuccessText
            Text(statusText)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(statusColor)

            if entry.category != .unknown {
                let badgeBg: Color = entry.failed ? Color.red.opacity(0.85) : Color.blue.opacity(0.8)
                Text(entry.category.tag)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeBg)
                    .clipShape(Capsule())
            }

            if entry.elapsedMs > 0 {
                Text("\(entry.elapsedMs)ms")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Text("详细信息")
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(activeFocused ? .white : .white.opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(activeFocused ? TVTheme.primary : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
    }

    private var errorDetailRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("失败原因:")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.orange)
            Text(entry.errorDetail)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(.orange.opacity(0.95))
        }
    }

    private var suggestionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("排查建议:")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(TVTheme.primaryHover)
            Text(entry.suggestion)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}
