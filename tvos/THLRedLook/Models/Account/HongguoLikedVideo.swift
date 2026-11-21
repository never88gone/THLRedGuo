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
