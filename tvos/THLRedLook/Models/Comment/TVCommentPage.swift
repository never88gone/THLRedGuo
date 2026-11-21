import Foundation

public struct TVCommentPage: Equatable {
    public let total: Int
    public let hasMore: Bool
    public let cursor: String
    public let list: [TVCommentItem]

    public init(total: Int, hasMore: Bool, cursor: String, list: [TVCommentItem]) {
        self.total = total
        self.hasMore = hasMore
        self.cursor = cursor
        self.list = list
    }

    public init(json: [String: Any]) {
        self.total = json["total"] as? Int ?? 0
        self.hasMore = json["hasMore"] as? Bool ?? false
        self.cursor = json["cursor"] as? String ?? ""
        let rawList = json["list"] as? [[String: Any]] ?? []
        self.list = rawList.compactMap { TVCommentItem(json: $0) }
    }
}
