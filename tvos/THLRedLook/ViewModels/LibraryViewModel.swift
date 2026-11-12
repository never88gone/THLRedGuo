import Foundation
import Combine

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public var selectedTab: LibraryTab = .history
    @Published public var selectedFollowFilter: FollowState = .none
    @Published public var searchQuery: String = ""

    @Published private(set) var accountLists: [LibraryTab: [WatchEntry]] = [:]
    @Published private(set) var accountErrors: [LibraryTab: String] = [:]
    @Published private(set) var loadingTabs: Set<LibraryTab> = []
    @Published private(set) var officialLikes: [HongguoLikedVideo] = []
    @Published private(set) var officialAnchors: [Anchor] = []
    @Published private(set) var moreTabs: Set<LibraryTab> = []
    private var failedRefresh: Set<LibraryTab> = []
    private var loadedTabs: Set<LibraryTab> = []
    private var offsets: [LibraryTab: Int] = [:]
    private var douyinOffset = 0
    private var emptyPages: [LibraryTab: Int] = [:]
    private var accountRevision: UInt64?

    private(set) var fixtureMode = false
    var officialAccount: Bool { fixtureMode || isAccountAvailable() }
    var isAccountAvailable: () -> Bool = { HongguoAccountModel.shared.loggedIn }
    var ownerRevision: () -> UInt64 = { HongguoAccountVault.shared.snapshot.revision }
    var followingRequest: (Int, Int) async throws -> HongguoCollectionPage<Anchor> = { try await HongguoAccountModel.shared.followingCreators(offset: $0, douyinOffset: $1) }
    var likesRequest: (Int) async throws -> HongguoCollectionPage<HongguoLikedVideo> = { try await HongguoAccountModel.shared.likedVideos(offset: $0) }
    var profileRequest: (String) async throws -> Anchor = { try await HongguoAccountModel.shared.creatorProfile($0) }

    func syncAccountOwner() {
        let revision = ownerRevision()
        guard revision != accountRevision else { return }
        accountRevision = revision; accountLists = [:]; accountErrors = [:]; loadingTabs = []
        officialLikes = []; officialAnchors = []; moreTabs = []; loadedTabs = []; failedRefresh = []; offsets = [:]; douyinOffset = 0; emptyPages = [:]
    }

    func loadAccount(_ tab: LibraryTab, refresh: Bool = false, more: Bool = false) async {
        syncAccountOwner()
        let refresh = refresh || failedRefresh.contains(tab)
        let revision = accountRevision!
        guard officialAccount, !loadingTabs.contains(tab),
              refresh || (more ? moreTabs.contains(tab) : !loadedTabs.contains(tab)) else { return }
        loadingTabs.insert(tab); accountErrors[tab] = nil
        defer { if accountRevision == revision { loadingTabs.remove(tab) } }
        let offset = refresh ? 0 : offsets[tab] ?? 0
        let douyin = refresh ? 0 : douyinOffset
        do {
            switch tab {
            case .anchors:
                let page = try await followingRequest(offset, douyin)
                guard accountRevision == revision, ownerRevision() == revision else { return }
                try validateCursor(page, offset: offset, douyin: douyin)
                let previousCount = refresh ? 0 : officialAnchors.count
                officialAnchors = merge(refresh ? [] : officialAnchors, page.items, key: { $0.id })
                acceptPage(tab, page: page, offset: offset, refresh: refresh, added: officialAnchors.count - previousCount)
                douyinOffset = page.douyinOffset
            case .liked:
                let page = try await likesRequest(offset)
                guard accountRevision == revision, ownerRevision() == revision else { return }
                try validateCursor(page, offset: offset, douyin: 0)
                let previousCount = refresh ? 0 : officialLikes.count
                officialLikes = merge(refresh ? [] : officialLikes, page.items, key: { $0.id })
                acceptPage(tab, page: page, offset: offset, refresh: refresh, added: officialLikes.count - previousCount)
            default:
                let entries = try await HongguoAccountModel.shared.library(history: tab == .history)
                guard accountRevision == revision, ownerRevision() == revision else { return }
                accountLists[tab] = entries
            }
            failedRefresh.remove(tab)
            loadedTabs.insert(tab)
        } catch {
            guard accountRevision == revision, ownerRevision() == revision else { return }
            if refresh { failedRefresh.insert(tab) }
            accountErrors[tab] = (error as? HongguoAccountError)?.localizedDescription ?? "账号列表获取失败，请重试"
        }
    }

    private func validateCursor<T>(_ page: HongguoCollectionPage<T>, offset: Int, douyin: Int) throws {
        if page.hasMore {
            guard let next = page.nextOffset, next >= offset, next > offset || page.douyinOffset > douyin else {
                throw HongguoAccountError.interactionInvalid
            }
        }
    }

    private func acceptPage<T>(_ tab: LibraryTab, page: HongguoCollectionPage<T>, offset: Int, refresh: Bool, added: Int) {
        offsets[tab] = page.nextOffset ?? offset
        if page.hasMore { moreTabs.insert(tab) } else { moreTabs.remove(tab) }
        emptyPages[tab] = added == 0 ? (refresh ? 0 : emptyPages[tab] ?? 0) + 1 : 0
        if page.hasMore && emptyPages[tab, default: 0] >= 3 {
            accountErrors[tab] = "连续多页暂无可展示内容，请稍后重试"
        } else if page.hasMore && added == 0 {
            Task { await Task.yield(); if selectedTab == tab { await loadAccount(tab, more: true) } }
        }
    }

    private func merge<T>(_ previous: [T], _ incoming: [T], key: (T) -> String) -> [T] {
        var result = previous
        var indices = Dictionary(uniqueKeysWithValues: previous.enumerated().map { (key($0.element), $0.offset) })
        for row in incoming {
            if let index = indices[key(row)] { result[index] = row }
            else { indices[key(row)] = result.count; result.append(row) }
        }
        return result
    }

    func loadMoreIfNeeded(_ tab: LibraryTab, index: Int, count: Int) async {
        guard index >= count - 5, accountErrors[tab] == nil else { return }
        await loadAccount(tab, more: true)
    }

    private let store: LocalStore
    private var cancellables = Set<AnyCancellable>()

    public init(store: LocalStore = .shared) {
        self.store = store
        #if DEBUG
        configureCollectionFixtures()
        #endif
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        UserLikeStore.shared.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        AnchorFollowStore.shared.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    #if DEBUG
    private func configureCollectionFixtures() {
        guard let raw = ProcessInfo.processInfo.environment["THL_ACCOUNT_COLLECTION_FIXTURE"],
              let data = raw.data(using: .utf8),
              let fixture = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let anchors = fixture["creators"] as? [[String: Any]],
              let likes = fixture["items"] as? [[String: Any]] else { return }
        fixtureMode = true
        selectedTab = .anchors
        let size = max(1, fixture["pageSize"] as? Int ?? 10)
        var failNextPage = fixture["failNextPageOnce"] as? Bool == true
        followingRequest = { offset, _ in
            try await Task.sleep(nanoseconds: 100_000_000)
            if offset > 0 && failNextPage { failNextPage = false; throw HongguoAccountError.network }
            let end = min(offset + size, anchors.count)
            let rows = offset < end ? Array(anchors[offset..<end]) : []
            return HongguoCollectionPage(items: rows.compactMap { Anchor(official: $0) }, hasMore: end < anchors.count, nextOffset: end)
        }
        likesRequest = { offset in
            let end = min(offset + size, likes.count)
            let rows = offset < end ? Array(likes[offset..<end]) : []
            return HongguoCollectionPage(items: rows.compactMap { HongguoLikedVideo(row: $0) }, hasMore: end < likes.count, nextOffset: end)
        }
        profileRequest = { id in
            guard let row = anchors.first(where: { $0["id"] as? String == id }), let anchor = Anchor(official: row) else {
                throw HongguoAccountError.interactionInvalid
            }
            return anchor
        }
    }
    #endif

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

    public var likedList: [Drama] {
        let all = UserLikeStore.shared.likedDramas
        guard !searchQuery.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    public var followedAnchorsList: [Anchor] {
        let all = officialAccount ? officialAnchors : AnchorFollowStore.shared.followedAnchors
        guard !searchQuery.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
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
