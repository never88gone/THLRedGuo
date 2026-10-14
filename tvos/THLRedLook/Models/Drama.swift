import Foundation

public struct Drama: Identifiable, Hashable, Codable {
    public let id: String
    public let source: String
    public let sourceId: String
    public let title: String
    public let description: String
    public let cover: String
    public let episodes: Int
    public let category: String
    public let vip: Bool?
    public let heat: String
    public let views: String
    public let onlineDate: String
    public let tags: [String]
    public let releaseStatus: String

    public init(
        id: String,
        source: String = "hongguo",
        sourceId: String = "",
        title: String,
        description: String = "",
        cover: String = "",
        episodes: Int = 0,
        category: String = "",
        vip: Bool? = nil,
        heat: String = "",
        views: String = "",
        onlineDate: String = "",
        tags: [String] = [],
        releaseStatus: String = ""
    ) {
        self.id = id
        self.source = source
        self.sourceId = sourceId
        self.title = title
        self.description = description
        self.cover = cover
        self.episodes = episodes
        self.category = category
        self.vip = vip
        self.heat = heat
        self.views = views
        self.onlineDate = onlineDate
        self.tags = tags
        self.releaseStatus = releaseStatus
    }

    public var isVIP: Bool {
        vip == true
    }

    public var releaseLabel: String {
        switch releaseStatus.lowercased() {
        case "finished", "completed":
            return "已完结"
        case "ongoing":
            return "连载中"
        default:
            return episodes > 0 ? "共 \(episodes) 集" : "全集"
        }
    }

    public var displaySubtitle: String {
        if !heat.isEmpty {
            return "🔥 \(heat)"
        }
        if !views.isEmpty {
            return "👁 \(views)"
        }
        return releaseLabel
    }

    public func merge(with fresh: Drama) -> Drama {
        guard id == fresh.id else { return fresh }
        return Drama(
            id: id,
            source: fresh.source.isEmpty ? source : fresh.source,
            sourceId: fresh.sourceId.isEmpty ? sourceId : fresh.sourceId,
            title: (fresh.title.isEmpty || fresh.title == "短剧") ? title : fresh.title,
            description: fresh.description.isEmpty ? description : fresh.description,
            cover: fresh.cover.isEmpty ? cover : fresh.cover,
            episodes: fresh.episodes > 0 ? fresh.episodes : episodes,
            category: fresh.category.isEmpty ? category : fresh.category,
            vip: fresh.vip ?? vip,
            heat: fresh.heat.isEmpty ? heat : fresh.heat,
            views: fresh.views.isEmpty ? views : fresh.views,
            onlineDate: fresh.onlineDate.isEmpty ? onlineDate : fresh.onlineDate,
            tags: fresh.tags.isEmpty ? tags : fresh.tags,
            releaseStatus: fresh.releaseStatus.isEmpty ? releaseStatus : fresh.releaseStatus
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, source, sourceId, title, description, cover, episodes, category, vip, heat, views, onlineDate, tags, releaseStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "hongguo"
        self.sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId) ?? ""
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "短剧"
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.cover = try container.decodeIfPresent(String.self, forKey: .cover) ?? ""
        
        if let epInt = try? container.decodeIfPresent(Int.self, forKey: .episodes) {
            self.episodes = epInt
        } else if let epStr = try? container.decodeIfPresent(String.self, forKey: .episodes), let val = Int(epStr) {
            self.episodes = val
        } else {
            self.episodes = 0
        }

        self.category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        self.vip = try container.decodeIfPresent(Bool.self, forKey: .vip)
        self.heat = try container.decodeIfPresent(String.self, forKey: .heat) ?? ""
        self.views = try container.decodeIfPresent(String.self, forKey: .views) ?? ""
        self.onlineDate = try container.decodeIfPresent(String.self, forKey: .onlineDate) ?? ""
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.releaseStatus = try container.decodeIfPresent(String.self, forKey: .releaseStatus) ?? ""
    }
}

public struct CatalogCategory: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let all = CatalogCategory(id: "", name: "全部")
    public static let recommendations = CatalogCategory(id: "app:recommendations", name: "推荐")
}

public enum CatalogSort: String, CaseIterable, Identifiable {
    case source = "default"
    case latest = "latest"
    case heat = "heat"
    case views = "views"
    case title = "title"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .source: return "默认排序"
        case .latest: return "最新上线"
        case .heat: return "最高热度"
        case .views: return "最多播放"
        case .title: return "名称排序"
        }
    }
}

public enum CatalogReleaseFilter: String, CaseIterable, Identifiable {
    case all = ""
    case ongoing = "ongoing"
    case completed = "completed"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "全部状态"
        case .ongoing: return "连载中"
        case .completed: return "已完结"
        }
    }
}
