import Foundation

public struct TVPictureInPictureSession: Equatable {
    public let drama: Drama
    public var episodeIndex: Int
    public let allEpisodes: [Episode]
    public var currentPosition: Double
    public var playbackPlan: PlaybackPlan?

    public init(
        drama: Drama,
        episodeIndex: Int,
        allEpisodes: [Episode],
        currentPosition: Double,
        playbackPlan: PlaybackPlan? = nil
    ) {
        self.drama = drama
        self.episodeIndex = episodeIndex
        self.allEpisodes = allEpisodes
        self.currentPosition = currentPosition
        self.playbackPlan = playbackPlan
    }
}
