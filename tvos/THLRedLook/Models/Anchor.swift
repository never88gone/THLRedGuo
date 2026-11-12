import Foundation

public struct Anchor: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let avatar: String
    public let intro: String
    public let followerCount: Int?
    public let worksCount: Int?
    public let dramas: [Drama]
    public let following: Bool?
    public let canFollow: Bool?
    public let relativeType: Int?

    public init(id: String, name: String, avatar: String = "", intro: String = "",
                followerCount: Int? = nil, worksCount: Int? = nil, dramas: [Drama] = [],
                following: Bool? = nil, canFollow: Bool? = nil, relativeType: Int? = nil) {
        self.id = id; self.name = name; self.avatar = avatar; self.intro = intro
        self.followerCount = followerCount; self.worksCount = worksCount; self.dramas = dramas
        self.following = following; self.canFollow = canFollow; self.relativeType = relativeType
    }

    init?(official row: [String: Any], dramas: [Drama] = []) {
        guard let id = row["id"] as? String, !id.isEmpty, let name = row["name"] as? String else { return nil }
        self.init(id: id, name: name, avatar: row["avatar"] as? String ?? "", intro: row["description"] as? String ?? "",
                  worksCount: row["worksCount"] as? Int, dramas: dramas, following: row["following"] as? Bool,
                  canFollow: row["canFollow"] as? Bool, relativeType: row["relativeType"] as? Int)
    }

    public var displayFollowerCount: String {
        guard let count = followerCount else { return "" }
        return count >= 10000 ? String(format: "%.1f万", Double(count) / 10000) : String(count)
    }
}

struct HongguoCollectionPage<Item> {
    let items: [Item]
    let hasMore: Bool
    let nextOffset: Int?
    var douyinOffset = 0
    var unsupportedCount = 0
}

struct HongguoLikedVideo: Identifiable {
    let id: String
    let drama: Drama?
    let title: String
    let subtitle: String

    init?(row: [String: Any]) {
        guard let rawID = row["id"] as? String, let kind = row["kind"] as? String else { return nil }
        id = "\(kind):\(rawID)"
        title = row["title"] as? String ?? "点赞视频"
        subtitle = kind == "series" ? "已点赞合集" : (row["episode"] as? Int).map { "已点赞 · 第 \($0) 集" } ?? "已点赞视频"
        if let series = row["seriesId"] as? String, series.range(of: "^[1-9][0-9]{0,29}$", options: .regularExpression) != nil {
            drama = Drama(id: "hongguo:\(series)", sourceId: series, title: title,
                          description: row["description"] as? String ?? "", cover: row["cover"] as? String ?? "", episodes: row["episodes"] as? Int ?? 0)
        } else { drama = nil }
    }
}
