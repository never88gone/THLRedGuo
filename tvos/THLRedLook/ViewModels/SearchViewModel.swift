import Foundation
import Combine

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var query = ""
    @Published public var suggestions: [String] = []
    @Published public var searchResults: [Drama] = []
    @Published public var isLoading = false
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
    private var debounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    public init(repository: NativeRepository = .shared, store: LocalStore = .shared) {
        self.repository = repository
        self.store = store

        store.$currentSourceId
            .dropFirst()
            .sink { [weak self] _ in
                self?.searchResults = []
                self?.suggestions = []
                self?.hasSearched = false
                self?.errorMessage = nil
            }
            .store(in: &cancellables)
    }

    public func onQueryChanged(_ newQuery: String) {
        query = newQuery
        debounceTask?.cancel()
        guard !newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            suggestions = []
            return
        }

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms 防抖
            if !Task.isCancelled {
                await fetchSuggestions(for: newQuery)
            }
        }
    }

    private func fetchSuggestions(for text: String) async {
        guard !activeSourceId.isEmpty else {
            suggestions = []
            return
        }
        do {
            suggestions = try await repository.loadSuggestions(query: text)
        } catch {
            suggestions = []
        }
    }

    public func executeSearch(keyword: String? = nil) async {
        let target = (keyword ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !activeSourceId.isEmpty else { return }
        query = target
        suggestions = []
        isLoading = true
        hasSearched = true
        errorMessage = nil
        store.addSearchKeyword(target)

        let source = activeSourceId
        let lowerSource = source.lowercased()
        do {
            let res = try await repository.loadCatalog(
                source: source,
                page: 1,
                query: target,
                force: true
            )
            searchResults = res.items.filter { drama in
                let s = drama.source.lowercased()
                return s.isEmpty || s == lowerSource
            }
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }
        isLoading = false
    }

    public func clearHistory() {
        store.clearSearchHistory()
    }
}
