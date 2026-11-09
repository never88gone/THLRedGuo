import Foundation

public struct VideoFeedPage: Decodable {
    public let items: [VideoFeedItem]
    public let page: Int
    public let hasMore: Bool

    public init(items: [VideoFeedItem], page: Int, hasMore: Bool) {
        self.items = items
        self.page = page
        self.hasMore = hasMore
    }
}
