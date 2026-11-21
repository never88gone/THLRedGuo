import Foundation

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
