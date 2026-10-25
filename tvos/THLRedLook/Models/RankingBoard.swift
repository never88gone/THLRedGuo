import Foundation

public struct RankedDrama: Decodable {
    public let rank: Int
    public let drama: Drama
    public let metric: String

    public init(rank: Int, drama: Drama, metric: String = "") {
        self.rank = rank
        self.drama = drama
        self.metric = metric
    }
}

public struct DiscoveryPage<Item> {
    public let items: [Item]
    public let page: Int
    public let hasMore: Bool
}

public struct RankingBoard: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let source: String

    public init(id: String, name: String, description: String, source: String = "hongguo") {
        self.id = id
        self.name = name
        self.description = description
        self.source = source
    }

    /// 判断榜单是否属于指定的数据源（严格过滤异构数据源类型）
    public func matches(source: String) -> Bool {
        let target = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return false }
        let currentBoardSource = self.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let currentBoardId = self.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if currentBoardSource == target {
            return true
        }
        if currentBoardId.hasPrefix("\(target)-") || currentBoardId.hasPrefix("\(target)_") {
            return true
        }
        return false
    }

    public var isAllowedOnTV: Bool {
        source.lowercased() == "hongguo" || id.lowercased().hasPrefix("hongguo")
    }

    /// 过滤出适宜在 tvOS 呈现的榜单列表
    public static func filterForTV(_ boards: [RankingBoard]) -> [RankingBoard] {
        boards.filter { $0.isAllowedOnTV }
    }
}

public struct DanmakuItem: Identifiable, Hashable, Codable {
    public let id: String
    public let text: String
    public let timeMs: Int64
    public let color: String

    public init(id: String = UUID().uuidString, text: String, timeMs: Int64, color: String = "#FFFFFF") {
        self.id = id
        self.text = text
        self.timeMs = timeMs
        self.color = color
    }
}
