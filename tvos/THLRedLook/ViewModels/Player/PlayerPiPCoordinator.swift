import Foundation
import AVKit

@MainActor
final class PlayerPiPCoordinator {
    weak var pipController: AVPictureInPictureController?

    var isSupported: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return AVPictureInPictureController.isPictureInPictureSupported()
        #endif
    }

    var isPiPActive: Bool {
        TVPictureInPictureCoordinator.shared.isPictureInPictureActive
    }

    var isStartingPiP: Bool {
        TVPictureInPictureCoordinator.shared.isStartingPiP
    }

    func register(
        player: AVPlayer?,
        drama: Drama,
        currentEpisodeIndex: Int,
        allEpisodes: [Episode],
        currentTime: Double,
        plan: PlaybackPlan?
    ) {
        if let controller = pipController, let p = player {
            TVPictureInPictureCoordinator.shared.register(
                controller: controller,
                player: p,
                drama: drama,
                currentEpisodeIndex: currentEpisodeIndex,
                allEpisodes: allEpisodes,
                initialPosition: currentTime,
                playbackPlan: plan
            )
        }
    }

    func checkRestorePiP(dramaId: String) -> (player: AVPlayer, episode: Int, position: Double, plan: PlaybackPlan?)? {
        guard isPiPActive,
              let activePipPlayer = TVPictureInPictureCoordinator.shared.activePlayer,
              let session = TVPictureInPictureCoordinator.shared.currentSession,
              session.drama.id == dramaId else { return nil }

        let currentSeconds = CMTimeGetSeconds(activePipPlayer.currentTime())
        let position = (currentSeconds.isFinite && currentSeconds >= 0) ? currentSeconds : session.currentPosition
        TVPictureInPictureCoordinator.shared.stopPictureInPicture()
        TVPictureInPictureCoordinator.shared.completeRestore(success: true)
        return (activePipPlayer, session.episodeIndex, position, session.playbackPlan)
    }

    func unregister() {
        TVPictureInPictureCoordinator.shared.unregisterPlaybackContext()
    }
}
