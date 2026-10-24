import XCTest
@testable import THLRedLook

@MainActor
private final class ListLoadingProvider: DramaSourceProviderProtocol {
    typealias Page = (items: [Drama], hasMore: Bool, page: Int)
    var categoriesPending: CheckedContinuation<[CatalogCategory], Error>?
    var pagePending: CheckedContinuation<Page, Error>?
    var holdCategories = false
    var holdPage = false
    var failCategories = false
    var requests: [Int] = []
    let categories = [CatalogCategory(id: "app:discover:all", name: "全部")]

    func loadCategories(source: String) async throws -> [CatalogCategory] {
        if holdCategories { return try await withCheckedThrowingContinuation { categoriesPending = $0 } }
        if failCategories { throw SourceAPIError.sourceUnavailable("合成分类失败") }
        return categories
    }
    func loadCatalog(source: String, category: String, page: Int, query: String, force: Bool) async throws -> Page {
        requests.append(page)
        if holdPage && page == 2 { return try await withCheckedThrowingContinuation { pagePending = $0 } }
        return response(page)
    }
    func response(_ page: Int) -> Page {
        ([Drama(id: "hongguo:synthetic-\(page)", source: "hongguo", title: "合成短剧\(page)")], page < 3, page)
    }
    func loadSuggestions(query: String) async throws -> [String] { [] }
    func loadDetail(drama: Drama) async throws -> DramaDetail { throw SourceAPIError.coreUninitialized }
    func loadRankingBoards() async throws -> [RankingBoard] { [] }
    func loadRankings(board: String, page: Int) async throws -> [Drama] { [] }
    func loadRecommendations(category: String) async throws -> [Drama] { [] }
}

@MainActor
final class ListLoadingTests: XCTestCase {
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }

    private func store() -> LocalStore {
        let name = "THLRedLook.QA.ListLoading." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return LocalStore(defaults: defaults)
    }

    func testFirstBatchDisplaysWhileCategoryMetadataIsPending() async {
        let provider = ListLoadingProvider()
        provider.holdCategories = true
        let model = HomeViewModel(repository: provider, store: store())
        let reload = Task { await model.reloadAll() }
        await eventually { provider.categoriesPending != nil && !model.items.isEmpty }
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(provider.requests, [1])
        provider.categoriesPending?.resume(returning: provider.categories)
        await reload.value
        XCTAssertEqual(model.categories, provider.categories)
    }

    func testCategoryFailureDoesNotDiscardFirstBatch() async {
        let provider = ListLoadingProvider()
        provider.failCategories = true
        let model = HomeViewModel(repository: provider, store: store())
        await model.reloadAll()
        XCTAssertEqual(model.items.map(\.id), ["hongguo:synthetic-1"])
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.categories.isEmpty)
    }

    func testAutomaticAndRemotePagingShareOneRequest() async {
        let provider = ListLoadingProvider()
        let model = HomeViewModel(repository: provider, store: store())
        await model.reloadAll()
        provider.holdPage = true
        let first = Task { await model.loadNextPage() }
        await eventually { provider.pagePending != nil }
        await model.loadNextPage()
        XCTAssertEqual(provider.requests, [1, 2])
        provider.pagePending?.resume(returning: provider.response(2))
        await first.value
        XCTAssertEqual(model.items.map(\.id), ["hongguo:synthetic-1", "hongguo:synthetic-2"])
        XCTAssertFalse(model.isLoadingMore)
    }

    func testSmallFeedFirstBatchDisplaysWhileNextPageIsPending() async {
        var pending: CheckedContinuation<VideoFeedPage, Never>?
        var requested: [Int] = []
        let model = VideoFeedViewModel(preloadEnabled: false) { page, _ in
            requested.append(page)
            if page == 1 {
                return VideoFeedPage(items: [VideoFeedItem(drama: Drama(id: "first", title: "合成推荐"), episode: 1, position: 0)], page: 1, hasMore: true)
            }
            return await withCheckedContinuation { pending = $0 }
        }
        await model.start()
        XCTAssertEqual(model.current?.id, "first")
        await eventually { pending != nil }
        XCTAssertEqual(requested, [1, 2])
        XCTAssertEqual(model.items.count, 1)
        pending?.resume(returning: VideoFeedPage(items: [VideoFeedItem(drama: Drama(id: "second", title: "合成推荐二"), episode: 1, position: 0)], page: 2, hasMore: false))
        await eventually { !model.isLoading }
        await model.next()
        XCTAssertEqual(model.current?.id, "second")
    }
    func testFeedInitialFailureAndExpiredCursorCanRetry() async {
        for code in ["NETWORK", "CURSOR_EXPIRED"] {
            var attempts = 0
            let model = VideoFeedViewModel(preloadEnabled: false) { page, _ in
                attempts += 1
                if attempts == 1 { throw NSError(domain: "fixture", code: 1, userInfo: ["sourceErrorCode": code]) }
                return VideoFeedPage(items: [VideoFeedItem(drama: Drama(id: "recovered", title: "合成恢复"), episode: 1, position: 0)], page: 1, hasMore: false)
            }
            await model.start()
            XCTAssertNotNil(model.errorMessage)
            await model.retry()
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.current?.id, "recovered")
            XCTAssertEqual(attempts, 2)
        }
    }

    func testCategoryMetadataNormalizationDoesNotDiscardPendingPage() async {
        let provider = ListLoadingProvider()
        provider.holdCategories = true
        let model = HomeViewModel(repository: provider, store: store())
        let reload = Task { await model.reloadAll() }
        await eventually { provider.categoriesPending != nil && !model.items.isEmpty }
        provider.holdPage = true
        let more = Task { await model.loadNextPage() }
        await eventually { provider.pagePending != nil }
        provider.categoriesPending?.resume(returning: provider.categories)
        await reload.value
        XCTAssertEqual(model.selectedCategory.id, "app:discover:all")
        provider.pagePending?.resume(returning: provider.response(2))
        await more.value
        XCTAssertEqual(model.items.count, 2)
        XCTAssertFalse(model.isLoadingMore)
    }

    func testUnpreparedFeedDramaDoesNotReusePreviousEpisodeList() async {
        let old = Drama(id: "test_feed_old", title: "合成旧推荐")
        let next = Drama(id: "test_feed_next", title: "合成新推荐")
        let model = PlayerViewModel(drama: old, allEpisodes: [Episode(id: "old-episode", title: "旧分集", number: 1)], store: store())
        await model.switchFeedDrama(drama: next)
        XCTAssertEqual(model.drama.id, next.id)
        XCTAssertTrue(model.allEpisodes.isEmpty)
        model.onDisappear()
    }

    func testRepeatedSourcePublicationDoesNotRestartCatalogCursor() async {
        let provider = ListLoadingProvider()
        let storage = store()
        let model = HomeViewModel(repository: provider, store: storage)
        await model.reloadAll()
        storage.currentSourceId = "hongguo"
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(provider.requests, [1])
        await model.loadNextPage()
        XCTAssertEqual(provider.requests, [1, 2])
    }
}
