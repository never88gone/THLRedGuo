import SwiftUI

public enum TVAppTab: String, CaseIterable, Identifiable {
    case catalog = "catalog"
    case feed = "feed"
    case rankings = "rankings"
    case search = "search"
    case library = "library"
    case downloads = "downloads"
    case settings = "settings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .catalog: return "发现"
        case .feed: return "推荐"
        case .rankings: return "榜单"
        case .search: return "搜索"
        case .library: return "我的"
        case .downloads: return "下载"
        case .settings: return "设置"
        }
    }

    public var label: String {
        switch self {
        case .catalog: return "精选短剧"
        case .feed: return "短剧推荐"
        case .rankings: return "短剧榜单"
        case .search: return "搜索"
        case .library: return "追剧"
        case .downloads: return "下载"
        case .settings: return "设置"
        }
    }

    public var icon: String {
        switch self {
        case .catalog: return "sparkles.tv"
        case .feed: return "play.rectangle.fill"
        case .rankings: return "chart.bar.fill"
        case .search: return "magnifyingglass"
        case .library: return "person.crop.circle.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    public var nextTab: TVAppTab? {
        let all = TVAppTab.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    public var prevTab: TVAppTab? {
        let all = TVAppTab.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return nil }
        return all[idx - 1]
    }

    public var accessibilityIdentifier: String {
        switch self {
        case .catalog: return "nav.catalog"
        case .feed: return "nav.feed"
        case .rankings: return "nav.rankings"
        case .search: return "nav.search"
        case .library: return "nav.library"
        case .downloads: return "nav.downloads"
        case .settings: return "nav.settings"
        }
    }
}
