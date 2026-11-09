import Foundation

public struct SeriesSeason: Decodable {
    public let drama: Drama
    public let season: Int
    public let playable: Bool
    public let status: String

    public init(drama: Drama, season: Int, playable: Bool, status: String) {
        self.drama = drama
        self.season = season
        self.playable = playable
        self.status = status
    }
}
