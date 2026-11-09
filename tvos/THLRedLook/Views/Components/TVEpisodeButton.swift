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

#Preview("TVEpisodeButton") {
    HStack(spacing: 12) {
        TVEpisodeButton(episode: Episode(id: "1", title: "第 1 集", number: 1, vip: false), isCurrent: true, isFocused: true) {}
        TVEpisodeButton(episode: Episode(id: "2", title: "第 2 集", number: 2, vip: true), isCurrent: false, isFocused: false) {}
    }
    .frame(width: 240)
    .padding(40)
    .background(TVColors.background)
}
