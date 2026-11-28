import Foundation
import AVFoundation

struct PreloadedEpisode {
    let episodeIndex: Int
    let dramaId: String
    let requestedQuality: Int
    let playbackRate: Float
    let plan: PlaybackPlan
    let playerItem: AVPlayerItem
    let player: AVPlayer?
    let decryptedURL: URL?

    init(
        episodeIndex: Int,
        dramaId: String = "",
        requestedQuality: Int = 0,
        playbackRate: Float = 1.0,
        plan: PlaybackPlan,
        playerItem: AVPlayerItem,
        player: AVPlayer? = nil,
        decryptedURL: URL? = nil
    ) {
        self.episodeIndex = episodeIndex
        self.dramaId = dramaId
        self.requestedQuality = requestedQuality
        self.playbackRate = playbackRate
        self.plan = plan
        self.playerItem = playerItem
        self.player = player
        self.decryptedURL = decryptedURL
    }
}

extension AVPlayerItem {
    func bufferedSecondsAhead(from time: CMTime? = nil) -> Double {
        let current = (time ?? currentTime()).seconds
        let anchor = current.isFinite && current >= 0 ? current : 0
        var best = 0.0
        for value in loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = start + range.duration.seconds
            if start.isFinite && end.isFinite && anchor >= start - 0.1 && end > anchor {
                best = max(best, end - anchor)
            }
        }
        return best
    }
}
