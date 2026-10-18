import Foundation

public struct PlaybackPlan: Hashable, Codable {
    public let url: String
    public let headers: [String: String]
    public let decryptionKey: String
    public let quality: Int
    public let qualities: [Int]
    public let session: String
    public let danmakuId: String
    public let prefetchedBytes: Int
    public let expiresAt: Int64
    public let mediaBytes: Int64
    public let routeIndex: Int
    public let routeCount: Int
    public let local: Bool

    public init(
        url: String,
        headers: [String: String] = [:],
        decryptionKey: String = "",
        quality: Int = 0,
        qualities: [Int] = [],
        session: String = "",
        danmakuId: String = "",
        prefetchedBytes: Int = 0,
        expiresAt: Int64 = 0,
        mediaBytes: Int64 = 0,
        routeIndex: Int = 0,
        routeCount: Int = 1,
        local: Bool = false
    ) {
        self.url = url
        self.headers = headers
        self.decryptionKey = decryptionKey
        self.quality = quality
        self.qualities = qualities.sorted(by: >)
        self.session = session
        self.danmakuId = danmakuId
        self.prefetchedBytes = prefetchedBytes
        self.expiresAt = expiresAt
        self.mediaBytes = max(0, mediaBytes)
        self.routeIndex = routeIndex
        self.routeCount = max(1, routeCount)
        self.local = local
    }

    enum CodingKeys: String, CodingKey {
        case url, headers, decryptionKey, quality, qualities, session, danmakuId, prefetchedBytes, expiresAt, mediaBytes, routeIndex, routeCount, local
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        self.headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        self.decryptionKey = try container.decodeIfPresent(String.self, forKey: .decryptionKey) ?? ""
        self.quality = try container.decodeIfPresent(Int.self, forKey: .quality) ?? 0
        self.qualities = try container.decodeIfPresent([Int].self, forKey: .qualities) ?? []
        self.session = try container.decodeIfPresent(String.self, forKey: .session) ?? ""
        self.danmakuId = try container.decodeIfPresent(String.self, forKey: .danmakuId) ?? ""
        self.prefetchedBytes = try container.decodeIfPresent(Int.self, forKey: .prefetchedBytes) ?? 0
        self.expiresAt = try container.decodeIfPresent(Int64.self, forKey: .expiresAt) ?? 0
        self.mediaBytes = try container.decodeIfPresent(Int64.self, forKey: .mediaBytes) ?? 0
        self.routeIndex = try container.decodeIfPresent(Int.self, forKey: .routeIndex) ?? 0
        self.routeCount = try container.decodeIfPresent(Int.self, forKey: .routeCount) ?? 1
        self.local = try container.decodeIfPresent(Bool.self, forKey: .local) ?? false
    }

    public var hasAlternative: Bool {
        !session.isEmpty && (routeIndex + 1 < routeCount)
    }

    public static func qualityLabel(_ q: Int) -> String {
        switch q {
        case 2160: return "4K 超清"
        case 1080: return "1080P 高清"
        case 720: return "720P 高清"
        case 480: return "480P 流畅"
        case 360: return "360P 标清"
        default: return q > 0 ? "\(q)P" : "自动"
        }
    }
}
