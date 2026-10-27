import SwiftUI

public struct CatalogView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject var store: LocalStore
    @EnvironmentObject private var jsService: JSSourceService
    @State private var showingFilterSheet = false
    @State private var selectedDrama: Drama?
    @State private var pendingNextRow: String?
    @State private var pendingCategoryFocus = false
    @State private var pendingCardFocus = false
    @State private var autoSelectCategoryTask: Task<Void, Never>?

    public enum FocusTarget: Hashable {
        case category(String)
        case filter
        case refresh
        case reloadButton
        case card(String)
    }
    @FocusState private var focusedTarget: FocusTarget?

    public var forceFocusFirstCard: Bool = false
    public var initialCategory: String? = nil
    public var focusCategoryTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 32), count: 6)
    private var selectedCategoryID: String { focusID(viewModel.selectedCategory) }

    public init(
        store: LocalStore = .shared,
        forceFocusFirstCard: Bool = false,
        initialCategory: String? = nil,
        focusCategoryTrigger: Int = 0,
        onRequestFocusTopNav: (() -> Void)? = nil
    ) {
        self.store = store
        self.forceFocusFirstCard = forceFocusFirstCard
        self.initialCategory = initialCategory
        self.focusCategoryTrigger = focusCategoryTrigger
        self.onRequestFocusTopNav = onRequestFocusTopNav
    }

    public var body: some View {
        VStack(spacing: 0) {
            if jsService.activeSourceId.isEmpty && jsService.sources.isEmpty {
                TVSourceBlankStateView { Task { await viewModel.reloadAll() } }
            } else {
                categoryHeader
                if viewModel.isLoading && viewModel.items.isEmpty {
                    Spacer()
                    ProgressView("正在载入精彩短剧...").font(.headline)
                    Spacer()
                } else if viewModel.items.isEmpty {
                    Spacer()
                    Text(viewModel.errorMessage ?? "当前分类暂无短剧").foregroundColor(.secondary)
                    retryButton
                    Spacer()
                } else {
                    catalogGrid
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterSortSheet(viewModel: viewModel, isPresented: $showingFilterSheet)
        }
        .fullScreenCover(item: $selectedDrama) { drama in
            DramaDetailView(drama: drama)
        }
        .onChange(of: viewModel.categories) { _, _ in
            if pendingCategoryFocus { focusSelectedCategory() }
        }
        .onChange(of: focusedTarget) { _, target in
            if let pendingNextRow, target != .card(pendingNextRow) { self.pendingNextRow = nil }
            if case .card(let id) = target,
               let index = viewModel.items.firstIndex(where: { $0.id == id }),
               index >= viewModel.items.count - columns.count * 2 {
                Task { await viewModel.loadNextPage() }
            }
            if case .category(let id) = target {
                if let cat = viewModel.categories.first(where: { focusID($0) == id }) {
                    scheduleAutoSelectCategory(cat)
                }
            } else {
                cancelAutoSelectCategory()
            }
        }
        .onChange(of: focusCategoryTrigger) { _, _ in
            pendingCategoryFocus = true
            DispatchQueue.main.async { focusSelectedCategory() }
        }
        .task(id: jsService.activeSourceId) {
            guard !jsService.activeSourceId.isEmpty else { return }
            await viewModel.reloadAll(initialCategory: initialCategory)
        }
        .onExitCommand {
            if !showingFilterSheet && selectedDrama == nil {
                cancelAutoSelectCategory()
                focusedTarget = nil
                onRequestFocusTopNav?()
            }
        }
    }

    private var categoryHeader: some View {
        HStack(spacing: 24) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(viewModel.categories) { category in
                            TVCapsuleButton(
                                title: category.name,
                                isSelected: viewModel.selectedCategory.id == category.id,
                                isFocused: focusedTarget == .category(focusID(category)),
                                onUpCommand: {
                                    cancelAutoSelectCategory()
                                    focusedTarget = nil
                                    onRequestFocusTopNav?()
                                },
                                onDownCommand: {
                                    cancelAutoSelectCategory()
                                    focusFirstCard()
                                },
                                onLeftCommand: { moveCategory(from: category, offset: -1) },
                                onRightCommand: { moveCategory(from: category, offset: 1) }
                            ) {
                                pendingNextRow = nil
                                cancelAutoSelectCategory()
                                viewModel.selectCategory(category, immediate: true)
                            }
                            .id("category_\(focusID(category))")
                            .focused($focusedTarget, equals: .category(focusID(category)))
                            .accessibilityIdentifier("catalog.category.\(focusID(category))")
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.leading, 12)
                    .padding(.trailing, 24)
                }
                .clipShape(Rectangle().inset(by: -30))
                .onChange(of: focusedTarget) { _, target in
                    if case .category(let id) = target {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("category_\(id)", anchor: .center)
                        }
                    }
                }
            }
            Spacer()
            HStack(spacing: 16) {
                TVButton(
                    title: viewModel.selectedSort.label,
                    icon: "line.3.horizontal.decrease.circle",
                    isFocused: focusedTarget == .filter,
                    onUpCommand: {
                        cancelAutoSelectCategory()
                        focusedTarget = nil
                        onRequestFocusTopNav?()
                    },
                    onDownCommand: {
                        cancelAutoSelectCategory()
                        focusFirstCard()
                    }
                ) { showingFilterSheet = true }
                .focused($focusedTarget, equals: .filter)
                .accessibilityIdentifier("catalog.filter")

                TVButton(
                    title: "",
                    icon: "arrow.clockwise",
                    isFocused: focusedTarget == .refresh,
                    onUpCommand: {
                        cancelAutoSelectCategory()
                        focusedTarget = nil
                        onRequestFocusTopNav?()
                    },
                    onDownCommand: {
                        cancelAutoSelectCategory()
                        focusFirstCard()
                    }
                ) {
                    pendingNextRow = nil
                    cancelAutoSelectCategory()
                    Task { await viewModel.reloadAll() }
                }
                .focused($focusedTarget, equals: .refresh)
                .accessibilityIdentifier("catalog.refresh")
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 48)
        .defaultFocus($focusedTarget, .category(selectedCategoryID))
    }

    private var catalogGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 36) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, drama in
                    DramaCardView(
                        drama: drama,
                        isFocused: focusedTarget == .card(drama.id),
                        forceFocused: forceFocusFirstCard && index == 0,
                        onUpCommand: (index < columns.count) ? {
                            focusSelectedCategory()
                        } : nil,
                        onDownCommand: (index + columns.count >= viewModel.items.count && viewModel.hasMore) ? {
                            focusNextRow(after: drama.id)
                        } : nil
                    ) { selectedDrama = drama }
                    .id(drama.id)
                    .focused($focusedTarget, equals: .card(drama.id))
                    .accessibilityIdentifier("catalog.result.\(index)")
                    .onAppear {
                        if index >= viewModel.items.count - 4 {
                            Task { await viewModel.loadNextPage() }
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 28)
            if viewModel.isLoadingMore {
                ProgressView("正在加载更多短剧...").padding(.vertical, 28)
            }
            if let message = viewModel.errorMessage {
                Text(message).foregroundColor(.secondary)
                retryButton.padding(.bottom, 28)
            }
        }
        .defaultFocus($focusedTarget, viewModel.items.first.map { FocusTarget.card($0.id) })
        .onChange(of: viewModel.items) { _, items in
            finishPendingRowFocus()
            if pendingCardFocus, let first = items.first {
                pendingCardFocus = false
                focusedTarget = .card(first.id)
            } else if case .card(let currentId) = focusedTarget {
                if !items.contains(where: { $0.id == currentId }), let first = items.first {
                    focusedTarget = .card(first.id)
                }
            }
        }
        .onChange(of: viewModel.isLoadingMore) { _, loading in
            if !loading { finishPendingRowFocus() }
        }
    }

    private var retryButton: some View {
        TVButton(
            title: "重新加载",
            icon: "arrow.clockwise",
            isFocused: focusedTarget == .reloadButton,
            onUpCommand: {
                if let last = viewModel.items.last { focusedTarget = .card(last.id) }
                else { focusSelectedCategory() }
            }
        ) { Task { await viewModel.retry() } }
        .focused($focusedTarget, equals: .reloadButton)
        .accessibilityIdentifier("catalog.retry")
    }

    private func focusID(_ category: CatalogCategory) -> String {
        category.id.isEmpty ? "all" : category.id
    }

    private func focusSelectedCategory() {
        guard !viewModel.categories.isEmpty else { return }
        pendingCategoryFocus = false
        cancelAutoSelectCategory()
        focusedTarget = .category(selectedCategoryID)
    }

    private func focusFirstCard() {
        cancelAutoSelectCategory()
        if let first = viewModel.items.first {
            focusedTarget = .card(first.id)
        } else if viewModel.isLoading {
            pendingCardFocus = true
        } else if viewModel.errorMessage != nil {
            focusedTarget = .reloadButton
        }
    }

    private func moveCategory(from category: CatalogCategory, offset: Int) {
        guard let index = viewModel.categories.firstIndex(of: category) else { return }
        let next = index + offset
        if next >= viewModel.categories.count {
            cancelAutoSelectCategory()
            focusedTarget = .filter
            return
        }
        if next < 0 {
            cancelAutoSelectCategory()
            focusedTarget = nil
            onRequestFocusTopNav?()
            return
        }
        let target = viewModel.categories[next]
        pendingNextRow = nil
        focusedTarget = .category(focusID(target))
        scheduleAutoSelectCategory(target)
    }

    private func scheduleAutoSelectCategory(_ category: CatalogCategory) {
        cancelAutoSelectCategory()
        guard viewModel.selectedCategory.id != category.id else { return }
        autoSelectCategoryTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            viewModel.selectCategory(category)
        }
    }

    private func cancelAutoSelectCategory() {
        autoSelectCategoryTask?.cancel()
        autoSelectCategoryTask = nil
    }

    private func focusNextRow(after id: String) {
        pendingNextRow = id
        finishPendingRowFocus()
    }

    private func finishPendingRowFocus() {
        guard let id = pendingNextRow, focusedTarget == .card(id),
              let index = viewModel.items.firstIndex(where: { $0.id == id }) else { return }
        let nextRow = (index / columns.count + 1) * columns.count
        guard nextRow < viewModel.items.count else {
            if !viewModel.hasMore || viewModel.errorMessage != nil {
                pendingNextRow = nil
            } else if !viewModel.isLoadingMore {
                Task { await viewModel.loadNextPage() }
            }
            return
        }
        let nextID = viewModel.items[min(index + columns.count, viewModel.items.count - 1)].id
        pendingNextRow = nil
        focusedTarget = .card(nextID)
    }
}
