import Foundation

struct HongguoCreator: Identifiable {
    let id: String
    let name: String
    let relativeType: Int
    let following: Bool?
    let canFollow: Bool
    init?(_ row: [String: Any]) {
        guard let id = row["id"] as? String, let name = row["name"] as? String, let type = row["relativeType"] as? Int else { return nil }
        self.id = id; self.name = name; self.relativeType = type
        self.following = row["following"] as? Bool; self.canFollow = row["canFollow"] as? Bool == true
    }
}
