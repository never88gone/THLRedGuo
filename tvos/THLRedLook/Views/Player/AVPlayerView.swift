import SwiftUI
import AVKit

// MARK: - SwiftUI 代表视图 (UIViewRepresentable)

public struct AVPlayerView: UIViewRepresentable {
    public let player: AVPlayer?
    public var urlString: String? = nil
    public var headers: [String: String] = [:]
    public var namespace: String = "default"
    public var isPlaying: Bool = true
    public var playbackRate: Double = 1.0
    public var videoBackgroundStyle: Int = 0
    public var initialProgress: Double = 0.0
    public var onVideoEnded: (() -> Void)? = nil
    public var onVideoPlaying: (() -> Void)? = nil
    public var onBufferStuck: (() -> Void)? = nil
    public var onTimeUpdate: ((Double, Double) -> Void)? = nil
    public var onPipControllerReady: ((AVPictureInPictureController) -> Void)? = nil

    public init(
        player: AVPlayer? = nil,
        urlString: String? = nil,
        headers: [String: String] = [:],
        namespace: String = "default",
        isPlaying: Bool = true,
        playbackRate: Double = 1.0,
        videoBackgroundStyle: Int = 0,
        initialProgress: Double = 0.0,
        onVideoEnded: (() -> Void)? = nil,
        onVideoPlaying: (() -> Void)? = nil,
        onBufferStuck: (() -> Void)? = nil,
        onTimeUpdate: ((Double, Double) -> Void)? = nil,
        onPipControllerReady: ((AVPictureInPictureController) -> Void)? = nil
    ) {
        self.player = player
        self.urlString = urlString
        self.headers = headers
        self.namespace = namespace
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.videoBackgroundStyle = videoBackgroundStyle
        self.initialProgress = initialProgress
        self.onVideoEnded = onVideoEnded
        self.onVideoPlaying = onVideoPlaying
        self.onBufferStuck = onBufferStuck
        self.onTimeUpdate = onTimeUpdate
        self.onPipControllerReady = onPipControllerReady
    }

    public func makeUIView(context: Context) -> AVPlayerContainerView {
        let container = AVPlayerContainerView()
        configure(container)
        return container
    }

    public func updateUIView(_ uiView: AVPlayerContainerView, context: Context) {
        configure(uiView)
    }

    private func configure(_ container: AVPlayerContainerView) {
        container.managesPlayback = player == nil
        let targetPlayer: AVPlayer?
        if let directPlayer = player {
            targetPlayer = directPlayer
        } else if let url = urlString, !url.isEmpty {
            targetPlayer = VideoCacheManager.shared.getPlayer(for: url, headers: headers, namespace: namespace)
        } else {
            targetPlayer = nil
        }

        if container.player !== targetPlayer {
            container.player = targetPlayer
        }

        if let pip = container.pipController, pip !== container.lastReportedPipController {
            container.lastReportedPipController = pip
            onPipControllerReady?(pip)
        }

        container.videoBackgroundStyle = videoBackgroundStyle
        container.updateBackgroundStyle()
        container.playbackRate = playbackRate
        container.onVideoEnded = onVideoEnded
        container.onVideoPlaying = onVideoPlaying
        container.onBufferStuck = onBufferStuck
        container.onTimeUpdate = onTimeUpdate

        guard container.managesPlayback else { return }

        if initialProgress > 0 {
            container.syncInitialProgress(initialProgress)
        }

        if isPlaying {
            if let url = urlString, !url.isEmpty {
                VideoCacheManager.shared.focusOnVideo(urlString: url, namespace: namespace)
            }
            if !container.shouldPlay {
                container.shouldPlay = true
            }
        } else {
            if container.shouldPlay {
                container.shouldPlay = false
            }
        }
    }

    public static func dismantleUIView(_ uiView: AVPlayerContainerView, coordinator: ()) {
        uiView.cleanup()
    }
}
