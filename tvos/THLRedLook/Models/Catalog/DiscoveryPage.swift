import Foundation

public struct DiscoveryPage<Item> {
    public let items: [Item]
    public let page: Int
    public let hasMore: Bool

    public init(items: [Item], page: Int, hasMore: Bool) {
        self.items = items
        self.page = page
        self.hasMore = hasMore
    }
}
