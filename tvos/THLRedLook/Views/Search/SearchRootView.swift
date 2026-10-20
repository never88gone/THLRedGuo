import SwiftUI
import UIKit

public struct SearchRootView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var selectedDrama: Drama?
    @State private var handledInitialQuery: String?
    @State private var returningDramaId: String?
    private enum SearchFocus: Hashable {
        case query
        case submit
        case drama(String)
    }
    @FocusState private var focusedTarget: SearchFocus?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 32), count: 6)

    public var initialQuery: String?
    public var targetEpisode: Int?
    public var focusTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)? = nil

    public init(
        initialQuery: String? = nil,
        targetEpisode: Int? = nil,
        focusTrigger: Int = 0,
        onRequestFocusTopNav: (() -> Void)? = nil
    ) {
        self.initialQuery = initialQuery
        self.targetEpisode = targetEpisode
        self.focusTrigger = focusTrigger
        self.onRequestFocusTopNav = onRequestFocusTopNav
    }

    public var body: some View {
        ZStack {
            if viewModel.activeSourceId.isEmpty {
                TVSourceBlankStateView {
                    if let q = initialQuery, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { await viewModel.executeSearch(keyword: q) }
                    }
                }
            } else {
                VStack(spacing: 24) {
                    // 顶部搜索输入框与按钮
                    HStack(spacing: 28) {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("输入剧名或关键词搜索...", text: Binding(
                                get: { viewModel.query },
                                set: { viewModel.onQueryChanged($0) }
                            ))
                            .focused($focusedTarget, equals: .query)
                            .accessibilityIdentifier("search.query")
                            .onMoveCommand { direction in
                                if direction == .up { focusedTarget = nil; onRequestFocusTopNav?() }
                                if direction == .right {

                                    focusSearchButton()
                                }
                            }
                            .onSubmit {
                                focusSearchButton()
                                Task { await viewModel.executeSearch() }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .tvPanelStyle(cornerRadius: 14)

                        TVButton(title: "搜索", icon: "magnifyingglass", isProminent: true) {
                            Task { await viewModel.executeSearch() }
                        }
                        .accessibilityIdentifier("search.submit")
                        .focused($focusedTarget, equals: .submit)
                        .onMoveCommand { direction in
                            if direction == .left { focusedTarget = .query }
                            if direction == .up { focusedTarget = nil; onRequestFocusTopNav?() }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)

                    // 联想建议列表 (Suggestions)（增加上侧、左侧、右侧防裁切间距）
                    if !viewModel.suggestions.isEmpty {
                        Text(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "猜你想搜" : "搜索联想")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 60)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 22) {
                                ForEach(viewModel.suggestions, id: \.self) { sug in
                                    TVCapsuleButton(title: sug, isSelected: false) {
                                        Task { await viewModel.executeSearch(keyword: sug) }
                                    }
                                }
                            }
                            .padding(.leading, 12)
                            .padding(.trailing, 48)
                            .padding(.top, 14)
                            .padding(.bottom, 14)
                        }
                        .padding(.horizontal, 48)
                    }

                    // 搜索历史（增加上侧、左侧、右侧防裁切间距）
                    if !viewModel.hasSearched && !viewModel.historyKeywords.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("历史搜索")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                TVButton(title: "清空历史", icon: "trash") {
                                    viewModel.clearHistory()
                                }
                                .padding(.top, 4)
                                .padding(.trailing, 6)
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 22) {
                                    ForEach(viewModel.historyKeywords, id: \.self) { kw in
                                        TVCapsuleButton(title: kw, isSelected: false) {
                                            Task { await viewModel.executeSearch(keyword: kw) }
                                        }
                                    }
                                }
                                .padding(.leading, 12)
                                .padding(.trailing, 36)
                                .padding(.top, 14)
                                .padding(.bottom, 14)
                            }
                        }
                        .padding(.horizontal, 48)
                    }

                    // 搜索结果展示
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView("正在搜索中...")
                        Spacer()
                    } else if viewModel.hasSearched && viewModel.searchResults.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text(viewModel.errorMessage ?? "未找到相关剧集，请尝试更简短的名称")
                                .foregroundColor(.secondary)
                            if viewModel.errorMessage != nil {
                                TVButton(title: "重试搜索", icon: "arrow.clockwise") {
                                    Task { await viewModel.executeSearch() }
                                }
                            }
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                LazyVGrid(columns: columns, spacing: 36) {
                                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, drama in
                                        DramaCardView(
                                            drama: drama,
                                            isExternalFocused: focusedTarget == .drama(drama.id),
                                            onUpCommand: {
                                                if index < columns.count {
                                                    focusedTarget = .query
                                                }
                                            }
                                        ) {
                                            returningDramaId = drama.id
                                            selectedDrama = drama
                                        }
                                        .focused($focusedTarget, equals: .drama(drama.id))
                                        .id("search_card_\(drama.id)")
                                        .accessibilityIdentifier("search.result.\(index)")
                                        .onAppear {
                                            // 瀑布流智能触底：滑到倒数 8 部短剧时自动提前异步请求下一页
                                            if index >= viewModel.searchResults.count - 8 && viewModel.hasMore && !viewModel.isLoadingMore {
                                                Task { await viewModel.loadMore() }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 48)
                                .padding(.vertical, 24)

                                if let message = viewModel.errorMessage {
                                    Text(message)
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }

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
                        }
                        .onChange(of: focusedTarget) { target in
                            // 遥控器焦点向下滑动推进到后半段时，双保险静默预热下一页
                            if case .drama(let id) = target,
                               let idx = viewModel.searchResults.firstIndex(where: { $0.id == id }),
                               idx >= viewModel.searchResults.count - 6,
                               viewModel.hasMore,
                               !viewModel.isLoadingMore {
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                }
                .onAppear {
                    runInitialSearchIfNeeded()
                    if !viewModel.hasSearched { viewModel.onQueryChanged(viewModel.query) }
                }
                .onChange(of: initialQuery) { _ in runInitialSearchIfNeeded() }
                .onChange(of: focusTrigger) { _ in
                    if let firstId = viewModel.searchResults.first?.id {
                        focusedTarget = .drama(firstId)

                    } else {
                        focusedTarget = .query

                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in
            guard selectedDrama == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if focusedTarget == .query { focusSearchButton() }
            }
        }
        .onExitCommand {
            guard selectedDrama == nil else { return }



            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onRequestFocusTopNav?()
            }
        }
        .fullScreenCover(item: $selectedDrama, onDismiss: {
            focusedTarget = returningDramaId.map(SearchFocus.drama)

        }) { drama in
            DramaDetailView(drama: drama)
        }
    }
    private func focusSearchButton() {
        focusedTarget = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focusedTarget = .submit }
    }

    private func runInitialSearchIfNeeded() {
        guard let query = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty, handledInitialQuery != query else { return }
        handledInitialQuery = query
        Task { await viewModel.executeSearch(keyword: query) }
    }

}
