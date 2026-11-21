import Foundation

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
