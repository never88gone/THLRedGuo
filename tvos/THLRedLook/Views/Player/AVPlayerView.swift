import SwiftUI
import AVKit

/// 底层视频画面渲染视图（基于纯净的 AVPlayerLayer 与透明 UIView）
/// 彻底去除系统黑底与控件干扰，支持竖屏短剧播放时自然透出底层全局渐变背景
public struct AVPlayerView: UIViewRepresentable {
    public let player: AVPlayer?

    public init(player: AVPlayer?) {
        self.player = player
    }

    public func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.player = player
        return view
    }

    public func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
    }
}

public class PlayerContainerView: UIView {
    public override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    public var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.clear.cgColor
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
