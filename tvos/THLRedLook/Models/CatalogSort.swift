import Foundation

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
