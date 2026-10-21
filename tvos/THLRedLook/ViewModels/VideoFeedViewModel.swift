import Foundation
import Combine

public struct VideoFeedItem: Decodable, Identifiable {
    public let drama: Drama
    public let episode: Int
    public let position: Double
    public var id: String { drama.id }
}

public struct VideoFeedPage: Decodable {
    public let items: [VideoFeedItem]
    public let page: Int
    public let hasMore: Bool
}

@MainActor
public final class VideoFeedViewModel: ObservableObject {
    @Published public private(set) var items: [VideoFeedItem] = []
    @Published public private(set) var currentIndex = 0
    @Published public private(set) var page = 0
    @Published public private(set) var hasMore = true
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var needsRefresh = false
    private var session = UUID().uuidString
    private var generation = 0
    private var pageTask: Task<Void, Never>?
    private let loadPage: (Int, String) async throws -> VideoFeedPage

    public init(loadPage: @escaping (Int, String) async throws -> VideoFeedPage = { page, session in
        try await NativeRepository.shared.loadVideoFeed(page: page, session: session)
    }) {
        self.loadPage = loadPage
    }

    public var current: VideoFeedItem? { items.indices.contains(currentIndex) ? items[currentIndex] : nil }
    public var canGoPrevious: Bool { currentIndex > 0 }
    public var canGoNext: Bool { currentIndex + 1 < items.count || hasMore }

    public func start() async {
        var attempts = 0
        while items.isEmpty && hasMore && attempts < 3 {
            await loadMore()
            attempts += 1
            if errorMessage != nil { break }
        }
        if items.isEmpty && errorMessage == nil { errorMessage = "暂时没有可播放的推荐，请重试或换一批" }
        prefetch()
    }

    public func refresh() async {
        generation += 1
        pageTask?.cancel()
        pageTask = nil
        isLoading = false
        session = UUID().uuidString
        items = []
        currentIndex = 0
        page = 0
        hasMore = true
        needsRefresh = false
        await start()
    }

    public func next() async {
        guard canGoNext else { return }
        if currentIndex + 1 >= items.count {
            if needsRefresh { await refresh(); return }
            errorMessage = nil
        }
        let requestedIndex = currentIndex
        let requestGeneration = generation
        var emptyPages = 0
        while currentIndex + 1 >= items.count && hasMore && errorMessage == nil && emptyPages < 3 {
            await loadMore()
            guard requestGeneration == generation, currentIndex == requestedIndex else { return }
            emptyPages += 1
        }
        guard requestGeneration == generation, currentIndex == requestedIndex else { return }
        if currentIndex + 1 < items.count { currentIndex += 1 }
        else if hasMore && errorMessage == nil { errorMessage = "暂未返回新的推荐，请重试或换一批" }
        prefetch()
    }

    public func previous() {
        guard canGoPrevious else { return }
        currentIndex -= 1
    }

    public func retry() async {
        if needsRefresh || (items.isEmpty && !hasMore) { await refresh() }
        else if items.isEmpty { await start() }
        else { await loadMore() }
    }

    private func prefetch() {
        guard errorMessage == nil, items.count - currentIndex <= 3, hasMore else { return }
        Task { await loadMore() }
    }

    public func loadMore() async {
        if let task = pageTask { await task.value; return }
        guard hasMore, !needsRefresh else { return }
        let requestGeneration = generation
        let requestedPage = page + 1
        let scope = session
        isLoading = true
        errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await loadPage(requestedPage, scope)
                guard !Task.isCancelled, generation == requestGeneration else { return }
                var seen = Set(items.map(\.id))
                items.append(contentsOf: result.items.filter { !$0.id.isEmpty && seen.insert($0.id).inserted })
                page = result.page
                hasMore = result.hasMore
                if items.isEmpty && !hasMore { errorMessage = "暂时没有可播放的推荐，请刷新重试" }
            } catch {
                guard !Task.isCancelled, generation == requestGeneration else { return }
                let code = (error as NSError).userInfo["sourceErrorCode"] as? String ?? ""
                needsRefresh = code == "CURSOR_EXPIRED" || code == "MISSING_CURSOR"
                errorMessage = needsRefresh ? "推荐已过期，请刷新获取新内容" : error.localizedDescription
            }
        }
        pageTask = task
        await task.value
        guard generation == requestGeneration else { return }
        pageTask = nil
        isLoading = false
    }
}
