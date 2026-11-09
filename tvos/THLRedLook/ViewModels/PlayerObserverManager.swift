import Foundation
import AVFoundation
import UIKit

@MainActor
final class PlayerObserverManager {
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var bufferingDebounceTimer: Timer?
    private var initializationTimer: Timer?
    private var itemNotifications: [NSObjectProtocol] = []

    func attach(
        to av: AVPlayer,
        item: AVPlayerItem,
        seekTo: Double,
        playbackRate: Float,
        isFeedMode: Bool,
        onPlayingChanged: @escaping (Bool) -> Void,
        onBufferingChanged: @escaping (Bool) -> Void,
        onReadyToPlay: @escaping (Double, Int) -> Void,
        onTimeUpdated: @escaping (Double) -> Void,
        onItemEnded: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        release()

        timeControlObserver = av.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak av] _, _ in
            Task { @MainActor in
                guard let self, let av else { return }
                let playing = av.timeControlStatus == .playing
                let waiting = av.timeControlStatus == .waitingToPlayAtSpecifiedRate
                onPlayingChanged(playing)
                if playing {
                    self.bufferingDebounceTimer?.invalidate()
                    self.bufferingDebounceTimer = nil
                    onBufferingChanged(false)
                } else if waiting {
                    if self.bufferingDebounceTimer == nil {
                        self.bufferingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                            Task { @MainActor in
                                if av.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                                    onBufferingChanged(true)
                                }
                            }
                        }
                    }
                } else {
                    self.bufferingDebounceTimer?.invalidate()
                    self.bufferingDebounceTimer = nil
                    onBufferingChanged(false)
                }
            }
        }

        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak av] observed, _ in
            Task { @MainActor in
                guard let self, let av else { return }
                switch observed.status {
                case .readyToPlay:
                    self.initializationTimer?.invalidate()
                    self.initializationTimer = nil
                    let seconds = observed.duration.seconds
                    let dur = (seconds.isFinite && seconds > 0) ? seconds : 0
                    let size = observed.presentationSize
                    let quality = Int(min(size.width, size.height))
                    if seekTo > 0.5, dur > 0 {
                        let pos = min(seekTo, max(0, dur - 1))
                        await av.seek(to: CMTime(seconds: pos, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                    onReadyToPlay(dur, quality)
                case .failed:
                    onError(observed.error ?? NSError(domain: "AVPlayer", code: -1))
                default:
                    break
                }
            }
        }

        timeObserverToken = av.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            Task { @MainActor in
                let sec = CMTimeGetSeconds(time)
                if sec.isFinite && sec >= 0 {
                    onTimeUpdated(sec)
                }
            }
        }

        let center = NotificationCenter.default
        itemNotifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in onItemEnded() }
        })

        let timeout = isFeedMode ? 10.0 : 30.0
        initializationTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            Task { @MainActor in
                if item.status != .readyToPlay {
                    onError(NSError(domain: "Player", code: -1001, userInfo: [NSLocalizedDescriptionKey: "视频初始化超时"]))
                }
            }
        }
    }

    func release() {
        initializationTimer?.invalidate()
        initializationTimer = nil
        bufferingDebounceTimer?.invalidate()
        bufferingDebounceTimer = nil
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        itemNotifications.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotifications.removeAll()
        timeObserverToken = nil
    }
}
