import Foundation
import AVFoundation

struct PreloadedEpisode {
    let episodeIndex: Int
    let plan: PlaybackPlan
    let playerItem: AVPlayerItem
    let decryptedURL: URL?
}
