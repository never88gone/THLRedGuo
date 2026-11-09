import SwiftUI
import AVKit

/// Apple tvOS 全局常驻画中画宿主容器
/// 始终常驻挂载于应用主根视图（MainTabView），保证其 AVPlayerLayer 永不脱离 Window 视图树，
/// 从根本上解决进入画中画后子页面退出导致系统将浮窗强制销毁的问题。
public struct TVGlobalPiPHostView: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> TVGlobalPiPHostUIView {
        let view = TVGlobalPiPHostUIView()
        TVPictureInPictureCoordinator.shared.bindGlobalHost(view: view)
        return view
    }

    public func updateUIView(_ uiView: TVGlobalPiPHostUIView, context: Context) {
        // 全局宿主仅作为图层常驻锚点，播放状态由 Coordinator 统一调度
    }
}

// MARK: - 预览
#Preview("TV Global PiP Host") {
    ZStack {
        TVColors.backgroundGradient
            .ignoresSafeArea()
        TVGlobalPiPHostView()
            .frame(width: 1, height: 1)
    }
}
