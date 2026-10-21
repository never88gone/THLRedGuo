import SwiftUI
import AVKit
import Combine

/// 基于 thldytv 的原生 AVPlayerContainerView
/// 采用双层 AVPlayerLayer (前景等比保持 + 背景动态视频填充与深色毛玻璃蒙版)
/// 拥有后台恢复重挂载、最后一帧画面保持(无缝平滑硬切)、快进防抖节流、6秒缓冲卡死监控与自动重试机制
public class AVPlayerContainerView: UIView {
    public var player: AVPlayer? {
        didSet {
            guard oldValue !== player else { return }
            oldValue?.pause()
            if let obs = timeObserver {
                oldValue?.removeTimeObserver(obs)
                timeObserver = nil
            }
            playerLayer?.player = player
            bgPlayerLayer?.player = player
            if let newPlayer = player {
                setupTimeObserver(for: newPlayer)
                setupPlayerObservers(for: newPlayer)
            }
        }
    }

    public var playerLayer: AVPlayerLayer?
    public var bgPlayerLayer: AVPlayerLayer?
    public var blurView: UIVisualEffectView?

    public var videoBackgroundStyle: Int = 0 // 0: 毛玻璃视频背景, 1: 视频铺满背景, 2: 纯黑/透明
    public var onVideoEnded: (() -> Void)?
    public var onVideoPlaying: (() -> Void)?
    public var onBufferStuck: (() -> Void)?
    public var onTimeUpdate: ((Double, Double) -> Void)?

    public var shouldPlay: Bool = false {
        didSet {
            if shouldPlay {
                play()
            } else {
                pause()
            }
        }
    }

    public var playbackRate: Double = 1.0 {
        didSet {
            if shouldPlay, let player = player, player.timeControlStatus == .playing {
                player.rate = Float(playbackRate)
            }
        }
    }

    public var initialProgress: Double = 0.0

    // 进度与节流快进快退状态
    private var pendingTargetTime: CMTime? = nil
    private var lastKnownValidTime: Double = 0.0
    private var isScrubbingSeeking: Bool = false
    private var pendingScrubTime: CMTime? = nil
    private var shouldResumePlayAfterSeek: Bool = false

    private var statusObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    private var bufferStuckTimer: Timer?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
        setupNotifications()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func appDidBecomeActive() {
        guard let p = self.player, self.shouldPlay else { return }
        // tvOS 在进出后台时可能偶发解绑图层，恢复时自动重新补绑
        if self.playerLayer?.player == nil {
            self.playerLayer?.player = p
        }
        if self.bgPlayerLayer?.player == nil {
            self.bgPlayerLayer?.player = p
        }
    }

    private func setupLayers() {
        backgroundColor = .black

        // 1. 背景层：等比缩放填满全屏，呈现动态环境色彩
        let bgLayer = AVPlayerLayer()
        bgLayer.videoGravity = .resizeAspectFill
        bgLayer.frame = bounds
        bgLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(bgLayer)
        self.bgPlayerLayer = bgLayer

        // 2. 毛玻璃蒙版：位于背景层之上，生成高级深色质感
        let blurEffect = UIBlurEffect(style: .dark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = bounds
        blurView.alpha = 0.88
        addSubview(blurView)
        self.blurView = blurView

        // 3. 前景主视频层：等比例完整居中展示
        let mainLayer = AVPlayerLayer()
        mainLayer.videoGravity = .resizeAspect
        mainLayer.frame = bounds
        mainLayer.backgroundColor = UIColor.clear.cgColor
        mainLayer.magnificationFilter = .trilinear
        mainLayer.minificationFilter = .trilinear
        mainLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(mainLayer)
        self.playerLayer = mainLayer

        updateBackgroundStyle()
    }

    public func updateBackgroundStyle() {
        let usesBlur = videoBackgroundStyle == 0
        let usesVideoBg = videoBackgroundStyle == 0 || videoBackgroundStyle == 1
        bgPlayerLayer?.isHidden = !usesVideoBg
        blurView?.isHidden = !usesBlur
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
        bgPlayerLayer?.frame = bounds
        blurView?.frame = bounds
    }

    // MARK: - 时间与状态监听

    private func setupTimeObserver(for player: AVPlayer) {
        if let token = timeObserver {
            self.player?.removeTimeObserver(token)
            timeObserver = nil
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 1000)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, let p = self.player, let item = p.currentItem else { return }
            let duration = item.duration
            if duration.isValid && !duration.isIndefinite {
                let currentSec = CMTimeGetSeconds(time)
                let totalSec = CMTimeGetSeconds(duration)
                if totalSec > 0 && !totalSec.isNaN {
                    if currentSec > 0.5 {
                        self.lastKnownValidTime = currentSec
                    }
                    self.onTimeUpdate?(currentSec, totalSec)
                }
            }
        }
    }

    private func setupPlayerObservers(for player: AVPlayer) {
        itemStatusObserver?.invalidate()
        statusObserver?.invalidate()

        if let item = player.currentItem {
            itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] it, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch it.status {
                    case .readyToPlay:
                        self.restorePendingProgressIfNeeded()
                        if self.shouldPlay {
                            self.play()
                        }
                    case .failed:
                        self.stopBufferMonitor()
                        self.onBufferStuck?()
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }

            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleItemDidPlayToEndTime(_:)), name: .AVPlayerItemDidPlayToEndTime, object: item)
        }

        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if p.timeControlStatus == .playing {
                    self.stopBufferMonitor()
                    self.onVideoPlaying?()
                } else if p.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.startBufferMonitor()
                } else if p.timeControlStatus == .paused {
                    self.stopBufferMonitor()
                }
            }
        }
    }

    @objc private func handleItemDidPlayToEndTime(_ notification: Notification) {
        guard shouldPlay else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.shouldPlay else { return }
            self.onVideoEnded?()
        }
    }

    // MARK: - 播放与暂停

    public func play() {
        guard let p = player else { return }
        restorePendingProgressIfNeeded()

        if p.timeControlStatus != .playing,
           let duration = p.currentItem?.duration,
           duration.isValid,
           !duration.isIndefinite,
           p.currentTime().seconds >= duration.seconds - 0.2 {
            p.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                guard let self = self, self.shouldPlay else { return }
                self.startPlayback(p)
            }
            return
        }

        startPlayback(p)
    }

    private func startPlayback(_ p: AVPlayer) {
        p.isMuted = false
        p.playImmediately(atRate: Float(playbackRate))
        if p.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            startBufferMonitor()
        }
    }

    public func pause() {
        player?.pause()
        stopBufferMonitor()
    }

    // MARK: - 进度恢复与快速 Seek 防抖节流

    public func syncInitialProgress(_ progress: Double) {
        guard progress > 0.5 else { return }
        self.lastKnownValidTime = progress
        if let p = player, p.currentItem?.status == .readyToPlay {
            let current = p.currentTime().seconds
            if current < 0.5 || abs(current - progress) > 2.0 {
                let target = CMTime(seconds: progress, preferredTimescale: 1000)
                p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                self.pendingTargetTime = nil
                self.initialProgress = 0.0
            }
        } else {
            self.initialProgress = progress
            self.pendingTargetTime = CMTime(seconds: progress, preferredTimescale: 1000)
        }
    }

    private func restorePendingProgressIfNeeded() {
        guard let p = player else { return }
        if let target = pendingTargetTime, target.seconds > 0.5 {
            p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            self.pendingTargetTime = nil
            self.initialProgress = 0.0
        } else if initialProgress > 0.5, p.currentTime().seconds < 0.5 {
            let target = CMTime(seconds: initialProgress, preferredTimescale: 1000)
            p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            self.initialProgress = 0.0
            self.pendingTargetTime = nil
        }
    }

    public func seekSmoothly(to seconds: Double, completion: (() -> Void)? = nil) {
        guard let p = player else { return }
        let newTime = CMTime(seconds: max(0, seconds), preferredTimescale: 1000)
        if isScrubbingSeeking {
            pendingScrubTime = newTime
        } else {
            performScrubSeek(newTime, player: p, completion: completion)
        }
    }

    private func performScrubSeek(_ time: CMTime, player: AVPlayer, completion: (() -> Void)? = nil) {
        isScrubbingSeeking = true
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            if let nextTime = self.pendingScrubTime {
                self.pendingScrubTime = nil
                self.performScrubSeek(nextTime, player: player, completion: completion)
            } else {
                self.isScrubbingSeeking = false
                completion?()
                if self.shouldResumePlayAfterSeek {
                    self.shouldResumePlayAfterSeek = false
                    if self.shouldPlay { player.play() }
                }
            }
        }
    }

    // MARK: - 清理与无缝画面保留

    /// 关键机制：只暂停音频与解码，不将图层画面重置为 nil，实现切视频时无闪黑的平滑硬切/滑切！
    public func cleanup() {
        stopBufferMonitor()
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
    }

    // MARK: - 6秒缓冲卡死超时检测

    private func startBufferMonitor() {
        stopBufferMonitor()
        guard shouldPlay else { return }

        bufferStuckTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            guard let self = self, self.shouldPlay else { return }
            guard self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
            self.onBufferStuck?()
        }
    }

    private func stopBufferMonitor() {
        bufferStuckTimer?.invalidate()
        bufferStuckTimer = nil
    }

    deinit {
        stopBufferMonitor()
        statusObserver?.invalidate()
        itemStatusObserver?.invalidate()
        if let token = timeObserver {
            player?.removeTimeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

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
        onTimeUpdate: ((Double, Double) -> Void)? = nil
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

        container.videoBackgroundStyle = videoBackgroundStyle
        container.updateBackgroundStyle()
        container.playbackRate = playbackRate
        container.onVideoEnded = onVideoEnded
        container.onVideoPlaying = onVideoPlaying
        container.onBufferStuck = onBufferStuck
        container.onTimeUpdate = onTimeUpdate

        if initialProgress > 0 {
            container.syncInitialProgress(initialProgress)
        }

        if isPlaying {
            if let url = urlString, !url.isEmpty {
                VideoCacheManager.shared.focusOnVideo(urlString: url, namespace: namespace)
            }
            container.shouldPlay = true
        } else {
            container.shouldPlay = false
        }
    }

    public static func dismantleUIView(_ uiView: AVPlayerContainerView, coordinator: ()) {
        uiView.cleanup()
    }
}
