import Foundation
import Combine

@MainActor
public final class SearchViewModel: ObservableObject {
    public static let defaultHotKeywords = [
        "都市逆袭", "战神归来", "隐忍龙王", "现代甜宠",
        "真假千金", "天降萌宝", "神豪首富", "狂龙出狱",
        "重生复仇", "九龙至尊", "绝品神医", "无双战王"
    ]

    @Published public var query = ""
    @Published public var suggestions: [String] = SearchViewModel.defaultHotKeywords
    @Published public var searchResults: [Drama] = []
    @Published public var isLoading = false
    @Published public var isLoadingMore = false
    @Published public var hasMore = false
    @Published public var hasSearched = false
    @Published public var errorMessage: String?

    public var activeSourceId: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : store.currentSourceId
        return src
    }

    public var historyKeywords: [String] {
        store.searchHistory
    }

    private let repository: NativeRepository
    private let store: LocalStore
    private var page = 0
    private var submittedQuery = ""
    private var submittedSource = ""
    private var generation = 0
    private var debounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    public init(repository: NativeRepository = .shared, store: LocalStore = .shared) {
        self.repository = repository
        self.store = store

        store.$currentSourceId
            .dropFirst()
            .sink { [weak self] source in
                guard let self, source.isEmpty || source.lowercased() != submittedSource.lowercased() else { return }
                generation += 1
                isLoading = false
                isLoadingMore = false
                hasMore = false
                searchResults = []
                suggestions = Self.defaultHotKeywords
                hasSearched = false
                errorMessage = nil
            }
            .store(in: &cancellables)
    }

    public func onQueryChanged(_ newQuery: String) {
        query = newQuery
        debounceTask?.cancel()

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms 防抖
            if !Task.isCancelled {
                await fetchSuggestions(for: newQuery)
            }
        }
    }

    private func fetchSuggestions(for text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // 输入为空时获取热搜词，若失败绝不清空，保留默认精选词
            guard !activeSourceId.isEmpty else {
                if suggestions.isEmpty { suggestions = Self.defaultHotKeywords }
                return
            }
            let source = activeSourceId
            do {
                let loaded = try await repository.loadSuggestions(query: "")
                guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, activeSourceId == source else { return }
                if !loaded.isEmpty {
                    suggestions = loaded
                } else if suggestions.isEmpty {
                    suggestions = Self.defaultHotKeywords
                }
            } catch {
                guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, activeSourceId == source else { return }
                if suggestions.isEmpty {
                    suggestions = Self.defaultHotKeywords
                }
            }
            return
        }

        // 输入非空时获取动态联想词
        guard !activeSourceId.isEmpty else { return }
        let source = activeSourceId
        do {
            let loaded = try await repository.loadSuggestions(query: trimmed)
            guard !Task.isCancelled, query == text, activeSourceId == source else { return }
            let filtered = loaded.isEmpty ? Self.defaultHotKeywords.filter { $0.contains(trimmed) } : loaded
            suggestions = filtered.isEmpty ? Self.defaultHotKeywords : filtered
        } catch {
            guard !Task.isCancelled, query == text, activeSourceId == source else { return }
            let matched = Self.defaultHotKeywords.filter { $0.contains(trimmed) }
            suggestions = matched.isEmpty ? Self.defaultHotKeywords : matched
        }
    }

    public func clearSearch() {
        debounceTask?.cancel()
        query = ""
        searchResults = []
        hasSearched = false
        isLoading = false
        isLoadingMore = false
        hasMore = false
        errorMessage = nil
        suggestions = Self.defaultHotKeywords
        Task {
            await fetchSuggestions(for: "")
        }
    }

    public func executeSearch(keyword: String? = nil) async {
        let target = (keyword ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        debounceTask?.cancel()
        generation += 1
        let ticket = generation
        submittedSource = !activeSourceId.isEmpty ? activeSourceId : "hongguo"
        submittedQuery = target
        query = target
        hasMore = false
        isLoadingMore = false
        isLoading = true
        hasSearched = true
        errorMessage = nil
        store.addSearchKeyword(target)

        await JSSourceService.shared.initialize()
        guard ticket == generation else { return }
        let source = !activeSourceId.isEmpty ? activeSourceId : "hongguo"
        let lowerSource = source.lowercased()
        submittedSource = source
        submittedQuery = target
        do {
            let res = try await repository.loadCatalog(
                source: source,
                page: 1,
                query: target,
                force: true
            )
            guard ticket == generation else { return }
            store.refreshDramas(res.items)
            page = res.page
            submittedQuery = target
            submittedSource = source
            hasMore = res.hasMore
            searchResults = res.items.filter { drama in
                let s = drama.source.lowercased()
                return s.isEmpty || s == lowerSource
            }
        } catch {
            guard ticket == generation else { return }
            errorMessage = error.localizedDescription
            searchResults = []
        }
        isLoading = false
    }

    public func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore, !submittedQuery.isEmpty else { return }
        let ticket = generation
        isLoadingMore = true
        errorMessage = nil
        do {
            let result = try await repository.loadCatalog(source: submittedSource, page: page + 1, query: submittedQuery)
            guard ticket == generation else { return }
            store.refreshDramas(result.items)
            let existing = Set(searchResults.map(\.id))
            searchResults.append(contentsOf: result.items.filter { !existing.contains($0.id) && $0.source.lowercased() == submittedSource.lowercased() })
            page = result.page
            hasMore = result.hasMore
        } catch {
            guard ticket == generation else { return }
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }

    public func clearHistory() {
        store.clearSearchHistory()
    }
}
