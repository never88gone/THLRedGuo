import Foundation

struct HongguoLikedVideo: Identifiable {
    let id: String
    let drama: Drama?
    let title: String
    let subtitle: String

    init?(row: [String: Any]) {
        guard let rawID = row["id"] as? String, let kind = row["kind"] as? String else { return nil }
        id = "\(kind):\(rawID)"
        title = row["title"] as? String ?? "点赞视频"
        subtitle = kind == "series" ? "已点赞合集" : (row["episode"] as? Int).map { "已点赞 · 第 \($0) 集" } ?? "已点赞视频"
        if let series = row["seriesId"] as? String, series.range(of: "^[1-9][0-9]{0,29}$", options: .regularExpression) != nil {
            drama = Drama(
                id: "hongguo:\(series)",
                sourceId: series,
                title: title,
                description: row["description"] as? String ?? "",
                cover: row["cover"] as? String ?? "",
                episodes: row["episodes"] as? Int ?? 0
            )
        } else {
            drama = nil
        }
    }
}

struct HongguoSubscribeItem: Identifiable {
    let key: String
    let itemId: String
    let title: String
    let subtitle: String
    let isOnline: Bool
    let drama: Drama

    var id: String { key }

    init?(row: [String: Any], isOnlineTab: Bool = false) {
        let rawId = (row["itemId"] as? String ?? row["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawId.isEmpty else { return nil }
        itemId = rawId
        let online = row["isOnline"] as? Bool ?? isOnlineTab
        isOnline = online
        key = "\(online ? "on" : "pre"):\(rawId)"
        let rawTitle = (row["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        title = rawTitle.isEmpty ? "待上线短剧" : rawTitle
        let sub = (row["subtitle"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        subtitle = sub
        let status = (row["releaseStatus"] as? String ?? (online ? "finished" : "upcoming")).trimmingCharacters(in: .whitespacesAndNewlines)
        let date = (row["onlineDate"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let heat = (row["heat"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = (row["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cover = (row["cover"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let epCount = (row["episodes"] as? NSNumber)?.intValue ?? 0
        let tags = row["tags"] as? [String] ?? []
        drama = Drama(
            id: "hongguo:\(rawId)",
            source: "hongguo",
            sourceId: rawId,
            title: title,
            description: desc,
            cover: cover,
            episodes: epCount,
            category: "新剧预约",
            heat: heat,
            onlineDate: date,
            tags: tags,
            releaseStatus: status
        )
    }
}
