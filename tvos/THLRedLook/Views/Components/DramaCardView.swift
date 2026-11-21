import SwiftUI
import Kingfisher

public struct DramaCardView: View {
    public let drama: Drama
    public var isFocused: Bool = false
    public var watchProgress: Double? = nil
    public var progressText: String? = nil
    public var forceFocused: Bool = false
    public var onUpCommand: (() -> Void)? = nil
    public var onLeftCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public var onSelect: () -> Void

    public init(
        drama: Drama,
        isFocused: Bool = false,
        isExternalFocused: Bool? = nil,
        watchProgress: Double? = nil,
        progressText: String? = nil,
        forceFocused: Bool = false,
        onUpCommand: (() -> Void)? = nil,
        onLeftCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.drama = drama
        self.isFocused = isExternalFocused ?? isFocused
        self.watchProgress = watchProgress
        self.progressText = progressText
        self.forceFocused = forceFocused
        self.onUpCommand = onUpCommand
        self.onLeftCommand = onLeftCommand
        self.onDownCommand = onDownCommand
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            DramaCardLabel(
                drama: drama,
                externalFocused: isFocused,
                watchProgress: watchProgress,
                progressText: progressText,
                forceFocused: forceFocused
            )
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            } else if direction == .left {
                onLeftCommand?()
            }
        }
    }
}

#Preview {
    DramaCardView(
        drama: Drama(
            id: "preview_1",
            title: "都市之战神归来",
            cover: "https://example.com/cover.jpg",
            episodes: 80,
            tags: ["热血", "都市"]
        ),
        watchProgress: 0.45,
        progressText: "看至第 36 集",
        onSelect: {}
    )
    .padding(40)
    .background(TVColors.background)
}
