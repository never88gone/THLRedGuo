import Foundation
import AVFoundation
import UIKit

@MainActor
final class PlayerObserverManager {
    private weak var player: AVPlayer?
    private var generation = 0
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var initializationTimer: Timer?
    private var healthTimer: Timer?
    private var itemNotifications: [NSObjectProtocol] = []

    func attach(
        to av: AVPlayer,
        item: AVPlayerItem,
        seekTo: Double,
        playbackRate: Float,
        isFeedMode: Bool,
        shouldPlay: @escaping () -> Bool = { true },
        onPlayingChanged: @escaping (Bool) -> Void,
        onBufferingChanged: @escaping (Bool) -> Void,
        onReadyToPlay: @escaping (Double, Int) -> Void,
        onTimeUpdated: @escaping (Double) -> Void,
        onItemEnded: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        release()
        player = av
        let epoch = generation
        let current: () -> Bool = { [weak self, weak av, weak item] in
            guard let self, let av, let item else { return false }
            return self.generation == epoch && self.player === av && av.currentItem === item
        }
        var ready = false
        var preparing = false
        var ended = false
        var lastPosition = seekTo
        var lastAdvance = Date()

        timeControlObserver = av.observe(\.timeControlStatus, options: [.initial, .new]) { [weak av] _, _ in
            Task { @MainActor in
                guard current(), let av else { return }
                onPlayingChanged(av.timeControlStatus == .playing)
                onBufferingChanged(av.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            }
        }
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak av] observed, _ in
            Task { @MainActor in
                guard current(), let self, let av else { return }
                switch observed.status {
                case .readyToPlay:
                    guard !preparing else { return }
                    preparing = true
                    self.initializationTimer?.invalidate()
                    let seconds = observed.duration.seconds
                    let duration = seconds.isFinite && seconds > 0 ? seconds : 0
                    let size = min(observed.presentationSize.width, observed.presentationSize.height)
                    if seekTo > 0.5, duration > 0 {
                        let position = min(seekTo, max(0, duration - 1))
                        await av.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        guard current() else { return }
                    }
                    lastPosition = av.currentTime().seconds
                    lastAdvance = Date()
                    ready = true
                    onReadyToPlay(duration, size.isFinite && size > 0 ? Int(size) : 0)
                case .failed:
                    onError(observed.error ?? NSError(domain: "AVPlayer", code: -1))
                default: break
                }
            }
        }
        timeObserverToken = av.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak av] _ in
            Task { @MainActor in
                guard current(), let av, ready else { return }
                let seconds = av.currentTime().seconds
                guard seconds.isFinite && seconds >= 0 else { return }
                if abs(seconds - lastPosition) > 0.05 { lastAdvance = Date(); lastPosition = seconds }
                onTimeUpdated(seconds)
            }
        }
        let center = NotificationCenter.default
        itemNotifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in
                guard current(), !ended else { return }
                ended = true
                onItemEnded()
            }
        })
        for name in [NSNotification.Name.AVPlayerItemFailedToPlayToEndTime, .encryptedPlaybackFailed] {
            let target: Any = name == .encryptedPlaybackFailed ? item.asset : item
            itemNotifications.append(center.addObserver(forName: name, object: target, queue: .main) { notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    ?? notification.userInfo?[NSUnderlyingErrorKey] as? Error
                    ?? NSError(domain: "Player", code: -1, userInfo: [NSLocalizedDescriptionKey: "视频读取中断"])
                Task { @MainActor in
                    guard current(), !ended else { return }
                    onError(error)
                }
            })
        }
        initializationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            Task { @MainActor in
                guard current(), !ready else { return }
                onError(NSError(domain: "Player", code: -1001, userInfo: [NSLocalizedDescriptionKey: "视频初始化超时"]))
            }
        }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                guard current(), ready, !ended else { return }
                guard shouldPlay() else { lastAdvance = Date(); return }
                if Date().timeIntervalSince(lastAdvance) >= 15 {
                    lastAdvance = Date()
                    onError(NSError(domain: "Player", code: -1001, userInfo: [NSLocalizedDescriptionKey: "视频持续缓冲，正在恢复"]))
                }
            }
        }
    }

    func release() {
        generation += 1
        initializationTimer?.invalidate(); initializationTimer = nil
        healthTimer?.invalidate(); healthTimer = nil
        statusObserver?.invalidate(); statusObserver = nil
        timeControlObserver?.invalidate(); timeControlObserver = nil
        itemNotifications.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotifications.removeAll()
        if let token = timeObserverToken { player?.removeTimeObserver(token) }
        timeObserverToken = nil
        player = nil
    }
}
