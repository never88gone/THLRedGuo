import SwiftUI
import UIKit

public struct TVRemoteTouchSurfaceView: UIViewRepresentable {
    public var accessibilityValue: String? = nil
    public var onPanBegan: () -> Void
    public var onPanChanged: (CGFloat) -> Void
    public var onPanEnded: () -> Void
    public var onLeftArrow: (() -> Void)? = nil
    public var onRightArrow: (() -> Void)? = nil
    public var onUpArrow: (() -> Void)? = nil
    public var onDownArrow: (() -> Void)? = nil
    public var onSelect: (() -> Void)? = nil
    public var onPlayPause: (() -> Void)? = nil
    public var onMenu: (() -> Void)? = nil

    public init(
        accessibilityValue: String? = nil,
        onPanBegan: @escaping () -> Void,
        onPanChanged: @escaping (CGFloat) -> Void,
        onPanEnded: @escaping () -> Void,
        onLeftArrow: (() -> Void)? = nil,
        onRightArrow: (() -> Void)? = nil,
        onUpArrow: (() -> Void)? = nil,
        onDownArrow: (() -> Void)? = nil,
        onSelect: (() -> Void)? = nil,
        onPlayPause: (() -> Void)? = nil,
        onMenu: (() -> Void)? = nil
    ) {
        self.accessibilityValue = accessibilityValue
        self.onPanBegan = onPanBegan
        self.onPanChanged = onPanChanged
        self.onPanEnded = onPanEnded
        self.onLeftArrow = onLeftArrow
        self.onRightArrow = onRightArrow
        self.onUpArrow = onUpArrow
        self.onDownArrow = onDownArrow
        self.onSelect = onSelect
        self.onPlayPause = onPlayPause
        self.onMenu = onMenu
    }

    public func makeUIView(context: Context) -> TVTouchCapturingView {
        let view = TVTouchCapturingView()
        updateProps(view)
        return view
    }

    public func updateUIView(_ uiView: TVTouchCapturingView, context: Context) {
        updateProps(uiView)
    }

    private func updateProps(_ view: TVTouchCapturingView) {
        view.accessibilityValue = accessibilityValue
        view.onPanBegan = onPanBegan
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onUpArrow = onUpArrow
        view.onDownArrow = onDownArrow
        view.onSelect = onSelect
        view.onPlayPause = onPlayPause
        view.onMenu = onMenu
    }
}
