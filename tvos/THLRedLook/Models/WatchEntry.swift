import Foundation

public enum FollowState: String, CaseIterable, Identifiable, Codable {
    case none = "none"
    case wishlist = "wishlist" // 想看
    case watching = "watching" // 在看
    case watched = "watched"   // 已看
    case updated = "updated"   // 有更新

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "未追剧"
        case .wishlist: return "想看"
        case .watching: return "在看"
        case .watched: return "已看"
        case .updated: return "有更新"
        }
    }

    public static func from(string: String) -> FollowState {
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "wishlist", "planned":
            return .wishlist
        case "watching":
            return .watching
        case "watched", "finished", "completed":
            return .watched
        case "updated":
            return .updated
        default:
            return .none
        }
    }
}

public struct WatchEntry: Identifiable, Hashable, Codable {
    public var id: String { drama.id }
    public let drama: Drama
    public let episode: Int
    public let position: Double
    public let duration: Double
    public let updatedAt: Date

    public init(drama: Drama, episode: Int, position: Double, duration: Double, updatedAt: Date = Date()) {
        self.drama = drama
        self.episode = episode
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    public var finished: Bool {
        duration > 1 && position >= duration - 1
    }

    public var progressPercent: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1.0)
    }

    public var progressLabel: String {
        let ep = episode > 0 ? "第 \(episode) 集" : ""
        let pct = Int(progressPercent * 100)
        return finished ? "\(ep) · 已播完" : "\(ep) · 看到 \(pct)%"
    }
}
