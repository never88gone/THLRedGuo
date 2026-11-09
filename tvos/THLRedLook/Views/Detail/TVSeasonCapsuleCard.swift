import SwiftUI

/// 紧凑型季度选择卡片（横向排布，无标题，含小海报与明确当前季高亮徽章）
public struct TVSeasonCapsuleCard: View {
    public let item: SeasonItem
    public var isExternalFocused: Bool = false
    public var onUpCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public let action: () -> Void

    public init(
        item: SeasonItem,
        isExternalFocused: Bool = false,
        onUpCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.isExternalFocused = isExternalFocused
        self.onUpCommand = onUpCommand
        self.onDownCommand = onDownCommand
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TVSeasonCapsuleCardLabel(
                item: item,
                externalFocused: isExternalFocused
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
            }
        }
    }
}
