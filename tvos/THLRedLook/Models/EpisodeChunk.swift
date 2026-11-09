import Foundation

public struct EpisodeChunk: Identifiable, Hashable {
    public var id: String { title }
    public let title: String
    public let range: Range<Int>
    public let episodes: [Episode]

    public init(title: String, range: Range<Int>, episodes: [Episode]) {
        self.title = title
        self.range = range
        self.episodes = episodes
    }
}
