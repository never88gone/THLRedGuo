import Foundation

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
