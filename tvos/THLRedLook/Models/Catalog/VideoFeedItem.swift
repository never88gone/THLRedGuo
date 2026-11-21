import Foundation

public struct VideoFeedItem: Decodable, Identifiable {
    public let drama: Drama
    public let episode: Int
    public let position: Double
    public var id: String { drama.id }

    public init(drama: Drama, episode: Int, position: Double) {
        self.drama = drama
        self.episode = episode
        self.position = position
    }
}
