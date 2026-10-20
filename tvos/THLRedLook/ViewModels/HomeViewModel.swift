import Foundation
import Combine

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var items: [Drama] = []
    @Published public var categories: [CatalogCategory] = []
    @Published public var selectedCategory: CatalogCategory = .all
    @Published public var selectedSort: CatalogSort = .source
    @Published public var selectedRelease: CatalogReleaseFilter = .all
    @Published public var isLoading = false
    @Published public var isLoadingMore = false
    @Published public var hasMore = false
    @Published public var errorMessage: String?

    private let repository: any DramaSourceProviderProtocol
    private let store: LocalStore
    private var currentPage = 0
    private var generation = 0
    private var cancellables = Set<AnyCancellable>()
    private var selectCategoryTask: Task<Void, Never>?

    public init(repository: any DramaSourceProviderProtocol = NativeRepository.shared, store: LocalStore = .shared) {
        self.repository = repository
        self.store = store
        store.$currentSourceId
            .dropFirst()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.reloadAll() }
            }
            .store(in: &cancellables)
    }

    public var activeSourceId: String {
        !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : store.currentSourceId
    }

    public var availableSources: [SourceSite] {
        SourceSite.visibleValues(unlocked: store.unlockedSources)
    }

    public var currentSource: SourceSite {
        SourceSite.byId(activeSourceId)
    }

    private func resetRequest() {
        generation += 1
        selectCategoryTask?.cancel()
        items = []
        currentPage = 0
        hasMore = false
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
    }

    public func reloadAll(initialCategory: String? = nil) async {
        resetRequest()
        let ticket = generation
        let source = activeSourceId
        guard !source.isEmpty else { categories = []; return }
        isLoading = true
        do {
            let list = try await repository.loadCategories(source: source)
            guard !Task.isCancelled, generation == ticket, activeSourceId == source else { return }
            categories = list
            selectedCategory = list.first(where: { $0.id == initialCategory || $0.name == initialCategory })
                ?? list.first(where: { $0.id == selectedCategory.id }) ?? list.first ?? .all
        } catch {
            guard !Task.isCancelled, generation == ticket, activeSourceId == source else { return }
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }
        await loadFirstPage()
    }

    public func selectCategory(_ category: CatalogCategory, immediate: Bool = false) {
        guard selectedCategory.id != category.id else { return }
        resetRequest()
        selectedCategory = category
        isLoading = true
        selectCategoryTask = Task {
            if !immediate { try? await Task.sleep(nanoseconds: 180_000_000) }
            guard !Task.isCancelled else { return }
            await loadFirstPage()
        }
    }

    public func selectSort(_ sort: CatalogSort) async {
        guard selectedSort != sort else { return }
        selectedSort = sort
        await loadFirstPage()
    }

    public func selectReleaseFilter(_ filter: CatalogReleaseFilter) async {
        guard selectedRelease != filter else { return }
        selectedRelease = filter
        await loadFirstPage()
    }

    public func loadFirstPage() async {
        generation += 1
        let ticket = generation
        let source = activeSourceId
        let category = selectedCategory.id
        items = []
        currentPage = 0
        hasMore = false
        isLoadingMore = false
        errorMessage = nil
        guard !source.isEmpty else { isLoading = false; return }
        isLoading = true
        defer { if generation == ticket { isLoading = false } }
        do {
            let result = try await repository.loadCatalog(source: source, category: category, page: 1, query: "", force: true)
            guard !Task.isCancelled, generation == ticket, activeSourceId == source,
                  selectedCategory.id == category else { return }
            store.refreshDramas(result.items)
            items = filterAndSort(dramas: result.items)
            currentPage = result.page
            hasMore = result.hasMore
        } catch {
            guard !Task.isCancelled, generation == ticket, activeSourceId == source,
                  selectedCategory.id == category else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func retry() async {
        if items.isEmpty { await reloadAll() }
        else {
            errorMessage = nil
            await loadNextPage()
        }
    }

    public func loadNextPage() async {
        guard !isLoading, !isLoadingMore, hasMore, errorMessage == nil else { return }
        let ticket = generation
        let source = activeSourceId
        let category = selectedCategory.id
        let page = currentPage + 1
        isLoadingMore = true
        defer { if generation == ticket { isLoadingMore = false } }
        do {
            let result = try await repository.loadCatalog(source: source, category: category, page: page, query: "", force: false)
            guard !Task.isCancelled, generation == ticket, activeSourceId == source,
                  selectedCategory.id == category else { return }
            store.refreshDramas(result.items)
            var seen = Set(items.map(\.id))
            items.append(contentsOf: filterAndSort(dramas: result.items).filter { seen.insert($0.id).inserted })
            hasMore = result.hasMore
            currentPage = result.page
        } catch {
            guard !Task.isCancelled, generation == ticket, activeSourceId == source,
                  selectedCategory.id == category else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func filterAndSort(dramas: [Drama]) -> [Drama] {
        let target = activeSourceId.lowercased()
        var result = dramas.filter { $0.source.isEmpty || $0.source.lowercased() == target }
        if selectedRelease != .all {
            result = result.filter { $0.releaseStatus.lowercased() == selectedRelease.rawValue }
        }
        switch selectedSort {
        case .source: break
        case .latest: result.sort { $0.onlineDate > $1.onlineDate }
        case .heat: result.sort { (Int($0.heat) ?? 0) > (Int($1.heat) ?? 0) }
        case .views: result.sort { $0.views > $1.views }
        case .title: result.sort { $0.title < $1.title }
        }
        return result
    }
}
