import UIKit
import AVKit

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
