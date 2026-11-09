import SwiftUI

struct TVPlayerWakeAreaView: View {
    let playbackAccessibilityValue: String
    let onQuickSeek: (Double) -> Void
    let onPanBegan: () -> Void
    let onPanChanged: (CGFloat) -> Void
    let onPanEnded: () -> Void
    let onUpCommand: () -> Void
    let onDownCommand: () -> Void
    let onSelect: () -> Void
    let onMenu: () -> Void
    let onMoveCommand: (MoveCommandDirection) -> Void

    @FocusState private var activeWakeFocus: PlayerWakeFocusArea?

    var body: some View {
        ZStack {
            TVRemoteTouchSurfaceView(
                accessibilityValue: playbackAccessibilityValue,
                onPanBegan: onPanBegan,
                onPanChanged: onPanChanged,
                onPanEnded: onPanEnded,
                onLeftArrow: { onQuickSeek(-10) },
                onRightArrow: { onQuickSeek(10) },
                onUpArrow: onUpCommand,
                onDownArrow: onDownCommand,
                onSelect: onSelect,
                onPlayPause: nil,
                onMenu: onMenu
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                Button(action: {
                    onQuickSeek(-10)
                }) {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TVZeroHighlightButtonStyle())
                .focusEffectDisabled()
                .focused($activeWakeFocus, equals: .leftSeek)
                .onExitCommand(perform: onMenu)
                .accessibilityIdentifier("player.directRewind")
                .frame(width: 120)

                Button(action: onSelect) {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TVZeroHighlightButtonStyle())
                .focusEffectDisabled()
                .focused($activeWakeFocus, equals: .centerWake)
                .accessibilityIdentifier("player.wake")
                .accessibilityLabel("显示播放控制")
                .accessibilityValue(playbackAccessibilityValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onExitCommand(perform: onMenu)
                .onMoveCommand(perform: onMoveCommand)

                Button(action: {
                    onQuickSeek(10)
                }) {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TVZeroHighlightButtonStyle())
                .focusEffectDisabled()
                .focused($activeWakeFocus, equals: .rightSeek)
                .onExitCommand(perform: onMenu)
                .accessibilityIdentifier("player.directForward")
                .frame(width: 120)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .defaultFocus($activeWakeFocus, .centerWake)
        .onChange(of: activeWakeFocus) { _, newFocus in
            if newFocus == .leftSeek {
                onQuickSeek(-10)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    activeWakeFocus = .centerWake
                }
            } else if newFocus == .rightSeek {
                onQuickSeek(10)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    activeWakeFocus = .centerWake
                }
            }
        }
    }
}
