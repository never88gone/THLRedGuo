import Foundation

public struct Episode: Identifiable, Hashable, Codable {
    public let id: String
    public let title: String
    public let number: Int
    public let vip: Bool
    public let raw: Data?

    public init(id: String, title: String, number: Int, vip: Bool = false, raw: Data? = nil) {
        self.id = id
        self.title = title
        self.number = number
        self.vip = vip
        self.raw = raw
    }

    public var rawChapter: [String: Any]? {
        guard let raw else { return nil }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    public var displayTitle: String {
        title.isEmpty ? "第 \(number) 集" : title
    }
}

public struct DramaDetail: Identifiable, Hashable {
    public var id: String { drama.id }
    public let drama: Drama
    public let episodes: [Episode]
    public let warning: String

    public init(drama: Drama, episodes: [Episode], warning: String = "") {
        self.drama = drama
        self.episodes = episodes
        self.warning = warning
    }

    /// 以 50 集为一组分段管理，适配电视遥控器快速换段
    public var episodeChunks: [EpisodeChunk] {
        let chunkSize = 50
        guard !episodes.isEmpty else { return [] }
        var chunks = [EpisodeChunk]()
        let total = episodes.count
        var start = 0
        while start < total {
            let end = min(start + chunkSize, total)
            let slice = Array(episodes[start..<end])
            let firstNum = slice.first?.number ?? (start + 1)
            let lastNum = slice.last?.number ?? end
            let title = "\(firstNum)-\(lastNum)"
            chunks.append(EpisodeChunk(title: title, range: start..<end, episodes: slice))
            start += chunkSize
        }
        return chunks
    }
}

public struct EpisodeChunk: Identifiable, Hashable {
    public var id: String { title }
    public let title: String
    public let range: Range<Int>
    public let episodes: [Episode]
}
