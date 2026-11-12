import Foundation
import AVFoundation

/// 播放器进度 Seek 协调器
@MainActor
final class PlayerSeekCoordinator {
    private var seekSequence: Int = 0
    private(set) var isSeeking: Bool = false

    init() {}

    func seek(
        to target: Double,
        player: AVPlayer?,
        duration: Double,
        generation: Int,
        onStart: (Double) -> Void,
        onComplete: @escaping (Int, Int) -> Void
    ) {
        guard let p = player, p.currentItem?.status == .readyToPlay, duration > 0 else { return }
        seekSequence += 1
        let sequence = seekSequence
        isSeeking = true
        let clampedTarget = max(0, min(target, duration))
        onStart(clampedTarget)

        p.seek(to: CMTime(seconds: clampedTarget, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, sequence == self.seekSequence else { return }
                self.isSeeking = false
                onComplete(generation, sequence)
            }
        }
    }

    func cancel() {
        seekSequence += 1
        isSeeking = false
    }
}
