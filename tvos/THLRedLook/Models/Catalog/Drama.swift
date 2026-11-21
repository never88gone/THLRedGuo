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

    public static func formatMetricNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "0" { return "" }

        if trimmed.contains("亿") {
            let numStr = trimmed.filter { "0123456789.".contains($0) }
            if let val = Double(numStr) {
                let formatted = String(format: "%.1f", val)
                return (formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted) + "亿"
            }
            return trimmed
        }

        if trimmed.contains("万") || trimmed.contains("w") || trimmed.contains("W") {
            let numStr = trimmed.filter { "0123456789.".contains($0) }
            if let val = Double(numStr) {
                if val >= 1000 {
                    return "\(Int(round(val)))万"
                } else {
                    let formatted = String(format: "%.1f", val)
                    return (formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted) + "万"
                }
            }
            return trimmed
        }

        let numStr = trimmed.filter { "0123456789.".contains($0) }
        guard let val = Double(numStr), val > 0 else {
            return trimmed
        }

        if val >= 100_000_000 {
            let yi = val / 100_000_000.0
            let formatted = String(format: "%.1f", yi)
            return (formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted) + "亿"
        } else if val >= 10_000 {
            let wan = val / 10_000.0
            if wan >= 1000 {
                return "\(Int(round(wan)))万"
            } else {
                let formatted = String(format: "%.1f", wan)
                return (formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted) + "万"
            }
        } else {
            return "\(Int(val))"
        }
    }

    public var formattedHeat: String {
        Drama.formatMetricNumber(heat)
    }

    public var formattedViews: String {
        Drama.formatMetricNumber(views)
    }

    public var displaySubtitle: String {
        if !heat.isEmpty {
            let fmt = formattedHeat
            if !fmt.isEmpty {
                return fmt.contains("🔥") ? fmt : "🔥 \(fmt)"
            }
        }
        if !views.isEmpty {
            let fmt = formattedViews
            if !fmt.isEmpty {
                return fmt.contains("👁") ? fmt : "👁 \(fmt)"
            }
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
