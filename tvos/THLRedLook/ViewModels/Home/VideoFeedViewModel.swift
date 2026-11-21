import Foundation
import Combine
import AVFoundation

@MainActor
public final class VideoFeedViewModel: ObservableObject {
    @Published public private(set) var items: [VideoFeedItem] = []
    @Published public private(set) var currentIndex = 0
    @Published public private(set) var page = 0
    @Published public private(set) var hasMore = true
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var needsRefresh = false

    // 预热与预解析缓存
    @Published public private(set) var feedPlans: [String: PlaybackPlan] = [:]
    @Published public private(set) var feedEpisodes: [String: [Episode]] = [:]
    private var resolvingTasks: [String: Task<PlaybackPlan?, Never>] = [:]
    private var decryptedURLs: [String: URL] = [:]

    private var session = UUID().uuidString
    private var generation = 0
    private var pageTask: Task<Void, Never>?
    private let preloadEnabled: Bool
    private let loadPage: (Int, String) async throws -> VideoFeedPage

    public init(preloadEnabled: Bool = true, loadPage: @escaping (Int, String) async throws -> VideoFeedPage = { page, session in
        try await NativeRepository.shared.loadVideoFeed(page: page, session: session)
    }) {
        self.preloadEnabled = preloadEnabled
        self.loadPage = loadPage
    }

    public var current: VideoFeedItem? { items.indices.contains(currentIndex) ? items[currentIndex] : nil }
    public var canGoPrevious: Bool { currentIndex > 0 }
    public var canGoNext: Bool { currentIndex + 1 < items.count || hasMore }

    public func start() async {
        if items.isEmpty && !needsRefresh { errorMessage = nil }
        var emptyPages = 0
        while items.isEmpty && hasMore && errorMessage == nil && emptyPages < 3 {
            await loadMore()
            emptyPages += 1
        }
        if items.isEmpty && errorMessage == nil {
            errorMessage = "暂时没有可播放的推荐，请重试或换一批"
        }
        if items.count < 3 { prefetch() }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self else { return }
            self.preloadAround(index: self.currentIndex)
        }
    }

    public func refresh() async {
        generation += 1
        pageTask?.cancel()
        pageTask = nil
        for (_, task) in resolvingTasks { task.cancel() }
        resolvingTasks.removeAll()
        cleanupDecryptedFiles()
        feedPlans.removeAll()
        feedEpisodes.removeAll()
        VideoCacheManager.shared.clearNamespace("feed")

        isLoading = false
        session = UUID().uuidString
        items = []
        currentIndex = 0
        page = 0
        hasMore = true
        needsRefresh = false
        errorMessage = nil
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
        if currentIndex + 1 < items.count {
            currentIndex += 1
            trimSlidingWindow(around: currentIndex)
            preloadAround(index: currentIndex)
        } else if hasMore && errorMessage == nil {
            errorMessage = "暂未返回新的推荐，请重试或换一批"
        }
        prefetch()
    }

    public func previous() {
        guard canGoPrevious else { return }
        currentIndex -= 1
        trimSlidingWindow(around: currentIndex)
        preloadAround(index: currentIndex)
    }

    public func retry() async {
        if needsRefresh || (items.isEmpty && !hasMore) { await refresh() }
        else if items.isEmpty { await start() }
        else { await loadMore() }
    }

    private func prefetch() {
        guard errorMessage == nil, items.count - currentIndex <= 8, hasMore else { return }
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
                let newItems = result.items.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
                items.append(contentsOf: newItems)
                page = result.page
                hasMore = result.hasMore
                if items.isEmpty && !hasMore { errorMessage = "暂时没有可播放的推荐，请刷新重试" }

                // 新数据追加后延迟预热
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard let self else { return }
                    self.preloadAround(index: self.currentIndex)
                }
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

    // MARK: - 全链路异步预解析与预热缓冲 (Preload Pipeline)

    private func trimSlidingWindow(around index: Int) {
        guard !items.isEmpty else { return }
        let keepWindowStart = max(0, index - 2)
        let keepWindowEnd = min(items.count - 1, index + 3)
        guard keepWindowStart <= keepWindowEnd else { return }

        let keepIds = Set(items[keepWindowStart...keepWindowEnd].map(\.id))

        for (id, task) in resolvingTasks where !keepIds.contains(id) {
            task.cancel()
            resolvingTasks.removeValue(forKey: id)
        }
        for (id, url) in decryptedURLs where !keepIds.contains(id) {
            CENCMP4Decryptor.shared.removePlaybackCache(at: url)
            decryptedURLs.removeValue(forKey: id)
        }
        for id in Array(feedPlans.keys) where !keepIds.contains(id) {
            feedPlans.removeValue(forKey: id)
            feedEpisodes.removeValue(forKey: id)
        }
    }

    public func preloadAround(index: Int) {
        guard preloadEnabled, index >= 0 && index < items.count else { return }
        trimSlidingWindow(around: index)
        // 关键：当前项(index)由前台 TVPlayerView 直接独占解析与起播，后台仅预热下一部(1)
        // 彻底杜绝前后台双向重复解析同一部短剧导致红果官方接口 429 风控与连接池/解码器竞争
        let offsets = [1]
        for offset in offsets {
            let targetIdx = index + offset
            guard targetIdx >= 0 && targetIdx < items.count else { continue }
            let item = items[targetIdx]
            if feedPlans[item.id] == nil && resolvingTasks[item.id] == nil {
                Task {
                    _ = await resolveAndPreload(item: item)
                }
            }
        }
    }

    public func resolveAndPreload(item: VideoFeedItem) async -> PlaybackPlan? {
        if let existing = feedPlans[item.id] {
            return existing
        }
        if let task = resolvingTasks[item.id] {
            return await task.value
        }

        let dramaId = item.id
        let task = Task { [weak self] () -> PlaybackPlan? in
            guard let self else { return nil }
            do {
                let detail = try await NativeRepository.preloading.loadDetail(drama: item.drama, store: LocalStore.shared)
                let episodes = detail.episodes
                let targetEpisode = episodes.first { $0.number == item.episode } ?? episodes.first
                let targetIndex = targetEpisode?.number ?? item.episode

                let resolved = try await NativeRepository.preloading.resolvePlayback(
                    drama: detail.drama,
                    episode: targetEpisode,
                    episodeIndex: targetIndex,
                    quality: 0
                )
                guard !Task.isCancelled else { return nil }

                let prepared = try await PlaybackAssetFactory.prepare(resolved)
                guard !Task.isCancelled else {
                    if let local = prepared.decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: local) }
                    return nil
                }
                if let local = prepared.decryptedURL { self.decryptedURLs[dramaId] = local }
                self.feedEpisodes[dramaId] = episodes
                self.feedPlans[dramaId] = resolved
                VideoCacheManager.shared.preload(asset: prepared.asset, for: resolved.url, namespace: "feed")
                let effectivePlan = resolved

                return effectivePlan
            } catch {
                return nil
            }
        }

        resolvingTasks[dramaId] = task
        let result = await task.value
        resolvingTasks.removeValue(forKey: dramaId)
        return result
    }

    private func cleanupDecryptedFiles() {
        let urls = Array(decryptedURLs.values)
        decryptedURLs.removeAll()
        Self.removeDecryptedFiles(urls)
    }

    nonisolated private static func removeDecryptedFiles(_ urls: [URL]) {
        for url in urls {
            CENCMP4Decryptor.shared.removePlaybackCache(at: url)
        }
    }

    deinit {
        let urls = Array(decryptedURLs.values)
        Self.removeDecryptedFiles(urls)
    }
}
