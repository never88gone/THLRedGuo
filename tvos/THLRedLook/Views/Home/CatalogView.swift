import SwiftUI

public struct CatalogView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject var store: LocalStore
    @State private var showingFilterSheet = false
    @State private var selectedDrama: Drama?
    @FocusState private var focusedCategory: String?
    @FocusState private var focusedDramaId: String?
    public var forceFocusFirstCard: Bool = false
    public var initialCategory: String? = nil
    public var focusCategoryTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)
    ]

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

    @EnvironmentObject private var jsService: JSSourceService
    @Environment(\.openURL) private var openURL
    @State private var showingImportAlert = false
    @State private var importURLString = ""
    @State private var isImporting = false

    public var body: some View {
        VStack(spacing: 0) {
            if jsService.activeSourceId.isEmpty {
                blankStateView
            } else {
                // 顶部分类栏与操作按钮（站源切换已迁移至设置中心统一管理）
            HStack(spacing: 24) {
                // 横向分类栏（增加上侧、左侧、右侧防裁切间距）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(viewModel.categories) { category in
                            let catId = category.id.isEmpty ? "all" : category.id
                            TVCapsuleButton(
                                title: category.name,
                                isSelected: viewModel.selectedCategory.id == category.id,
                                isFocused: focusedCategory == catId,
                                onFocused: {
                                    viewModel.selectCategory(category, immediate: false)
                                },
                                onUpCommand: {
                                    focusedCategory = nil
                                    onRequestFocusTopNav?()
                                },
                                onDownCommand: {
                                    focusedCategory = nil
                                    focusedDramaId = viewModel.items.first?.id
                                }
                            ) {
                                viewModel.selectCategory(category, immediate: true)
                            }
                            .focused($focusedCategory, equals: catId)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .padding(.leading, 12)
                    .padding(.trailing, 24)
                }
                .clipShape(Rectangle().inset(by: -30))

                Spacer()

                HStack(spacing: 16) {
                    // 排序筛选按钮
                    TVButton(
                        title: viewModel.selectedSort.label,
                        icon: "line.3.horizontal.decrease.circle",
                        isFocused: focusedCategory == "__filter__",
                        onUpCommand: {
                            focusedCategory = nil
                            onRequestFocusTopNav?()
                        },
                        onDownCommand: {
                            focusedCategory = nil
                            focusedDramaId = viewModel.items.first?.id
                        }
                    ) {
                        showingFilterSheet = true
                    }
                    .focused($focusedCategory, equals: "__filter__")

                    // 刷新按钮
                    TVButton(
                        title: "",
                        icon: "arrow.clockwise",
                        isFocused: focusedCategory == "__refresh__",
                        onUpCommand: {
                            focusedCategory = nil
                            onRequestFocusTopNav?()
                        },
                        onDownCommand: {
                            focusedCategory = nil
                            focusedDramaId = viewModel.items.first?.id
                        }
                    ) {
                        Task { await viewModel.reloadAll() }
                    }
                    .focused($focusedCategory, equals: "__refresh__")
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 48)
            .background(Color.clear)
            .focusSection()
            .defaultFocus($focusedCategory, viewModel.selectedCategory.id.isEmpty ? "all" : viewModel.selectedCategory.id)

            // 内容网格
            if viewModel.isLoading && viewModel.items.isEmpty {
                Spacer()
                ProgressView("正在载入精彩短剧...")
                    .font(.headline)
                Spacer()
            } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow)
                    Text("加载失败：\(error)")
                        .foregroundColor(.secondary)
                    TVButton(title: "重新加载", isProminent: true) {
                        Task { await viewModel.loadFirstPage() }
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 36) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, drama in
                            DramaCardView(
                                drama: drama,
                                isFocused: focusedDramaId == drama.id,
                                forceFocused: forceFocusFirstCard && index == 0,
                                onUpCommand: (index < 6) ? {
                                    focusedDramaId = nil
                                    let catId = viewModel.selectedCategory.id.isEmpty ? "all" : viewModel.selectedCategory.id
                                    focusedCategory = catId
                                } : nil
                            ) {
                                selectedDrama = drama
                            }
                            .focused($focusedDramaId, equals: drama.id)
                            .onAppear {
                                if drama.id == viewModel.items.last?.id {
                                    Task { await viewModel.loadNextPage() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 28)

                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Text("正在加载更多...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                }
                .focusSection()
                .defaultFocus($focusedDramaId, viewModel.items.first?.id)
            } // end else for loading
            } // end else for jsService
        } // end VStack
        .sheet(isPresented: $showingFilterSheet) {
            FilterSortSheet(viewModel: viewModel, isPresented: $showingFilterSheet)
        }
        .fullScreenCover(item: $selectedDrama) { drama in
            DramaDetailView(drama: drama)
        }
        .onChange(of: focusedCategory) { cat in
            NSLog("🎯 [FOCUS_TRACE] Catalog focusedCategory = %@", cat ?? "nil")
        }
        .onChange(of: focusedDramaId) { dramaId in
            NSLog("🎯 [FOCUS_TRACE] Catalog focusedDramaId = %@", dramaId ?? "nil")
        }
        .onChange(of: focusCategoryTrigger) { _ in
            let target = viewModel.selectedCategory.id.isEmpty ? "all" : viewModel.selectedCategory.id
            focusedDramaId = nil
            focusedCategory = target
            NSLog("🎯 [FOCUS_TRACE] Catalog 收到导航栏向下指令 -> 精确聚焦分类: %@", target)
        }
        .task(id: jsService.activeSourceId) {
            await viewModel.reloadAll()
            if let targetCat = initialCategory, !targetCat.isEmpty {
                for _ in 0..<10 {
                    if let found = viewModel.categories.first(where: { $0.id == targetCat || $0.name == targetCat }) {
                        viewModel.selectCategory(found, immediate: true)
                        break
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
    }
    
    private var blankStateView: some View {
        TVSourceBlankStateView {
            Task { await viewModel.reloadAll() }
        }
    }
}

