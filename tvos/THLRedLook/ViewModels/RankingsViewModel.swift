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
        isLoadingMore = false
        errorMessage = nil
        selectedBoard = board
        if let cached = cachedByBoard[board.id] {
            isLoading = false
            apply(cached)
            return
        }
        // 平滑切换：不粗暴清空 items，保留旧数据展示，杜绝下方视图瞬时坍塌导致焦点丢失
        isLoading = true
        hasMore = false
        loadTask = Task {
            await loadRankings()
        }
    }

    private func apply(_ result: DiscoveryPage<RankedDrama>) {
        items = result.items.map(\.drama)
        ranks = Dictionary(result.items.enumerated().map { index, item in
            (item.drama.id, item.rank > 0 ? item.rank : (index + 1))
        }, uniquingKeysWith: { first, _ in first })
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
            var seen = Set(previous.map(\.drama.id))
            var nextItems = previous
            for item in sanitized {
                if seen.insert(item.drama.id).inserted {
                    let rank = nextItems.count + 1
                    nextItems.append(RankedDrama(rank: rank, drama: item.drama, metric: item.metric))
                }
            }
            let loaded = DiscoveryPage(items: nextItems, page: result.page, hasMore: result.hasMore)
            cachedByBoard[board.id] = loaded
            apply(loaded)

            // 电视大屏榜单优化：首次呈现后在后台静默补充第 2 页，扩充排行榜深度，不阻塞首屏交互
            if !more && nextItems.count < 40 && result.hasMore {
                Task {
                    if let nextResult = try? await repository.loadRankingPage(board: board.id, page: 2) {
                        guard !Task.isCancelled, generation == ticket, currentSource == target else { return }
                        let nextSanitized = nextResult.items.filter {
                            $0.drama.source.isEmpty || $0.drama.source.lowercased() == target
                        }
                        var merged = nextItems
                        for item in nextSanitized {
                            if seen.insert(item.drama.id).inserted {
                                let rank = merged.count + 1
                                merged.append(RankedDrama(rank: rank, drama: item.drama, metric: item.metric))
                            }
                        }
                        let updated = DiscoveryPage(items: merged, page: nextResult.page, hasMore: nextResult.hasMore)
                        cachedByBoard[board.id] = updated
                        apply(updated)
                    }
                }
            }
        } catch {
            guard !Task.isCancelled, generation == ticket else { return }
            errorMessage = error.localizedDescription
            if !more { items = []; hasMore = false }
        }
    }

}
