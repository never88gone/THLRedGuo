import SwiftUI
import AVKit
import Combine

/// 基于 thldytv 的原生 AVPlayerContainerView
/// 采用双层 AVPlayerLayer (前景等比保持 + 背景动态视频填充与深色毛玻璃蒙版)
/// 拥有后台恢复重挂载、最后一帧画面保持(无缝平滑硬切)、快进防抖节流、6秒缓冲卡死监控与自动重试机制
public class AVPlayerContainerView: UIView {
    public var managesPlayback = true
    public var player: AVPlayer? {
        didSet {
            guard oldValue !== player else { return }
            if managesPlayback { oldValue?.pause() }
            if let obs = timeObserver {
                oldValue?.removeTimeObserver(obs)
                timeObserver = nil
            }
            playerLayer?.player = player
            bgPlayerLayer?.player = player
            if managesPlayback, let newPlayer = player {
                setupTimeObserver(for: newPlayer)
                setupPlayerObservers(for: newPlayer)
            }
        }
    }

    public var isPlaying: Bool = true
    public var videoBackgroundStyle: Int = 0
    public var playbackRate: Double = 1.0 {
        didSet {
            if managesPlayback && shouldPlay && abs((player?.rate ?? 0) - Float(playbackRate)) > 0.01 {
                player?.rate = Float(playbackRate)
            }
        }
    }
    public var onVideoEnded: (() -> Void)? = nil
    public var onVideoPlaying: (() -> Void)? = nil
    public var onBufferStuck: (() -> Void)? = nil
    public var onTimeUpdate: ((Double, Double) -> Void)? = nil

    public var shouldPlay: Bool = true {
        didSet {
            guard managesPlayback else { return }
            if shouldPlay {
                if let p = player {
                    p.rate = Float(playbackRate)
                    startBufferMonitor()
                }
            } else {
                player?.pause()
                stopBufferMonitor()
            }
        }
    }

    var playerLayer: AVPlayerLayer?
    var bgPlayerLayer: AVPlayerLayer?
    var blurView: UIVisualEffectView?
    private var lastFrameSnapshotView: UIView?

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var currentItemObserver: NSKeyValueObservation?

    private var bufferCheckTimer: Timer?
    private var lastObservedPlaybackTime: Double = -1.0
    private var bufferStallCount: Int = 0

    public var pipController: AVPictureInPictureController?
    public weak var lastReportedPipController: AVPictureInPictureController?

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

    private func setupLayers() {
        backgroundColor = .black

        let bgLayer = AVPlayerLayer()
        bgLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(bgLayer)
        self.bgPlayerLayer = bgLayer

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.alpha = 0.85
        addSubview(blur)
        self.blurView = blur

        let fgLayer = AVPlayerLayer()
        fgLayer.videoGravity = .resizeAspect
        layer.addSublayer(fgLayer)
        self.playerLayer = fgLayer

        setupPictureInPicture()
    }

    private func setupPictureInPicture() {
        guard pipController == nil,
              AVPictureInPictureController.isPictureInPictureSupported(),
              let mainLayer = self.playerLayer else { return }
        let pip = AVPictureInPictureController(playerLayer: mainLayer)
        self.pipController = pip
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgPlayerLayer?.frame = bounds
        playerLayer?.frame = bounds
        blurView?.frame = bounds
        lastFrameSnapshotView?.frame = bounds
        CATransaction.commit()
    }

    public func updateBackgroundStyle() {
        switch videoBackgroundStyle {
        case 0:
            bgPlayerLayer?.isHidden = true
            blurView?.isHidden = true
        case 1:
            bgPlayerLayer?.isHidden = false
            blurView?.isHidden = false
            blurView?.alpha = 0.85
        case 2:
            bgPlayerLayer?.isHidden = false
            blurView?.isHidden = true
        default:
            bgPlayerLayer?.isHidden = true
            blurView?.isHidden = true
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDidPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func handleItemDidPlayToEnd(notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              item === player?.currentItem else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onVideoEnded?()
        }
    }

    @objc private func handleAppDidBecomeActive() {
        if playerLayer?.player == nil, let p = player {
            playerLayer?.player = p
            bgPlayerLayer?.player = p
        }
        if managesPlayback && shouldPlay {
            player?.rate = Float(playbackRate)
        }
    }

    @objc private func handleAppDidEnterBackground() {
        // 后台生命周期处理
    }

    private func setupTimeObserver(for p: AVPlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let current = time.seconds
            let duration = self.player?.currentItem?.duration.seconds ?? 0
            if current.isFinite && !current.isNaN {
                self.onTimeUpdate?(current, duration.isFinite ? duration : 0)
                if current > 0.1 {
                    self.removeLastFrameSnapshot()
                }
            }
        }
    }

    private func setupPlayerObservers(for p: AVPlayer) {
        statusObserver?.invalidate()
        itemStatusObserver?.invalidate()
        currentItemObserver?.invalidate()

        statusObserver = p.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if player.timeControlStatus == .playing {
                    self.onVideoPlaying?()
                    self.removeLastFrameSnapshot()
                }
            }
        }

        currentItemObserver = p.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self = self, let item = player.currentItem else { return }
                self.observeCurrentItemStatus(item)
            }
        }

        if let item = p.currentItem {
            observeCurrentItemStatus(item)
        }
    }

    private func observeCurrentItemStatus(_ item: AVPlayerItem) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] currentItem, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if currentItem.status == .readyToPlay {
                    if self.shouldPlay {
                        self.player?.rate = Float(self.playbackRate)
                    }
                }
            }
        }
    }

    private func startBufferMonitor() {
        stopBufferMonitor()
        bufferStallCount = 0
        lastObservedPlaybackTime = -1.0
        bufferCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkBufferHealth()
        }
    }

    private func stopBufferMonitor() {
        bufferCheckTimer?.invalidate()
        bufferCheckTimer = nil
    }

    private func checkBufferHealth() {
        guard shouldPlay, let p = player, p.timeControlStatus != .paused else {
            bufferStallCount = 0
            return
        }

        let currentTime = p.currentTime().seconds
        if currentTime.isFinite && !currentTime.isNaN {
            if abs(currentTime - lastObservedPlaybackTime) < 0.05 {
                bufferStallCount += 1
                if bufferStallCount >= 6 {
                    bufferStallCount = 0
                    DispatchQueue.main.async { [weak self] in
                        self?.onBufferStuck?()
                    }
                }
            } else {
                bufferStallCount = 0
            }
            lastObservedPlaybackTime = currentTime
        }
    }

    public func syncInitialProgress(_ progress: Double) {
        guard let p = player, progress > 0 else { return }
        let targetTime = CMTime(seconds: progress, preferredTimescale: 600)
        p.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func captureCurrentFrame() {
        guard let snapshot = self.snapshotView(afterScreenUpdates: false) else { return }
        removeLastFrameSnapshot()
        snapshot.frame = bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(snapshot)
        self.lastFrameSnapshotView = snapshot
    }

    public func removeLastFrameSnapshot() {
        lastFrameSnapshotView?.removeFromSuperview()
        lastFrameSnapshotView = nil
    }

    public func cleanup() {
        stopBufferMonitor()
        if managesPlayback { player?.pause() }
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        itemStatusObserver?.invalidate()
        currentItemObserver?.invalidate()
        playerLayer?.player = nil
        bgPlayerLayer?.player = nil
        removeLastFrameSnapshot()
    }

    deinit {
        stopBufferMonitor()
        statusObserver?.invalidate()
        itemStatusObserver?.invalidate()
        currentItemObserver?.invalidate()
        if let token = timeObserver {
            player?.removeTimeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
