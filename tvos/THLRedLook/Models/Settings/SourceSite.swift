import Foundation

public struct SourceSite: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let description: String

    public init(id: String, name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }

    public var onlineSearch: Bool {
        id == "hongguo" || pagedSearch
    }

    public var pagedSearch: Bool {
        false
    }

    public var searchSuggestions: Bool {
        id == "hongguo"
    }

    public var groupId: String {
        "hongguo"
    }

    public var groupName: String {
        "精选短剧"
    }

    public var entryName: String {
        name
    }

    public static let hongguo = SourceSite(id: "hongguo", name: "官方免费短剧", description: "短剧 · 漫剧 · AI 剧")

    /// 检查是否为 tvOS 支持的站源（仅支持官方规范源）
    public static func isAdultOrProhibitedOnTV(_ id: String) -> Bool {
        id.lowercased() != "hongguo"
    }

    /// 默认公开站源：tvOS 仅支持官方免费短剧
    public static let primaryValues: [SourceSite] = [
        hongguo
    ]

    /// 敏感站源：tvOS 彻底禁用且无其它敏感源
    public static let restrictedValues: [SourceSite] = []

    public static let allValues: [SourceSite] = [hongguo]

    public static func isPrimary(_ id: String) -> Bool {
        id == "hongguo"
    }

    public static func isRestricted(_ id: String) -> Bool {
        false
    }

    public static func visibleValues(unlocked: Bool) -> [SourceSite] {
        [hongguo]
    }

    public static func byId(_ id: String) -> SourceSite {
        hongguo
    }
}
