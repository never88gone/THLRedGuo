import Foundation

/// 主播 / 创作者实体模型
public struct Anchor: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let avatar: String
    public let intro: String
    public let followerCount: Int
    public let worksCount: Int
    public let dramas: [Drama]

    public init(
        id: String,
        name: String,
        avatar: String = "",
        intro: String = "知名短剧创作者，主演多部热门短剧。",
        followerCount: Int = 12800,
        worksCount: Int = 1,
        dramas: [Drama] = []
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.intro = intro
        self.followerCount = followerCount
        self.worksCount = max(worksCount, dramas.count)
        self.dramas = dramas
    }

    public var displayFollowerCount: String {
        if followerCount >= 10000 {
            let val = Double(followerCount) / 10000.0
            return String(format: "%.1f万", val)
        }
        return "\(followerCount)"
    }
}
