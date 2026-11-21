import Foundation

/// 用户点赞视频记录模型
public struct UserLikeRecord: Identifiable, Hashable, Codable {
    public var id: String { "\(dramaId)_\(episode)" }
    public let dramaId: String
    public let episode: Int
    public let title: String
    public let cover: String
    public let drama: Drama
    public let likedAt: Date

    public init(drama: Drama, episode: Int = 1, likedAt: Date = Date()) {
        self.dramaId = drama.id
        self.episode = episode
        self.title = drama.title
        self.cover = drama.cover
        self.drama = drama
        self.likedAt = likedAt
    }
}
