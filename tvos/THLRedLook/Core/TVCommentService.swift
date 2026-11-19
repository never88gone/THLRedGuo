import Foundation

public final class TVCommentService {
    public static let shared = TVCommentService()
    private let session = URLSession(configuration: .default)

    private init() {}

    public func fetchCommentList(bookId: String, cursor: String = "", count: Int = 20) async throws -> TVCommentPage {
        let cleanId = bookId.replacingOccurrences(of: "hongguo:", with: "")
        let payload: [String: String] = [
            "bookId": cleanId,
            "cursor": cursor,
            "count": String(count)
        ]
        let command = try await NativeBridge.shared.accountRequest("commentList", payload: payload)
        guard let urlStr = command["url"] as? String, let url = URL(string: urlStr) else {
            throw HongguoAccountError.invalid
        }
        var request = URLRequest(url: url)
        request.httpMethod = command["method"] as? String ?? "POST"
        if let headers = command["headers"] as? [String: String] {
            for (key, val) in headers {
                request.setValue(val, forHTTPHeaderField: key)
            }
        }
        if let bodyStr = command["body"] as? String {
            request.httpBody = bodyStr.data(using: .utf8)
        }

        let (data, _) = try await session.data(for: request)
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        let parsed = try await NativeBridge.shared.accountParse("commentList", body: bodyText)
        return TVCommentPage(json: parsed)
    }

    public func fetchCommentReplyList(commentId: String, bookId: String, cursor: String = "", count: Int = 20) async throws -> TVCommentReplyPage {
        let cleanId = bookId.replacingOccurrences(of: "hongguo:", with: "")
        let payload: [String: String] = [
            "commentId": commentId,
            "bookId": cleanId,
            "cursor": cursor,
            "count": String(count)
        ]
        let command = try await NativeBridge.shared.accountRequest("commentReplyList", payload: payload)
        guard let urlStr = command["url"] as? String, let url = URL(string: urlStr) else {
            throw HongguoAccountError.invalid
        }
        var request = URLRequest(url: url)
        request.httpMethod = command["method"] as? String ?? "POST"
        if let headers = command["headers"] as? [String: String] {
            for (key, val) in headers {
                request.setValue(val, forHTTPHeaderField: key)
            }
        }
        if let bodyStr = command["body"] as? String {
            request.httpBody = bodyStr.data(using: .utf8)
        }

        let (data, _) = try await session.data(for: request)
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        let parsed = try await NativeBridge.shared.accountParse("commentReplyList", body: bodyText)
        return TVCommentReplyPage(json: parsed)
    }
}
