import Foundation

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
