import Foundation
import Combine

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public var selectedTab: LibraryTab = .history
    @Published public var selectedFollowFilter: FollowState = .none
    @Published public var searchQuery: String = ""

    public enum LibraryTab: String, CaseIterable, Identifiable {
        case history = "history"
        case follows = "follows"

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .history: return "最近观看"
            case .follows: return "我的收藏"
            }
        }
    }

    @Published private(set) var accountLists: [LibraryTab: [WatchEntry]] = [:]
    @Published private(set) var accountErrors: [LibraryTab: String] = [:]
    @Published private(set) var loadingTabs: Set<LibraryTab> = []
    private var accountRevision: UInt64?

    func loadAccount(_ tab: LibraryTab, refresh: Bool = false) async {
        let revision = HongguoAccountVault.shared.snapshot.revision
        if revision != accountRevision {
            accountRevision = revision; accountLists = [:]; accountErrors = [:]; loadingTabs = []
        }
        guard HongguoAccountModel.shared.loggedIn, !loadingTabs.contains(tab), refresh || accountLists[tab] == nil else { return }
        loadingTabs.insert(tab); accountErrors[tab] = nil
        defer { if accountRevision == revision { loadingTabs.remove(tab) } }
        do {
            let entries = try await HongguoAccountModel.shared.library(history: tab == .history)
            guard accountRevision == revision, HongguoAccountVault.shared.snapshot.revision == revision else { return }
            accountLists[tab] = entries
        } catch {
            NSLog("[AccountLibrary] error=%@", (error as? HongguoAccountError)?.localizedDescription ?? "network")
            guard accountRevision == revision, HongguoAccountVault.shared.snapshot.revision == revision else { return }
            accountErrors[tab] = "账号列表获取失败，请重试"
        }
    }

    private let store: LocalStore
    private var cancellables = Set<AnyCancellable>()

    public init(store: LocalStore = .shared) {
        self.store = store
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var currentSource: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : store.currentSourceId
        return src.isEmpty ? "hongguo" : src
    }

    public var historyList: [WatchEntry] {
        let target = currentSource.lowercased()
        let sourceMatched = store.history.filter { $0.drama.source.lowercased() == target }
        guard !searchQuery.isEmpty else { return sourceMatched }
        return sourceMatched.filter { $0.drama.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    public var followedList: [Drama] {
        let target = currentSource.lowercased()
        let sourceMatched = store.followedDramas.filter { $0.source.lowercased() == target }
        let filtered: [Drama]
        if selectedFollowFilter == .none {
            filtered = sourceMatched
        } else {
            filtered = sourceMatched.filter { store.followState(for: $0.id) == selectedFollowFilter }
        }
        guard !searchQuery.isEmpty else { return filtered }
        return filtered.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    public func clearHistory() {
        store.clearHistory(for: currentSource)
    }

    public func removeHistory(dramaId: String) {
        store.removeHistory(dramaId: dramaId)
    }

    public func removeFollow(dramaId: String) {
        store.removeFollow(dramaId: dramaId)
    }
}
