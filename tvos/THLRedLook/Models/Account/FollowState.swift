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
