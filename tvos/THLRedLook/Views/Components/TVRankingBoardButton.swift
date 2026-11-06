import SwiftUI

// MARK: - 统一排行榜大Tab按钮
public struct TVRankingBoardButton: View {
    public let board: RankingBoard
    public var isSelected: Bool = false
    public var isFocused: Bool = false
    public var onFocused: (() -> Void)? = nil
    public var onUpCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public var onLeftCommand: (() -> Void)? = nil
    public var onRightCommand: (() -> Void)? = nil
    public let action: () -> Void

    public init(
        board: RankingBoard,
        isSelected: Bool = false,
        isFocused: Bool = false,
        isExternalFocused: Bool? = nil,
        onFocused: (() -> Void)? = nil,
        onUpCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        onLeftCommand: (() -> Void)? = nil,
        onRightCommand: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.board = board
        self.isSelected = isSelected
        self.isFocused = isExternalFocused ?? isFocused
        self.onFocused = onFocused
        self.onUpCommand = onUpCommand
        self.onDownCommand = onDownCommand
        self.onLeftCommand = onLeftCommand
        self.onRightCommand = onRightCommand
        self.action = action
    }

    @Environment(\.isFocused) private var envIsFocused

    public var body: some View {
        let activeFocused = isFocused || envIsFocused
        Button(action: action) {
            VStack(spacing: 6) {
                Text(board.name)
                    .font(.system(size: 20, weight: isSelected ? .black : .bold))
                    .foregroundColor(TVColors.textPrimary)
                    .lineLimit(1)
                Text(board.description)
                    .font(.caption)
                    .foregroundColor(activeFocused ? TVColors.textPrimary.opacity(0.9) : TVColors.textSecondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(width: 240)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? (activeFocused ? TVColors.primaryHover : TVColors.primary) : (activeFocused ? TVColors.surfaceFocused : TVColors.surfaceCard))
            )
            .tvFocusBorder(isFocused: activeFocused, cornerRadius: 14)
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
        .onChange(of: activeFocused) { focused in
            if focused {
                onFocused?()
            }
        }
    }
}

#Preview("TVRankingBoardButton") {
    TVRankingBoardButton(
        board: RankingBoard(id: "hot", name: "热门榜", description: "当下全网最热短剧", source: "hongguo"),
        isSelected: true,
        isFocused: true
    ) {}
    .padding(50)
    .background(TVColors.background)
}
