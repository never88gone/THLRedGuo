import Foundation
import MediaPlayer
import AVFoundation

@MainActor
final class PlayerRemoteCommandCoordinator {
    private var remoteCommandTargets: [Any] = []
    private static let audioSessionQueue = DispatchQueue(label: "THLRedLook.AudioSession")

    func setup(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onToggle: @escaping () -> Void
    ) {
        teardown()
        let commandCenter = MPRemoteCommandCenter.shared()

        let playTarget = commandCenter.playCommand.addTarget { _ in
            NSLog("🎬 [MPRemoteCommandCenter] 收到系统 playCommand")
            Task { @MainActor in onPlay() }
            return .success
        }
        remoteCommandTargets.append((commandCenter.playCommand, playTarget))

        let pauseTarget = commandCenter.pauseCommand.addTarget { _ in
            NSLog("🎬 [MPRemoteCommandCenter] 收到系统 pauseCommand")
            Task { @MainActor in onPause() }
            return .success
        }
        remoteCommandTargets.append((commandCenter.pauseCommand, pauseTarget))

        let toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { _ in
            NSLog("🎬 [MPRemoteCommandCenter] 收到系统 togglePlayPauseCommand")
            Task { @MainActor in onToggle() }
            return .success
        }
        remoteCommandTargets.append((commandCenter.togglePlayPauseCommand, toggleTarget))

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
    }

    func teardown() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        remoteCommandTargets.removeAll()
    }

    func configureAudioSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.audioSessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .moviePlayback)
                    try session.setActive(true)
                } catch {}
                continuation.resume()
            }
        }
    }
}
