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

/// 全局常驻画中画底层 UIView 承载容器
public final class TVGlobalPiPHostUIView: UIView {
    public let playerLayer = AVPlayerLayer()
    public private(set) var pipController: AVPictureInPictureController?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.clear.cgColor
        layer.addSublayer(playerLayer)

        if AVPictureInPictureController.isPictureInPictureSupported() {
            let controller = AVPictureInPictureController(playerLayer: playerLayer)
            self.pipController = controller
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // 维持极其微小的几何区域，保证在屏幕绘制树中有效但绝不干扰大屏排版
        playerLayer.frame = bounds
    }

    public func attachPlayer(_ player: AVPlayer?) {
        playerLayer.player = player
    }

    public func detachPlayer() {
        playerLayer.player = nil
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
