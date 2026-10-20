import SwiftUI

public struct CatalogView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject var store: LocalStore
    @State private var showingFilterSheet = false
    @State private var selectedDrama: Drama?

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
                                isFocused: focusedTarget == .category(catId),
                                onFocused: {
                                    viewModel.selectCategory(category, immediate: false)
                                },
                                onUpCommand: {
                                    focusedTarget = nil
                                    onRequestFocusTopNav?()
                                },
                                onDownCommand: {
                                    if let first = viewModel.items.first {
                                        focusedTarget = .card(first.id)
                                    }
                                }
                            ) {
                                viewModel.selectCategory(category, immediate: true)
                            }
                            .focused($focusedTarget, equals: .category(catId))
                            .accessibilityIdentifier("catalog.category.\(catId)")
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
                        isFocused: focusedTarget == .filter,
                        onUpCommand: {
                            focusedTarget = nil
                            onRequestFocusTopNav?()
                        },
                        onDownCommand: {
                            if let first = viewModel.items.first {
                                focusedTarget = .card(first.id)
                            }
                        }
                    ) {
                        showingFilterSheet = true
                    }
                    .focused($focusedTarget, equals: .filter)
                    .accessibilityIdentifier("catalog.filter")

                    // 刷新按钮
                    TVButton(
                        title: "",
                        icon: "arrow.clockwise",
                        isFocused: focusedTarget == .refresh,
                        onUpCommand: {
                            focusedTarget = nil
                            onRequestFocusTopNav?()
                        },
                        onDownCommand: {
                            if let first = viewModel.items.first {
                                focusedTarget = .card(first.id)
                            }
                        }
                    ) {
                        Task { await viewModel.reloadAll() }
                    }
                    .focused($focusedTarget, equals: .refresh)
                    .accessibilityIdentifier("catalog.refresh")
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 48)
            .background(Color.clear)
            .focusSection()
            .defaultFocus($focusedTarget, .category("all"))

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
                    TVButton(
                        title: "重新加载",
                        isProminent: true,
                        isFocused: focusedTarget == .reloadButton,
                        onUpCommand: {
                            let catId = viewModel.selectedCategory.id.isEmpty ? "all" : viewModel.selectedCategory.id
                            focusedTarget = .category(catId)
                        }
                    ) {
                        Task { await viewModel.loadFirstPage() }
                    }
                    .focused($focusedTarget, equals: .reloadButton)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 36) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, drama in
                            DramaCardView(
                                drama: drama,
                                isFocused: focusedTarget == .card(drama.id),
                                forceFocused: forceFocusFirstCard && index == 0,
                                onUpCommand: (index < 6) ? {
                                    let catId = viewModel.selectedCategory.id.isEmpty ? "all" : viewModel.selectedCategory.id
                                    focusedTarget = .category(catId)
                                } : nil
                            ) {
                                selectedDrama = drama
                            }
                            .focused($focusedTarget, equals: .card(drama.id))
                            .accessibilityIdentifier("catalog.result.\(index)")
                            .onAppear {
                                // 瀑布流智能触底：滑动至倒数 10 部短剧时提前自动请求下一页
                                if index >= viewModel.items.count - 10 && viewModel.hasMore && !viewModel.isLoadingMore {
                                    Task { await viewModel.loadNextPage() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 28)

                    if viewModel.isLoadingMore {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在加载更多短剧...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                }
                .focusSection()
                .defaultFocus($focusedTarget, viewModel.items.first.map { FocusTarget.card($0.id) })
            } // end else for loading
            } // end else for jsService
        } // end VStack
        .sheet(isPresented: $showingFilterSheet) {
            FilterSortSheet(viewModel: viewModel, isPresented: $showingFilterSheet)
        }
        .fullScreenCover(item: $selectedDrama) { drama in
            DramaDetailView(drama: drama)
        }
        .onChange(of: focusedTarget) { target in
            NSLog("🎯 [FOCUS_TRACE] Catalog focusedTarget = %@", String(describing: target))
            if case .card(let id) = target,
               let idx = viewModel.items.firstIndex(where: { $0.id == id }),
               idx >= viewModel.items.count - 6,
               viewModel.hasMore,
               !viewModel.isLoadingMore {
                Task { await viewModel.loadNextPage() }
            }
        }
        .onChange(of: focusCategoryTrigger) { _ in
            let target = "all"
            focusedTarget = .category(target)
            NSLog("🎯 [FOCUS_TRACE] Catalog 收到导航栏向下指令 -> 精确聚焦全部按钮: %@", target)
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

