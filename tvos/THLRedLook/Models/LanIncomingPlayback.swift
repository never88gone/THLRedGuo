import Foundation

public struct LanIncomingPlayback: Hashable, Codable {
    public let drama: Drama
    public let episodeIndex: Int
    public let position: Double
    public let senderName: String

    public init(drama: Drama, episodeIndex: Int, position: Double, senderName: String) {
        self.drama = drama
        self.episodeIndex = episodeIndex
        self.position = position
        self.senderName = senderName
    }
}
