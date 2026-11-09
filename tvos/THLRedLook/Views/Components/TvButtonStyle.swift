import SwiftUI

/// 适用于 tvOS 遥控器聚焦的标准卡片/按钮样式（参考 thldytv 规范）
public struct TvButtonStyle: ButtonStyle {
    public var variant: TvButtonVariant = .primary
    public var cornerRadius: CGFloat = 14
    public var isFocused: Bool = false

    public init(variant: TvButtonVariant = .primary, cornerRadius: CGFloat = 14, isFocused: Bool = false) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.isFocused = isFocused
    }

    public func makeBody(configuration: Configuration) -> some View {
        TvButtonHelper(
            configuration: configuration,
            variant: variant,
            cornerRadius: cornerRadius,
            isFocusedExternal: isFocused
        )
    }
}

#Preview("TvButtonStyle Showcase") {
    VStack(spacing: 20) {
        Button("Primary Button") {}
            .buttonStyle(TvButtonStyle(variant: .primary, isFocused: true))
        Button("Secondary Button") {}
            .buttonStyle(TvButtonStyle(variant: .secondary, isFocused: false))
    }
    .padding(50)
    .background(TVColors.background)
}
