import Foundation
import Combine

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public var selectedTab: LibraryTab = .history
    @Published public var selectedFollowFilter: FollowState = .none
    @Published public var selectedReserveOnline: Bool = false
    @Published public var searchQuery: String = ""

    @Published private(set) var accountLists: [LibraryTab: [WatchEntry]] = [:]
    @Published private(set) var accountErrors: [LibraryTab: String] = [:]
    @Published private(set) var loadingTabs: Set<LibraryTab> = []
    @Published private(set) var officialLikes: [HongguoLikedVideo] = []
    @Published private(set) var officialAnchors: [Anchor] = []
    @Published private(set) var officialReservedComing: [HongguoSubscribeItem] = []
    @Published private(set) var officialReservedOnline: [HongguoSubscribeItem] = []
    @Published private(set) var moreTabs: Set<LibraryTab> = []
    private var failedRefresh: Set<LibraryTab> = []
    private var loadedTabs: Set<LibraryTab> = []
    private var offsets: [LibraryTab: Int] = [:]
    private var douyinOffset = 0
    private var emptyPages: [LibraryTab: Int] = [:]
    private var reserveOffsets: [Bool: Int] = [:]
    private var reserveMore: Set<Bool> = []
    private var reserveLoaded: Set<Bool> = []
    private var reserveFailed: Set<Bool> = []
    private var reserveEmptyPages: [Bool: Int] = [:]
    private var reserveErrors: [Bool: String] = [:]
    private var accountRevision: UInt64?

    private(set) var fixtureMode = false
    var officialAccount: Bool { fixtureMode || isAccountAvailable() }
    var isAccountAvailable: () -> Bool = { HongguoAccountModel.shared.loggedIn }
    var ownerRevision: () -> UInt64 = { HongguoAccountVault.shared.snapshot.revision }
    var followingRequest: (Int, Int) async throws -> HongguoCollectionPage<Anchor> = { try await HongguoAccountModel.shared.followingCreators(offset: $0, douyinOffset: $1) }
    var likesRequest: (Int) async throws -> HongguoCollectionPage<HongguoLikedVideo> = { try await HongguoAccountModel.shared.likedVideos(offset: $0) }
    var reserveRequest: (Int, Bool) async throws -> HongguoCollectionPage<HongguoSubscribeItem> = { try await HongguoAccountModel.shared.subscribedDramas(offset: $0, isOnline: $1) }
    var profileRequest: (String) async throws -> Anchor = { try await HongguoAccountModel.shared.creatorProfile($0) }

    func syncAccountOwner() {
        let revision = ownerRevision()
        guard revision != accountRevision else { return }
        accountRevision = revision; accountLists = [:]; accountErrors = [:]; loadingTabs = []
        officialLikes = []; officialAnchors = []; officialReservedComing = []; officialReservedOnline = []
        moreTabs = []; loadedTabs = []; failedRefresh = []; offsets = [:]; douyinOffset = 0; emptyPages = [:]
        reserveOffsets = [:]; reserveMore = []; reserveLoaded = []; reserveFailed = []; reserveEmptyPages = [:]; reserveErrors = [:]
    }

    func switchReserveFilter(_ online: Bool) {
        guard selectedReserveOnline != online else { return }
        selectedReserveOnline = online
        accountErrors[.reservations] = reserveErrors[online]
        if reserveMore.contains(online) { moreTabs.insert(.reservations) } else { moreTabs.remove(.reservations) }
        Task { await loadAccount(.reservations) }
    }

    func loadAccount(_ tab: LibraryTab, refresh: Bool = false, more: Bool = false) async {
        syncAccountOwner()
        if tab == .reservations {
            await loadReservations(online: selectedReserveOnline, refresh: refresh, more: more)
            return
        }
        let effectiveRefresh = refresh || failedRefresh.contains(tab)
        let isCurrentTabEmpty: Bool = {
            switch tab {
            case .anchors: return officialAnchors.isEmpty
            case .liked: return officialLikes.isEmpty
            default: return (accountLists[tab] ?? []).isEmpty
            }
        }()
        let shouldRefresh = effectiveRefresh || (!more && isCurrentTabEmpty && !loadedTabs.contains(tab))
        let revision = accountRevision!
        guard officialAccount, !loadingTabs.contains(tab),
              shouldRefresh || (more ? moreTabs.contains(tab) : !loadedTabs.contains(tab)) else { return }
        loadingTabs.insert(tab); accountErrors[tab] = nil
        defer { if accountRevision == revision { loadingTabs.remove(tab) } }
        let offset = effectiveRefresh ? 0 : offsets[tab] ?? 0
        let douyin = effectiveRefresh ? 0 : douyinOffset
        do {
            switch tab {
            case .anchors:
                let page = try await followingRequest(offset, douyin)
                guard accountRevision == revision, ownerRevision() == revision else { return }
                try validateCursor(page, offset: offset, douyin: douyin)
                let previousCount = effectiveRefresh ? 0 : officialAnchors.count
                officialAnchors = merge(effectiveRefresh ? [] : officialAnchors, page.items, key: { $0.id })
                acceptPage(tab, page: page, offset: offset, refresh: effectiveRefresh, added: officialAnchors.count - previousCount)
                douyinOffset = page.douyinOffset
            case .liked:
                let page = try await likesRequest(offset)
                guard accountRevision == revision, ownerRevision() == revision else { return }
                try validateCursor(page, offset: offset, douyin: 0)
                let previousCount = effectiveRefresh ? 0 : officialLikes.count
                officialLikes = merge(effectiveRefresh ? [] : officialLikes, page.items, key: { $0.id })
                acceptPage(tab, page: page, offset: offset, refresh: effectiveRefresh, added: officialLikes.count - previousCount)
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

    private func loadReservations(online: Bool, refresh: Bool, more: Bool) async {
        let effectiveRefresh = refresh || reserveFailed.contains(online)
        let currentItems = online ? officialReservedOnline : officialReservedComing
        let shouldRefresh = effectiveRefresh || (!more && currentItems.isEmpty && !reserveLoaded.contains(online))
        let revision = accountRevision!
        guard officialAccount, !loadingTabs.contains(.reservations),
              shouldRefresh || (more ? reserveMore.contains(online) : !reserveLoaded.contains(online)) else { return }
        loadingTabs.insert(.reservations)
        reserveErrors[online] = nil
        if selectedReserveOnline == online { accountErrors[.reservations] = nil }
        defer { if accountRevision == revision { loadingTabs.remove(.reservations) } }
        let offset = effectiveRefresh ? 0 : (reserveOffsets[online] ?? 0)
        do {
            let page = try await reserveRequest(offset, online)
            guard accountRevision == revision, ownerRevision() == revision else { return }
            try validateCursor(page, offset: offset, douyin: 0)
            let previous = effectiveRefresh ? [] : (online ? officialReservedOnline : officialReservedComing)
            let updated = merge(previous, page.items, key: { $0.key })
            if online { officialReservedOnline = updated } else { officialReservedComing = updated }
            let added = updated.count - previous.count
            reserveOffsets[online] = page.nextOffset ?? offset
            if page.hasMore { reserveMore.insert(online) } else { reserveMore.remove(online) }
            reserveEmptyPages[online] = added == 0 ? (effectiveRefresh ? 0 : reserveEmptyPages[online] ?? 0) + 1 : 0
            if page.hasMore && reserveEmptyPages[online, default: 0] >= 3 {
                reserveErrors[online] = "连续多页暂无可展示内容，请稍后重试"
            }
            if selectedReserveOnline == online {
                if page.hasMore { moreTabs.insert(.reservations) } else { moreTabs.remove(.reservations) }
                accountErrors[.reservations] = reserveErrors[online]
            }
            reserveFailed.remove(online)
            reserveLoaded.insert(online)
        } catch {
            guard accountRevision == revision, ownerRevision() == revision else { return }
            if refresh { reserveFailed.insert(online) }
            let message = (error as? HongguoAccountError)?.localizedDescription ?? "我的预约获取失败，请重试"
            reserveErrors[online] = message
            if selectedReserveOnline == online { accountErrors[.reservations] = message }
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

        HongguoAccountModel.shared.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
                Task { @MainActor in
                    if self.officialAccount {
                        let isEmpty: Bool
                        switch self.selectedTab {
                        case .anchors: isEmpty = self.officialAnchors.isEmpty
                        case .liked: isEmpty = self.officialLikes.isEmpty
                        case .reservations: isEmpty = (self.selectedReserveOnline ? self.officialReservedOnline : self.officialReservedComing).isEmpty
                        default: isEmpty = (self.accountLists[self.selectedTab] ?? []).isEmpty
                        }
                        if isEmpty && !self.loadingTabs.contains(self.selectedTab) {
                            await self.loadAccount(self.selectedTab)
                        }
                    }
                }
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
        selectedTab = (fixture["initialTab"] as? String) == "reservations" ? .reservations : .anchors
        let size = max(1, fixture["pageSize"] as? Int ?? 10)
        if let reservations = fixture["reservations"] as? [[String: Any]] {
            reserveRequest = { offset, isOnline in
                let matched = reservations.filter { ($0["isOnline"] as? Bool ?? false) == isOnline }
                let end = min(offset + size, matched.count)
                let rows = offset < end ? Array(matched[offset..<end]) : []
                return HongguoCollectionPage(
                    items: rows.compactMap { HongguoSubscribeItem(row: $0, isOnlineTab: isOnline) },
                    hasMore: end < matched.count,
                    nextOffset: end
                )
            }
        }
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
        guard officialAccount else { return [] }
        let all = officialLikes.compactMap(\.drama)
        guard !searchQuery.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    public var followedAnchorsList: [Anchor] {
        guard officialAccount else { return [] }
        let all = officialAnchors
        guard !searchQuery.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var reservedList: [HongguoSubscribeItem] {
        guard officialAccount else { return [] }
        let all = selectedReserveOnline ? officialReservedOnline : officialReservedComing
        guard !searchQuery.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    func removeReservation(_ item: HongguoSubscribeItem) async throws {
        if item.isOnline {
            try await HongguoAccountModel.shared.deleteSubscribedDramas([item.itemId], isOnline: true)
            officialReservedOnline.removeAll { $0.key == item.key }
        } else {
            try await HongguoAccountModel.shared.setDramaSubscribed(item.drama, subscribed: false)
            officialReservedComing.removeAll { $0.key == item.key }
        }
        await loadAccount(.reservations, refresh: true)
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
