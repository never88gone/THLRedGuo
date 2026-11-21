import Foundation

public struct SeasonItem: Identifiable, Hashable {
    public var id: String { drama.id }
    public let drama: Drama
    public let seasonNumber: Int
    public let title: String
    public let isCurrent: Bool
    public let playable: Bool

    public init(drama: Drama, seasonNumber: Int, title: String, isCurrent: Bool, playable: Bool = true) {
        self.drama = drama
        self.seasonNumber = seasonNumber
        self.title = title
        self.isCurrent = isCurrent
        self.playable = playable
    }
}
