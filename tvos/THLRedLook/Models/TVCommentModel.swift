import Foundation

public struct TVCommentItem: Identifiable, Equatable {
    public let id: String
    public let text: String
    public let userName: String
    public let userAvatar: String
    public let userId: String
    public let createTime: Int
    public let diggCount: Int
    public let replyCount: Int

    public init(
        id: String,
        text: String,
        userName: String,
        userAvatar: String,
        userId: String,
        createTime: Int,
        diggCount: Int,
        replyCount: Int
    ) {
        self.id = id
        self.text = text
        self.userName = userName
        self.userAvatar = userAvatar
        self.userId = userId
        self.createTime = createTime
        self.diggCount = diggCount
        self.replyCount = replyCount
    }

    public init?(json: [String: Any]) {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        self.text = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.userName = json["userName"] as? String ?? "红果用户"
        self.userAvatar = json["userAvatar"] as? String ?? ""
        self.userId = json["userId"] as? String ?? ""
        self.createTime = json["createTime"] as? Int ?? 0
        self.diggCount = json["diggCount"] as? Int ?? 0
        self.replyCount = json["replyCount"] as? Int ?? 0
    }
}

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

public struct TVCommentReplyItem: Identifiable, Equatable {
    public let id: String
    public let text: String
    public let userName: String
    public let userAvatar: String
    public let userId: String
    public let replyToUserName: String
    public let createTime: Int
    public let diggCount: Int

    public init(
        id: String,
        text: String,
        userName: String,
        userAvatar: String,
        userId: String,
        replyToUserName: String,
        createTime: Int,
        diggCount: Int
    ) {
        self.id = id
        self.text = text
        self.userName = userName
        self.userAvatar = userAvatar
        self.userId = userId
        self.replyToUserName = replyToUserName
        self.createTime = createTime
        self.diggCount = diggCount
    }

    public init?(json: [String: Any]) {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        self.text = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.userName = json["userName"] as? String ?? "红果用户"
        self.userAvatar = json["userAvatar"] as? String ?? ""
        self.userId = json["userId"] as? String ?? ""
        self.replyToUserName = json["replyToUserName"] as? String ?? ""
        self.createTime = json["createTime"] as? Int ?? 0
        self.diggCount = json["diggCount"] as? Int ?? 0
    }
}

public struct TVCommentReplyPage: Equatable {
    public let total: Int
    public let hasMore: Bool
    public let cursor: String
    public let list: [TVCommentReplyItem]

    public init(total: Int, hasMore: Bool, cursor: String, list: [TVCommentReplyItem]) {
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
        self.list = rawList.compactMap { TVCommentReplyItem(json: $0) }
    }
}
