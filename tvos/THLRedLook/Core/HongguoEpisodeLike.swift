import Foundation

struct HongguoEpisodeLike {
    let id: String
    let number: Int
    let liked: Bool
    let count: Int
    init?(_ row: [String: Any]) {
        guard let id = row["id"] as? String, let number = row["number"] as? Int, let liked = row["liked"] as? Bool else { return nil }
        self.id = id; self.number = number; self.liked = liked; self.count = row["count"] as? Int ?? 0
    }
}
