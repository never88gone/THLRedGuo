import Foundation

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

    public static let defaults: [RankingBoard] = [
        RankingBoard(id: "hongguo-hot", name: "总热播榜", description: "当下最受欢迎的短剧热播排行", source: "hongguo"),
        RankingBoard(id: "hongguo-real", name: "真人剧榜", description: "高口碑真人短剧热门排行", source: "hongguo"),
        RankingBoard(id: "hongguo-comic", name: "漫剧榜", description: "精彩动态漫剧精选排行", source: "hongguo"),
        RankingBoard(id: "hongguo-ai", name: "AI剧榜", description: "前沿生成式 AI 剧情剧集排行", source: "hongguo")
    ]

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

    /// 获取特定数据源的专属默认/兜底榜单（未配置数据源时返回空列表）
    public static func defaults(for source: String) -> [RankingBoard] {
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanSource.isEmpty || cleanSource == "hongguo" else { return [] }
        return defaults
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
