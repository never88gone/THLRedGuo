import Foundation
import AVFoundation

public struct PreparedPlaybackResult {
    public let plan: PlaybackPlan
    public let playerItem: AVPlayerItem
    public let decryptedURL: URL?

    public init(plan: PlaybackPlan, playerItem: AVPlayerItem, decryptedURL: URL?) {
        self.plan = plan
        self.playerItem = playerItem
        self.decryptedURL = decryptedURL
    }
}
