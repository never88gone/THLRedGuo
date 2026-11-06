import SwiftUI

/// 适用于全屏捕获层和透明容器的按钮样式（参考 thldytv 规范）
public struct TvTransparentButtonStyle: ButtonStyle {
    public var cornerRadius: CGFloat = 16
    public var isFocused: Bool = false
    public var focusedScale: CGFloat = 1.0

    public init(cornerRadius: CGFloat = 16, isFocused: Bool = false, focusedScale: CGFloat = 1.0) {
        self.cornerRadius = cornerRadius
        self.isFocused = isFocused
        self.focusedScale = focusedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        TvTransparentButtonHelper(
            configuration: configuration,
            cornerRadius: cornerRadius,
            isFocusedExternal: isFocused,
            focusedScale: focusedScale
        )
    }
}

private struct TvTransparentButtonHelper: View {
    let configuration: ButtonStyle.Configuration
    let cornerRadius: CGFloat
    let isFocusedExternal: Bool
    let focusedScale: CGFloat

    @Environment(\.isFocused) var envIsFocused

    var isFocused: Bool {
        isFocusedExternal || envIsFocused
    }

    var body: some View {
        configuration.label
            .background(Color.clear)
            .cornerRadius(cornerRadius)
            .scaleEffect(isFocused ? focusedScale : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
    }
}

#Preview("TvTransparentButtonStyle") {
    Button("Transparent Surface") {}
        .buttonStyle(TvTransparentButtonStyle(isFocused: true))
        .padding(50)
        .background(TVColors.background)
}
