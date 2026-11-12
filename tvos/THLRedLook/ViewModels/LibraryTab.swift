import Foundation

public enum LibraryTab: String, CaseIterable, Identifiable {
    case history = "history"
    case follows = "follows"
    case liked = "liked"
    case anchors = "anchors"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .history: return "最近观看"
        case .follows: return "我的收藏"
        case .liked: return "点赞视频"
        case .anchors: return "关注主播"
        }
    }
}
