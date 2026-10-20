import Foundation
import Combine

@MainActor
public final class RankingsViewModel: ObservableObject {
    @Published public var boards: [RankingBoard] = []
    @Published public var selectedBoard: RankingBoard?
    @Published public var items: [Drama] = []
    @Published public var isLoading = false
    @Published public var isLoadingMore = false
    @Published public var hasMore = false
    @Published public var errorMessage: String?
    @Published public var currentSource: String = ""
    @Published public var ranks: [String: Int] = [:]

    private let repository: NativeRepository
    private var cachedByBoard: [String: DiscoveryPage<RankedDrama>] = [:]
    private var page = 0
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    public init(repository: NativeRepository = .shared) {
        self.repository = repository
        self.boards = []
        self.selectedBoard = nil
        self.items = []
        self.currentSource = ""
    }

    public func loadBoards(forSource source: String? = nil) async {
        let activeSource: String
        if let s = source, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activeSource = s
        } else if !JSSourceService.shared.activeSourceId.isEmpty {
            activeSource = JSSourceService.shared.activeSourceId
        } else if !LocalStore.shared.currentSourceId.isEmpty {
            activeSource = LocalStore.shared.currentSourceId
        } else {
            activeSource = ""
        }

        let target = activeSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if self.currentSource != target {
            generation += 1
            loadTask?.cancel()
            self.currentSource = target
            self.cachedByBoard.removeAll()
            ranks = [:]
            items = []
            selectedBoard = nil
        }

        guard !target.isEmpty else {
            self.boards = []
            self.selectedBoard = nil
            self.items = []
            return
        }

        generation += 1
        let ticket = generation
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        defer { if generation == ticket { isLoading = false } }
        let loaded: [RankingBoard]
        do {
            loaded = try await repository.loadRankingBoards()
        } catch {
            guard !Task.isCancelled, generation == ticket, currentSource == target else { return }
            errorMessage = error.localizedDescription
            boards = []
            selectedBoard = nil
            items = []
            return
        }
        guard !Task.isCancelled, generation == ticket, currentSource == target else { return }
        let tvSafeBoards = RankingBoard.filterForTV(loaded)

        // 单源模式：榜单必须严格仅展示当前选中的数据源，彻底隔离未激活的数据源
        let matchingBoards = tvSafeBoards.filter { $0.matches(source: target) }

        if !matchingBoards.isEmpty {
            self.boards = matchingBoards
        } else {
            self.boards = []
        }

        if let cur = self.selectedBoard, self.boards.contains(where: { $0.id == cur.id }) {
            // 保持当前
        } else {
            self.selectedBoard = self.boards.first
        }
    }

    public func selectBoard(_ board: RankingBoard) {
        guard board.isAllowedOnTV else { return }
        guard selectedBoard?.id != board.id else { return }
        generation += 1
        loadTask?.cancel()
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        selectedBoard = board
        if let cached = cachedByBoard[board.id] {
            apply(cached)
            return
        }
        items = []
        ranks = [:]
        hasMore = false
        loadTask?.cancel()
        loadTask = Task {
            await loadRankings()
        }
    }

    private func apply(_ result: DiscoveryPage<RankedDrama>) {
        items = result.items.map(\.drama)
        ranks = Dictionary(result.items.map { ($0.drama.id, $0.rank) }, uniquingKeysWith: { _, last in last })
        page = result.page
        hasMore = result.hasMore
    }

    public func loadMore() async {
        guard errorMessage == nil else { return }
        await loadRankings(more: true)
    }

    public func loadRankings(more: Bool = false) async {
        guard let board = selectedBoard, board.isAllowedOnTV, !currentSource.isEmpty else {
            items = []
            isLoading = false
            isLoadingMore = false
            hasMore = false
            return
        }
        if more && (!hasMore || isLoading || isLoadingMore) { return }
        generation += 1
        let ticket = generation
        let target = currentSource
        isLoading = !more
        isLoadingMore = more
        errorMessage = nil
        defer {
            if generation == ticket {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let result = try await repository.loadRankingPage(board: board.id, page: more ? page + 1 : 1)
            guard !Task.isCancelled, generation == ticket, currentSource == target else { return }
            let sanitized = result.items.filter {
                $0.drama.source.isEmpty || $0.drama.source.lowercased() == target
            }
            let previous = more ? cachedByBoard[board.id]?.items ?? [] : []
            var seen = Set<String>()
            let combined = (previous + sanitized).filter { seen.insert($0.drama.id).inserted }
            let loaded = DiscoveryPage(items: combined, page: result.page, hasMore: result.hasMore)
            cachedByBoard[board.id] = loaded
            apply(loaded)
        } catch {
            guard !Task.isCancelled, generation == ticket else { return }
            errorMessage = error.localizedDescription
            if !more { items = []; hasMore = false }
        }
    }

}

@MainActor
public final class RecommendationsViewModel: ObservableObject {
    public let subCategories = ["真人剧", "漫剧", "AI 剧"]
    @Published public var selectedSubCategory: String = "真人剧"
    @Published public var items: [Drama] = []
    @Published public var isLoading = false
    @Published public var isLoadingMore = false
    @Published public var hasMore = false
    @Published public var errorMessage: String?
    @Published public var currentSource: String = ""

    private let repository: NativeRepository
    private var cachedByCategory: [String: DiscoveryPage<Drama>] = [:]
    private var page = 0
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    public init(repository: NativeRepository = .shared) {
        self.repository = repository
    }

    public var activeSourceId: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : LocalStore.shared.currentSourceId
        return src
    }

    public func selectSubCategory(_ cat: String) {
        guard selectedSubCategory != cat else { return }
        generation += 1
        loadTask?.cancel()
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        selectedSubCategory = cat
        guard !activeSourceId.isEmpty else {
            items = []
            return
        }
        let cacheKey = "\(activeSourceId.lowercased()):\(cat)"
        if let cached = cachedByCategory[cacheKey] {
            apply(cached)
            return
        }
        items = []
        hasMore = false
        loadTask?.cancel()
        loadTask = Task {
            await loadRecommendations()
        }
    }

    private func apply(_ result: DiscoveryPage<Drama>) {
        items = result.items
        page = result.page
        hasMore = result.hasMore
    }

    public func loadMore() async {
        guard errorMessage == nil else { return }
        await loadRecommendations(more: true)
    }

    public func loadRecommendations(forSource source: String? = nil, more: Bool = false) async {
        let target = (source ?? activeSourceId).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if currentSource != target {
            generation += 1
            currentSource = target
            cachedByCategory.removeAll()
            items = []
            hasMore = false
        }
        guard !target.isEmpty else {
            items = []
            isLoading = false
            isLoadingMore = false
            hasMore = false
            return
        }
        if more && (!hasMore || isLoading || isLoadingMore) { return }
        generation += 1
        let ticket = generation
        let category = selectedSubCategory
        let cacheKey = "\(target):\(category)"
        isLoading = !more
        isLoadingMore = more
        errorMessage = nil
        defer {
            if generation == ticket {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let result: DiscoveryPage<Drama>
            if target == "hongguo" {
                result = try await repository.loadRecommendationPage(category: category, page: more ? page + 1 : 1)
            } else {
                let loaded = try await repository.loadCatalog(source: target, category: "all", page: more ? page + 1 : 1, query: "", force: false)
                result = DiscoveryPage(items: loaded.items, page: loaded.page, hasMore: loaded.hasMore)
            }
            guard !Task.isCancelled, generation == ticket, currentSource == target, selectedSubCategory == category else { return }
            let sanitized = result.items.filter { $0.source.isEmpty || $0.source.lowercased() == target }
            let previous = more ? cachedByCategory[cacheKey]?.items ?? [] : []
            var seen = Set<String>()
            let combined = (previous + sanitized).filter { seen.insert($0.id).inserted }
            let loaded = DiscoveryPage(items: combined, page: result.page, hasMore: result.hasMore)
            cachedByCategory[cacheKey] = loaded
            apply(loaded)
        } catch {
            guard !Task.isCancelled, generation == ticket else { return }
            errorMessage = error.localizedDescription
            if !more { items = []; hasMore = false }
        }
    }
}
