import SwiftUI

// MARK: - 彻底剥离 tvOS 系统原生白光/白卡片滤镜的纯净 ButtonStyle
public struct TVZeroHighlightButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
