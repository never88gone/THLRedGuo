import Foundation

struct HongguoCollectionPage<Item> {
    let items: [Item]
    let hasMore: Bool
    let nextOffset: Int?
    var douyinOffset = 0
    var unsupportedCount = 0
}
