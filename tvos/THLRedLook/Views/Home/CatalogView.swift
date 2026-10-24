import SwiftUI

public struct CatalogView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject var store: LocalStore
    @EnvironmentObject private var jsService: JSSourceService
    @State private var showingFilterSheet = false
    @State private var selectedDrama: Drama?
    @State private var pendingNextRow: String?
    @State private var pendingCategoryFocus = false

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
                focusedTarget = nil
                onRequestFocusTopNav?()
            }
        }
    }

    private var categoryHeader: some View {
        HStack(spacing: 24) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(viewModel.categories) { category in
                        TVCapsuleButton(
                            title: category.name,
                            isSelected: viewModel.selectedCategory.id == category.id,
                            isFocused: focusedTarget == .category(focusID(category)),
                            onUpCommand: {
                                focusedTarget = nil
                                onRequestFocusTopNav?()
                            },
                            onDownCommand: focusFirstCard,
                            onLeftCommand: { moveCategory(from: category, offset: -1) },
                            onRightCommand: { moveCategory(from: category, offset: 1) }
                        ) {
                            pendingNextRow = nil
                            viewModel.selectCategory(category, immediate: true)
                        }
                        .focused($focusedTarget, equals: .category(focusID(category)))
                        .accessibilityIdentifier("catalog.category.\(focusID(category))")
                    }
                }
                .padding(.vertical, 16)
                .padding(.leading, 12)
                .padding(.trailing, 24)
            }
            .clipShape(Rectangle().inset(by: -30))
            Spacer()
            HStack(spacing: 16) {
                TVButton(
                    title: viewModel.selectedSort.label,
                    icon: "line.3.horizontal.decrease.circle",
                    isFocused: focusedTarget == .filter,
                    onUpCommand: {
                        focusedTarget = nil
                        onRequestFocusTopNav?()
                    },
                    onDownCommand: focusFirstCard
                ) { showingFilterSheet = true }
                .focused($focusedTarget, equals: .filter)
                .accessibilityIdentifier("catalog.filter")

                TVButton(
                    title: "",
                    icon: "arrow.clockwise",
                    isFocused: focusedTarget == .refresh,
                    onUpCommand: {
                        focusedTarget = nil
                        onRequestFocusTopNav?()
                    },
                    onDownCommand: focusFirstCard
                ) {
                    pendingNextRow = nil
                    Task { await viewModel.reloadAll() }
                }
                .focused($focusedTarget, equals: .refresh)
                .accessibilityIdentifier("catalog.refresh")
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 48)
        .focusSection()
        .defaultFocus($focusedTarget, .category(selectedCategoryID))
    }

    private var catalogGrid: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 36) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, drama in
                        DramaCardView(
                            drama: drama,
                            isFocused: focusedTarget == .card(drama.id),
                            forceFocused: forceFocusFirstCard && index == 0,
                            onUpCommand: {
                                if index < columns.count { focusSelectedCategory() }
                                else { focusCard(viewModel.items[index - columns.count].id, scroll: scroll) }
                            },
                            onDownCommand: {
                                if viewModel.errorMessage != nil { focusedTarget = .reloadButton }
                                else { focusNextRow(after: drama.id, scroll: scroll) }
                            }
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
            .focusSection()
            .defaultFocus($focusedTarget, viewModel.items.first.map { FocusTarget.card($0.id) })
            .onChange(of: viewModel.items) { _, _ in finishPendingRowFocus(scroll: scroll) }
            .onChange(of: viewModel.isLoadingMore) { _, loading in
                if !loading { finishPendingRowFocus(scroll: scroll) }
            }
            .onChange(of: focusedTarget) { _, target in
                if case .card(let id) = target { scroll.scrollTo(id, anchor: .center) }
            }
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
        focusedTarget = .category(selectedCategoryID)
    }

    private func focusFirstCard() {
        if let first = viewModel.items.first { focusedTarget = .card(first.id) }
        else if viewModel.errorMessage != nil { focusedTarget = .reloadButton }
    }

    private func moveCategory(from category: CatalogCategory, offset: Int) {
        guard let index = viewModel.categories.firstIndex(of: category) else { return }
        let next = index + offset
        if next >= viewModel.categories.count { focusedTarget = .filter; return }
        if next < 0 {
            focusedTarget = nil
            onRequestFocusTopNav?()
            return
        }
        let target = viewModel.categories[next]
        pendingNextRow = nil
        viewModel.selectCategory(target, immediate: true)
        focusedTarget = .category(focusID(target))
    }

    private func focusNextRow(after id: String, scroll: ScrollViewProxy) {
        pendingNextRow = id
        finishPendingRowFocus(scroll: scroll)
    }

    private func finishPendingRowFocus(scroll: ScrollViewProxy) {
        guard let id = pendingNextRow, focusedTarget == .card(id),
              let index = viewModel.items.firstIndex(where: { $0.id == id }) else { return }
        let nextRow = (index / columns.count + 1) * columns.count
        guard nextRow < viewModel.items.count else {
            if !viewModel.hasMore || viewModel.errorMessage != nil { pendingNextRow = nil }
            else if !viewModel.isLoadingMore {
                Task { await viewModel.loadNextPage() }
            }
            return
        }
        let nextID = viewModel.items[min(index + columns.count, viewModel.items.count - 1)].id
        pendingNextRow = nil
        focusCard(nextID, scroll: scroll)
    }

    private func focusCard(_ id: String, scroll: ScrollViewProxy) {
        scroll.scrollTo(id, anchor: .center)
        DispatchQueue.main.async {
            guard selectedDrama == nil else { return }
            focusedTarget = .card(id)
        }
    }
}
