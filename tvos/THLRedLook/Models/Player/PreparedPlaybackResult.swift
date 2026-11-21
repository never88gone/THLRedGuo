import Foundation
import AVFoundation

public struct PreparedPlaybackResult {
    public let plan: PlaybackPlan
    public let playerItem: AVPlayerItem
    public let decryptedURL: URL?
    public let drama: Drama?
    public let episodes: [Episode]?

    public init(plan: PlaybackPlan, playerItem: AVPlayerItem, decryptedURL: URL?, drama: Drama? = nil, episodes: [Episode]? = nil) {
        self.plan = plan
        self.playerItem = playerItem
        self.decryptedURL = decryptedURL
        self.drama = drama
        self.episodes = episodes
    }
}
