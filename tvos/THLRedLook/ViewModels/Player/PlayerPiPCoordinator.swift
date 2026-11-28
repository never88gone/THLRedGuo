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

    func checkRestorePiP(dramaId: String) -> (player: AVPlayer, episode: Int, position: Double, plan: PlaybackPlan?, hasRestoreHandler: Bool)? {
        guard (isPiPActive || isStartingPiP),
              let activePipPlayer = TVPictureInPictureCoordinator.shared.activePlayer,
              let session = TVPictureInPictureCoordinator.shared.currentSession,
              session.drama.id == dramaId else { return nil }

        let currentSeconds = CMTimeGetSeconds(activePipPlayer.currentTime())
        let position = (currentSeconds.isFinite && currentSeconds >= 0) ? currentSeconds : session.currentPosition
        let hasHandler = TVPictureInPictureCoordinator.shared.hasRestoreCompletionHandler
        TVPictureInPictureCoordinator.shared.beginRestoreTransfer()
        if !hasHandler {
            TVPictureInPictureCoordinator.shared.stopPictureInPicture(preservePlayerForRestore: true)
        }
        return (activePipPlayer, session.episodeIndex, position, session.playbackPlan, hasHandler)
    }

    func stopCompetingPiPIfNeeded(forDramaId dramaId: String, activePlayerCandidate: AVPlayer? = nil) {
        TVPictureInPictureCoordinator.shared.stopIfActiveForDifferentPlayback(
            dramaId: dramaId,
            activePlayerCandidate: activePlayerCandidate
        )
    }

    func unregister() {
        TVPictureInPictureCoordinator.shared.unregisterPlaybackContext()
    }
}
