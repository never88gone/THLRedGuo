import Foundation

public struct SeriesSeason: Decodable {
    public let drama: Drama
    public let season: Int
    public let playable: Bool
    public let status: String
}

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
        let isHongguo = source == "hongguo" || id.hasPrefix("hongguo:")
        self.vip = isHongguo ? false : vip
        self.heat = heat
        self.views = views
        self.onlineDate = onlineDate
        self.tags = isHongguo ? tags.filter { t in
            let lower = t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !lower.contains("vip") && !lower.contains("付费")
        } : tags
        self.releaseStatus = releaseStatus
    }

    public var cleanSourceId: String {
        let value = sourceId.isEmpty ? id : sourceId
        if let suffix = value.split(separator: ":").last, value.contains(":") { return String(suffix) }
        let prefix = source + "_"
        return !source.isEmpty && value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
    }

    public var isVIP: Bool {
        source != "hongguo" && !id.hasPrefix("hongguo:") && vip == true
    }

    public var releaseLabel: String {
        switch releaseStatus.lowercased() {
        case "finished", "completed":
            return "已完结"
        case "ongoing":
            return "连载中"
        case "upcoming":
            return "待上线"
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
        let isHongguo = source == "hongguo" || id.hasPrefix("hongguo:") || fresh.source == "hongguo" || fresh.id.hasPrefix("hongguo:")
        let mergedVip: Bool? = isHongguo ? false : (fresh.vip ?? vip)
        let mergedTags = isHongguo ? (fresh.tags.isEmpty ? tags : fresh.tags).filter { t in
            let lower = t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !lower.contains("vip") && !lower.contains("付费")
        } : (fresh.tags.isEmpty ? tags : fresh.tags)

        return Drama(
            id: id,
            source: fresh.source.isEmpty ? source : fresh.source,
            sourceId: fresh.sourceId.isEmpty ? sourceId : fresh.sourceId,
            title: (fresh.title.isEmpty || fresh.title == "短剧") ? title : fresh.title,
            description: fresh.description.isEmpty ? description : fresh.description,
            cover: fresh.cover.isEmpty ? cover : fresh.cover,
            episodes: fresh.episodes > 0 ? fresh.episodes : episodes,
            category: fresh.category.isEmpty ? category : fresh.category,
            vip: mergedVip,
            heat: fresh.heat.isEmpty ? heat : fresh.heat,
            views: fresh.views.isEmpty ? views : fresh.views,
            onlineDate: fresh.onlineDate.isEmpty ? onlineDate : fresh.onlineDate,
            tags: mergedTags,
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
        let isHongguo = self.source == "hongguo" || self.id.hasPrefix("hongguo:")
        let rawVip = try container.decodeIfPresent(Bool.self, forKey: .vip)
        self.vip = isHongguo ? false : rawVip
        self.heat = try container.decodeIfPresent(String.self, forKey: .heat) ?? ""
        self.views = try container.decodeIfPresent(String.self, forKey: .views) ?? ""
        self.onlineDate = try container.decodeIfPresent(String.self, forKey: .onlineDate) ?? ""
        let rawTags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.tags = isHongguo ? rawTags.filter { t in
            let lower = t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !lower.contains("vip") && !lower.contains("付费")
        } : rawTags
        self.releaseStatus = try container.decodeIfPresent(String.self, forKey: .releaseStatus) ?? ""
    }
}

public enum HongguoSeriesIdentity {
    public static func isRounded(_ drama: Drama) -> Bool {
        guard drama.source.lowercased() == "hongguo",
              drama.cleanSourceId.range(of: "^[1-9]\\d{15,29}$", options: .regularExpression) != nil,
              let number = Double(drama.cleanSourceId), number.isFinite, number > 9_007_199_254_740_991 else { return false }
        return NSDecimalNumber(string: String(number), locale: Locale(identifier: "en_US_POSIX")).stringValue == drama.cleanSourceId
    }

    private static func cleanTitle(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "[（(【\\[]\\s*(?:4K|1080P|720P|超清|高清|全集|完结|精修版|独家|热播|已完结|[0-9]+集全?|\\s)+\\s*[）)】\\]]$"
        while let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            result.removeSubrange(range)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    public static func baseTitle(_ title: String) -> String {
        cleanTitle(title).replacingOccurrences(of: "第\\s*[0-9零〇一二两三四五六七八九十百]+\\s*[季部]\\s*$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func seasonNumber(_ value: String) -> Int? {
        if let number = Int(value) { return (1...200).contains(number) ? number : nil }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        var total = 0
        var digit = 0
        for character in value {
            if let number = digits[character] { digit = digit * 10 + number }
            else if character == "十" || character == "百" {
                total += max(1, digit) * (character == "十" ? 10 : 100)
                digit = 0
            } else { return nil }
        }
        let number = total + digit
        return (1...200).contains(number) ? number : nil
    }

    private static func titleKey(_ title: String) -> String {
        var result = cleanTitle(title).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? cleanTitle(title)
        let regex = try! NSRegularExpression(pattern: "第\\s*([0-9零〇一二两三四五六七八九十百]+)\\s*([季部])\\s*$")
        if let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let numberRange = Range(match.range(at: 1), in: result),
           let unitRange = Range(match.range(at: 2), in: result),
           let wholeRange = Range(match.range, in: result),
           let number = seasonNumber(String(result[numberRange])) {
            let suffix = "第\(number)" + String(result[unitRange])
            result.replaceSubrange(wholeRange, with: suffix)
        }
        return result.lowercased().replacingOccurrences(of: "[\\s\\p{P}]+", with: "", options: .regularExpression)
    }

    public static func replacements(previous: [Drama], fresh: [Drama]) -> [String: Drama] {
        let stale = previous.filter(isRounded)
        guard !stale.isEmpty else { return [:] }
        let listed = Set(fresh.filter { $0.source.lowercased() == "hongguo" }.map(\.cleanSourceId))
        let grouped = Dictionary(grouping: fresh.filter {
            $0.source.lowercased() == "hongguo" && !isRounded($0) &&
            $0.cleanSourceId.range(of: "^[1-9]\\d{15,29}$", options: .regularExpression) != nil
        }, by: { titleKey($0.title) })
        var result: [String: Drama] = [:]
        for old in stale where !listed.contains(old.cleanSourceId) {
            let matches = (grouped[titleKey(old.title)] ?? []).filter { Double($0.cleanSourceId) == Double(old.cleanSourceId) }
            let unique = Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            if unique.count == 1 { result[old.id] = unique.values.first }
        }
        return result
    }

    public static func merge(_ previous: Drama, with fresh: Drama) -> Drama {
        Drama(id: fresh.id, source: fresh.source, sourceId: fresh.cleanSourceId,
              title: previous.title, description: previous.description, cover: previous.cover,
              episodes: previous.episodes, category: previous.category, vip: previous.vip,
              heat: previous.heat, views: previous.views, onlineDate: previous.onlineDate,
              tags: previous.tags, releaseStatus: previous.releaseStatus).merge(with: fresh)
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
