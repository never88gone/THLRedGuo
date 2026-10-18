import Foundation
import Combine

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var items: [Drama] = []
    @Published public var categories: [CatalogCategory] = [CatalogCategory.all]
    @Published public var selectedCategory: CatalogCategory = CatalogCategory.all
    @Published public var selectedSort: CatalogSort = .source
    @Published public var selectedRelease: CatalogReleaseFilter = .all
    @Published public var isLoading = false
    @Published public var isLoadingMore = false
    @Published public var hasMore = true
    @Published public var errorMessage: String?

    private let repository: NativeRepository
    private let store: LocalStore
    private var currentPage = 1
    private var cancellables = Set<AnyCancellable>()
    private var selectCategoryTask: Task<Void, Never>?
    private var loadFirstPageTask: Task<Void, Never>?
    private var cachedByCategory: [String: [Drama]] = [:]

    public init(repository: NativeRepository = .shared, store: LocalStore = .shared) {
        self.repository = repository
        self.store = store

        // 监听站源切换
        store.$currentSourceId
            .dropFirst()
            .sink { [weak self] _ in
                self?.cachedByCategory.removeAll()
                Task { [weak self] in
                    await self?.reloadAll()
                }
            }
            .store(in: &cancellables)
    }

    public var activeSourceId: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : store.currentSourceId
        return src
    }

    public var availableSources: [SourceSite] {
        SourceSite.visibleValues(unlocked: store.unlockedSources)
    }

    public var currentSource: SourceSite {
        SourceSite.byId(activeSourceId)
    }

    public func reloadAll() async {
        NSLog("🎬 [HomeVM] reloadAll 调用, activeSourceId='%@'", activeSourceId)
        cachedByCategory.removeAll()
        items.removeAll()
        guard !activeSourceId.isEmpty else {
            categories = [CatalogCategory.all]
            isLoading = false
            return
        }
        await loadCategories()
        await loadFirstPage()
    }

    public func loadCategories() async {
        guard !activeSourceId.isEmpty else {
            categories = [CatalogCategory.all]
            return
        }
        do {
            NSLog("🎬 [HomeVM] 正在请求分类...")
            let list = try await repository.loadCategories(source: activeSourceId)
            NSLog("🎬 [HomeVM] 分类请求成功: %ld 个", list.count)
            categories = list
            if !categories.contains(where: { $0.id == selectedCategory.id }) {
                selectedCategory = CatalogCategory.all
            }
        } catch {
            NSLog("🎬 [HomeVM] 分类请求失败: %@", error.localizedDescription)
            categories = [CatalogCategory.all]
        }
    }

    public func selectCategory(_ cat: CatalogCategory, immediate: Bool = false) {
        guard selectedCategory.id != cat.id else { return }
        selectedCategory = cat
        if let cached = cachedByCategory[cat.id], !cached.isEmpty {
            items = cached
            return
        }
        selectCategoryTask?.cancel()
        selectCategoryTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            guard !Task.isCancelled else { return }
            await loadFirstPage()
        }
    }

    public func selectSort(_ sort: CatalogSort) async {
        guard selectedSort != sort else { return }
        selectedSort = sort
        cachedByCategory.removeAll()
        await loadFirstPage()
    }

    public func selectReleaseFilter(_ filter: CatalogReleaseFilter) async {
        guard selectedRelease != filter else { return }
        selectedRelease = filter
        cachedByCategory.removeAll()
        await loadFirstPage()
    }

    public func loadFirstPage() async {
        guard !activeSourceId.isEmpty else {
            items = []
            isLoading = false
            return
        }
        loadFirstPageTask?.cancel()
        isLoading = true
        errorMessage = nil
        currentPage = 1
        NSLog("🎬 [HomeVM] loadFirstPage 发起 loadCatalog: source='%@', category='%@'", activeSourceId, selectedCategory.id)
        let targetSource = activeSourceId
        let targetCategory = selectedCategory.id
        loadFirstPageTask = Task {
            do {
                let res = try await repository.loadCatalog(
                    source: targetSource,
                    category: targetCategory,
                    page: 1,
                    query: "",
                    force: true
                )
                guard !Task.isCancelled else { return }
                store.refreshDramas(res.items)
                NSLog("🎬 [HomeVM] loadCatalog 成功返回 %ld 部短剧", res.items.count)
                let filtered = filterAndSort(dramas: res.items)
                items = filtered
                cachedByCategory[targetCategory] = filtered
                hasMore = res.hasMore
                currentPage = 1
            } catch {
                if !Task.isCancelled {
                    NSLog("🎬 [HomeVM] loadCatalog 失败: %@", error.localizedDescription)
                    errorMessage = error.localizedDescription
                    items = []
                }
            }
            isLoading = false
        }
        await loadFirstPageTask?.value
    }

    public func loadNextPage() async {
        guard !isLoadingMore && hasMore else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let res = try await repository.loadCatalog(
                source: activeSourceId,
                category: selectedCategory.id,
                page: nextPage,
                query: "",
                force: false
            )
            guard !Task.isCancelled else { return }
            store.refreshDramas(res.items)
            let newItems = filterAndSort(dramas: res.items)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: newItems.filter { !existing.contains($0.id) })
            hasMore = res.hasMore
            currentPage = nextPage
        } catch {
            // 静默失败，保持已有数据
        }
        isLoadingMore = false
    }

    private func filterAndSort(dramas: [Drama]) -> [Drama] {
        let target = activeSourceId.lowercased()
        var result = dramas.filter { drama in
            let s = drama.source.lowercased()
            return s.isEmpty || s == target
        }
        // 连载状态筛选
        if selectedRelease != .all {
            result = result.filter { $0.releaseStatus.lowercased() == selectedRelease.rawValue }
        }
        // 排序
        switch selectedSort {
        case .source:
            break
        case .latest:
            result.sort { $0.onlineDate > $1.onlineDate }
        case .heat:
            result.sort { (Int($0.heat) ?? 0) > (Int($1.heat) ?? 0) }
        case .views:
            result.sort { $0.views > $1.views }
        case .title:
            result.sort { $0.title < $1.title }
        }
        return result
    }
}
