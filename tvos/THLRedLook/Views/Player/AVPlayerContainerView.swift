import SwiftUI
import AVKit
import Combine

/// 基于 thldytv 的原生 AVPlayerContainerView
/// 采用双层 AVPlayerLayer (前景等比保持 + 背景动态视频填充与深色毛玻璃蒙版)
/// 拥有后台恢复重挂载、最后一帧画面保持(无缝平滑硬切)、快进防抖节流、6秒缓冲卡死监控与自动重试机制
public class AVPlayerContainerView: UIView {
    public static let willTransitionNotification = Notification.Name("THLRedLook.AVPlayerContainerWillTransition")
    public static let didCancelTransitionNotification = Notification.Name("THLRedLook.AVPlayerContainerDidCancelTransition")

    public var managesPlayback = true
    public var lastTransitionEpoch: Int = 0
    public var hasTransitionSnapshot: Bool { lastFrameSnapshotView != nil }
    public var player: AVPlayer? {
        didSet {
            guard oldValue !== player else { return }
            if oldValue != nil, player != nil, lastFrameSnapshotView == nil {
                captureCurrentFrame(from: oldValue)
            }
            if managesPlayback { oldValue?.pause() }
            if let obs = timeObserver {
                oldValue?.removeTimeObserver(obs)
                timeObserver = nil
            }
            playerLayer?.player = player
            bgPlayerLayer?.player = player
            if let newPlayer = player {
                if managesPlayback {
                    setupTimeObserver(for: newPlayer)
                }
                setupPlayerObservers(for: newPlayer)
                evaluateTransitionCompletion()
            } else {
                statusObserver?.invalidate()
                itemStatusObserver?.invalidate()
                currentItemObserver?.invalidate()
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
    private var readyForDisplayObserver: NSKeyValueObservation?
    private weak var transitionOldPlayer: AVPlayer?
    private weak var transitionOldItem: AVPlayerItem?
    private var isAwaitingTransitionFrame: Bool = false
    private var transitionFallbackWorkItem: DispatchWorkItem?

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
        backgroundColor = TVColors.uiBlack

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

        readyForDisplayObserver = fgLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.evaluateTransitionCompletion()
            }
        }

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
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleItemDidPlayToEnd), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        center.addObserver(self, selector: #selector(handleAppDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleAppDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(handleWillTransitionNotification), name: Self.willTransitionNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidCancelTransitionNotification), name: Self.didCancelTransitionNotification, object: nil)
    }

    @objc private func handleWillTransitionNotification(_ notification: Notification) {
        guard notification.object == nil || (notification.object as AnyObject) === player else { return }
        captureCurrentFrame()
    }

    @objc private func handleDidCancelTransitionNotification(_ notification: Notification) {
        guard notification.object == nil || (notification.object as AnyObject) === player else { return }
        clearTransitionSnapshot(animated: true)
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
                    if self.isAwaitingTransitionFrame {
                        self.evaluateTransitionCompletion()
                    } else {
                        self.removeLastFrameSnapshot()
                    }
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
                    if self.managesPlayback {
                        self.onVideoPlaying?()
                    }
                    self.evaluateTransitionCompletion()
                }
            }
        }

        currentItemObserver = p.observe(\.currentItem, options: [.old, .new]) { [weak self] player, change in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let oldItem = change.oldValue ?? nil
                if let oldItem, let newItem = player.currentItem, oldItem !== newItem, self.lastFrameSnapshotView == nil {
                    self.captureCurrentFrame(from: player, preferredItem: oldItem)
                }
                if let item = player.currentItem {
                    self.observeCurrentItemStatus(item)
                    self.evaluateTransitionCompletion()
                }
            }
        }

        if let item = p.currentItem {
            observeCurrentItemStatus(item)
        }
    }

    private func observeCurrentItemStatus(_ item: AVPlayerItem) {
        itemStatusObserver?.invalidate()
        if item.status == .readyToPlay {
            evaluateTransitionCompletion()
        }
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] currentItem, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if currentItem.status == .readyToPlay {
                    if self.managesPlayback, self.shouldPlay {
                        self.player?.rate = Float(self.playbackRate)
                    }
                    self.evaluateTransitionCompletion()
                } else if currentItem.status == .failed {
                    self.clearTransitionSnapshot(animated: false)
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

    private func scheduleTransitionFallback() {
        transitionFallbackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.clearTransitionSnapshot(animated: true)
        }
        transitionFallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func evaluateTransitionCompletion() {
        guard isAwaitingTransitionFrame, lastFrameSnapshotView != nil else { return }
        guard let currentPlayer = player, let item = currentPlayer.currentItem else { return }
        let switched = (currentPlayer !== transitionOldPlayer) || (item !== transitionOldItem)
        guard switched,
              let layer = playerLayer,
              layer.isReadyForDisplay,
              item.status == .readyToPlay else { return }
        clearTransitionSnapshot(animated: true)
    }

    public func captureCurrentFrame(from sourcePlayer: AVPlayer? = nil, preferredItem: AVPlayerItem? = nil) {
        let targetPlayer = sourcePlayer ?? player
        if isAwaitingTransitionFrame, lastFrameSnapshotView != nil, playerLayer?.isReadyForDisplay != true {
            transitionOldPlayer = targetPlayer
            transitionOldItem = preferredItem ?? targetPlayer?.currentItem
            scheduleTransitionFallback()
            return
        }

        guard !bounds.isEmpty, window != nil,
              let resolvedSnapshot = self.snapshotView(afterScreenUpdates: false) else { return }

        removeLastFrameSnapshot()
        resolvedSnapshot.frame = bounds
        resolvedSnapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        resolvedSnapshot.alpha = 1
        addSubview(resolvedSnapshot)
        self.lastFrameSnapshotView = resolvedSnapshot
        self.transitionOldPlayer = targetPlayer
        self.transitionOldItem = preferredItem ?? targetPlayer?.currentItem
        self.isAwaitingTransitionFrame = true
        scheduleTransitionFallback()
    }

    public func removeLastFrameSnapshot() {
        clearTransitionSnapshot(animated: false)
    }

    public func clearTransitionSnapshot(animated: Bool = false) {
        transitionFallbackWorkItem?.cancel()
        transitionFallbackWorkItem = nil
        isAwaitingTransitionFrame = false
        transitionOldPlayer = nil
        transitionOldItem = nil
        guard let snapshot = lastFrameSnapshotView else { return }
        self.lastFrameSnapshotView = nil
        if animated {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                snapshot.alpha = 0
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        } else {
            snapshot.layer.removeAllAnimations()
            snapshot.removeFromSuperview()
        }
    }

    public func cleanup() {
        stopBufferMonitor()
        if managesPlayback { player?.pause() }
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        [statusObserver, itemStatusObserver, currentItemObserver, readyForDisplayObserver].forEach { $0?.invalidate() }
        playerLayer?.player = nil; bgPlayerLayer?.player = nil
        clearTransitionSnapshot(animated: false)
    }

    deinit {
        stopBufferMonitor()
        transitionFallbackWorkItem?.cancel()
        [statusObserver, itemStatusObserver, currentItemObserver, readyForDisplayObserver].forEach { $0?.invalidate() }
        if let token = timeObserver { player?.removeTimeObserver(token) }
        NotificationCenter.default.removeObserver(self)
    }
}
