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
