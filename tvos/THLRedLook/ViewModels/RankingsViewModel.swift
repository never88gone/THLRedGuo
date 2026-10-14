import Foundation
import Combine

@MainActor
public final class RankingsViewModel: ObservableObject {
    @Published public var boards: [RankingBoard] = []
    @Published public var selectedBoard: RankingBoard?
    @Published public var items: [Drama] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var currentSource: String = ""

    private let repository: NativeRepository
    private var cachedByBoard: [String: [Drama]] = [:]
    private var loadTask: Task<Void, Never>?

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
            self.currentSource = target
            self.cachedByBoard.removeAll()
        }

        guard !target.isEmpty else {
            self.boards = []
            self.selectedBoard = nil
            self.items = []
            return
        }

        let loaded = (try? await repository.loadRankingBoards()) ?? []
        let tvSafeBoards = RankingBoard.filterForTV(loaded)

        // 单源模式：榜单必须严格仅展示当前选中的数据源，彻底隔离未激活的数据源
        let matchingBoards = tvSafeBoards.filter { $0.matches(source: target) }

        if !matchingBoards.isEmpty {
            self.boards = matchingBoards
        } else {
            self.boards = RankingBoard.defaults(for: target).filter(\.isAllowedOnTV)
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
        selectedBoard = board
        if let cached = cachedByBoard[board.id], !cached.isEmpty {
            items = cached
            return
        }
        loadTask?.cancel()
        loadTask = Task {
            await loadRankings()
        }
    }

    public func loadRankings() async {
        guard let board = selectedBoard, board.isAllowedOnTV, !currentSource.isEmpty else {
            items = []
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await repository.loadRankings(board: board.id)
            let sanitized = loaded.filter { drama in
                let s = drama.source.lowercased()
                if s.contains("huangguo") || s == "cloudfront" {
                    return false
                }
                // 确保剧集源严格属于当前数据源或榜单本身对应的数据源，防止跨源混杂
                if !s.isEmpty && s != currentSource && s != board.source.lowercased() {
                    return false
                }
                return true
            }
            items = sanitized
            cachedByBoard[board.id] = sanitized
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
                items = []
            }
        }
        isLoading = false
    }
}

@MainActor
public final class RecommendationsViewModel: ObservableObject {
    public let subCategories = ["真人剧", "漫剧", "AI 剧"]
    @Published public var selectedSubCategory: String = "真人剧"
    @Published public var items: [Drama] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var currentSource: String = ""

    private let repository: NativeRepository
    private var cachedByCategory: [String: [Drama]] = [:]
    private var loadTask: Task<Void, Never>?

    public init(repository: NativeRepository = .shared) {
        self.repository = repository
    }

    public var activeSourceId: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : LocalStore.shared.currentSourceId
        return src
    }

    public func selectSubCategory(_ cat: String) {
        guard selectedSubCategory != cat else { return }
        selectedSubCategory = cat
        guard !activeSourceId.isEmpty else {
            items = []
            return
        }
        let cacheKey = "\(activeSourceId.lowercased()):\(cat)"
        if let cached = cachedByCategory[cacheKey], !cached.isEmpty {
            items = cached
            return
        }
        loadTask?.cancel()
        loadTask = Task {
            await loadRecommendations()
        }
    }

    public func loadRecommendations(forSource source: String? = nil) async {
        let target = (source ?? activeSourceId).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if currentSource != target {
            currentSource = target
            cachedByCategory.removeAll()
        }

        guard !target.isEmpty else {
            items = []
            isLoading = false
            return
        }
        do {
            let loaded: [Drama]
            if target == "hongguo" {
                loaded = try await repository.loadRecommendations(category: selectedSubCategory)
            } else {
                let res = try await repository.loadCatalog(source: target, category: "all", page: 1, query: "", force: false)
                loaded = res.items
            }
            let sanitized = loaded.filter { drama in
                let s = drama.source.lowercased()
                if s.contains("huangguo") || s == "cloudfront" { return false }
                return s.isEmpty || s == target
            }
            items = sanitized
            cachedByCategory["\(target):\(selectedSubCategory)"] = sanitized
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
                items = []
            }
        }
        isLoading = false
    }
}
