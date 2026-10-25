import SwiftUI
import UIKit

public struct SearchRootView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var selectedDrama: Drama?
    @State private var handledInitialQuery: String?
    @State private var returningDramaId: String?

    private enum SearchFocus: Hashable {
        case query
        case clearIcon
        case clear
        case submit
        case suggestion(String)
        case history(String)
        case clearHistory
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
                    // 顶部搜索输入框与操作栏（精准处理按键导航，消除死锁）
                    HStack(spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                                .font(.system(size: 22))

                            TextField("输入剧名或关键词搜索...", text: Binding(
                                get: { viewModel.query },
                                set: { viewModel.onQueryChanged($0) }
                            ))
                            .focused($focusedTarget, equals: .query)
                            .accessibilityIdentifier("search.query")
                            .onMoveCommand { direction in
                                switch direction {
                                case .right:
                                    if !viewModel.query.isEmpty {
                                        focusedTarget = .clearIcon
                                    } else if viewModel.hasSearched {
                                        focusedTarget = .clear
                                    } else {
                                        focusedTarget = .submit
                                    }
                                case .down:
                                    focusContentBelowInput()
                                case .left:
                                    focusedTarget = nil
                                    onRequestFocusTopNav?()
                                case .up:
                                    break
                                }
                            }
                            .onSubmit {
                                focusedTarget = .submit
                                Task { await viewModel.executeSearch() }
                            }

                            if !viewModel.query.isEmpty {
                                Button(action: {
                                    viewModel.clearSearch()
                                    focusedTarget = .query
                                }) {
                                    let isIconFocused = focusedTarget == .clearIcon
                                    ZStack {
                                        Circle()
                                            .fill(
                                                isIconFocused
                                                    ? AnyShapeStyle(LinearGradient(
                                                        colors: [Color(red: 0.95, green: 0.22, blue: 0.28), Color(red: 0.78, green: 0.12, blue: 0.18)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ))
                                                    : AnyShapeStyle(Color.white.opacity(0.12))
                                            )
                                            .frame(width: 34, height: 34)

                                        Image(systemName: "xmark")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(isIconFocused ? .white : .white.opacity(0.65))

                                        if isIconFocused {
                                            Circle()
                                                .stroke(Color.white, lineWidth: 2.5)
                                                .frame(width: 34, height: 34)
                                        }
                                    }
                                    .scaleEffect(isIconFocused ? 1.15 : 1.0)
                                    .shadow(color: isIconFocused ? Color.red.opacity(0.85) : Color.clear, radius: 10, x: 0, y: 0)
                                    .animation(TVTheme.focusSpringAnimation, value: isIconFocused)
                                }
                                .buttonStyle(TVZeroHighlightButtonStyle())
                                .focusEffectDisabled()
                                .focused($focusedTarget, equals: .clearIcon)
                                .accessibilityIdentifier("search.clear_icon")
                                .onMoveCommand { direction in
                                    switch direction {
                                    case .left:
                                        focusedTarget = .query
                                    case .right:
                                        if !viewModel.query.isEmpty || viewModel.hasSearched {
                                            focusedTarget = .clear
                                        } else {
                                            focusedTarget = .submit
                                        }
                                    case .down:
                                        focusContentBelowInput()
                                    case .up:
                                        break
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .tvPanelStyle(cornerRadius: 14)

                        // 独立清空搜索按钮（有输入或已执行搜索时可见，一键清除文字与结果）
                        if !viewModel.query.isEmpty || viewModel.hasSearched {
                            TVButton(
                                title: "清空",
                                icon: "xmark.circle",
                                isProminent: false,
                                isExternalFocused: focusedTarget == .clear
                            ) {
                                viewModel.clearSearch()
                                focusedTarget = .query
                            }
                            .accessibilityIdentifier("search.clear")
                            .focused($focusedTarget, equals: .clear)
                            .onMoveCommand { direction in
                                switch direction {
                                case .left:
                                    if !viewModel.query.isEmpty {
                                        focusedTarget = .clearIcon
                                    } else {
                                        focusedTarget = .query
                                    }
                                case .right:
                                    focusedTarget = .submit
                                case .down:
                                    focusContentBelowInput()
                                case .up:
                                    break
                                }
                            }
                        }

                        TVButton(
                            title: "搜索",
                            icon: "magnifyingglass",
                            isProminent: true,
                            isExternalFocused: focusedTarget == .submit
                        ) {
                            Task { await viewModel.executeSearch() }
                        }
                        .accessibilityIdentifier("search.submit")
                        .focused($focusedTarget, equals: .submit)
                        .onMoveCommand { direction in
                            switch direction {
                            case .left:
                                if !viewModel.query.isEmpty || viewModel.hasSearched {
                                    focusedTarget = .clear
                                } else if !viewModel.query.isEmpty {
                                    focusedTarget = .clearIcon
                                } else {
                                    focusedTarget = .query
                                }
                            case .down:
                                focusContentBelowInput()
                            case .up, .right:
                                break
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)
                    .focusSection()

                    // 猜你想搜 / 热门精选词（只要没有展示搜索结果就持续展示，绝不自动消失）
                    if !viewModel.hasSearched && !viewModel.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "猜你想搜" : "搜索联想")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white.opacity(0.75))
                                .padding(.horizontal, 48)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 18) {
                                    ForEach(viewModel.suggestions, id: \.self) { sug in
                                        TVCapsuleButton(
                                            title: sug,
                                            isSelected: false,
                                            isFocused: focusedTarget == .suggestion(sug),
                                            onUpCommand: {
                                                focusedTarget = .query
                                            },
                                            onDownCommand: {
                                                if !viewModel.historyKeywords.isEmpty {
                                                    focusedTarget = .history(viewModel.historyKeywords.first!)
                                                }
                                            }
                                        ) {
                                            Task { await viewModel.executeSearch(keyword: sug) }
                                        }
                                        .focused($focusedTarget, equals: .suggestion(sug))
                                        .accessibilityIdentifier("search.suggestion.\(sug)")
                                    }
                                }
                                .padding(.horizontal, 48)
                                .padding(.vertical, 8)
                            }
                        }
                        .focusSection()
                    }

                    // 搜索历史
                    if !viewModel.hasSearched && !viewModel.historyKeywords.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("历史搜索")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white.opacity(0.75))
                                Spacer()
                                TVButton(
                                    title: "清空历史",
                                    icon: "trash",
                                    isProminent: false,
                                    isExternalFocused: focusedTarget == .clearHistory
                                ) {
                                    viewModel.clearHistory()
                                }
                                .accessibilityIdentifier("search.clearHistory")
                                .focused($focusedTarget, equals: .clearHistory)
                            }
                            .padding(.horizontal, 48)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 18) {
                                    ForEach(viewModel.historyKeywords, id: \.self) { kw in
                                        TVCapsuleButton(
                                            title: kw,
                                            isSelected: false,
                                            isFocused: focusedTarget == .history(kw),
                                            onUpCommand: {
                                                if let firstSug = viewModel.suggestions.first {
                                                    focusedTarget = .suggestion(firstSug)
                                                } else {
                                                    focusedTarget = .query
                                                }
                                            }
                                        ) {
                                            Task { await viewModel.executeSearch(keyword: kw) }
                                        }
                                        .focused($focusedTarget, equals: .history(kw))
                                        .accessibilityIdentifier("search.history.\(kw)")
                                    }
                                }
                                .padding(.horizontal, 48)
                                .padding(.vertical, 8)
                            }
                        }
                        .focusSection()
                    }

                    // 搜索结果展示或加载指示
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView("正在搜索中...")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    } else if viewModel.hasSearched && viewModel.searchResults.isEmpty {
                        Spacer()
                        VStack(spacing: 18) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 54))
                                .foregroundColor(.secondary)
                            Text(viewModel.errorMessage ?? "未找到相关剧集，请尝试更换关键词")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary)

                            HStack(spacing: 20) {
                                TVButton(title: "清空重新搜索", icon: "arrow.counterclockwise", isProminent: true) {
                                    viewModel.clearSearch()
                                    focusedTarget = .query
                                }
                                if viewModel.errorMessage != nil {
                                    TVButton(title: "重试搜索", icon: "arrow.clockwise") {
                                        Task { await viewModel.executeSearch() }
                                    }
                                }
                            }
                            .padding(.top, 12)
                        }
                        Spacer()
                    } else if viewModel.hasSearched && !viewModel.searchResults.isEmpty {
                        ScrollView {
                            VStack(spacing: 24) {
                                LazyVGrid(columns: columns, spacing: 36) {
                                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, drama in
                                        DramaCardView(
                                            drama: drama,
                                            isExternalFocused: focusedTarget == .drama(drama.id),
                                            onUpCommand: {
                                                if index < columns.count {
                                                    if !viewModel.query.isEmpty || viewModel.hasSearched {
                                                        focusedTarget = .clear
                                                    } else {
                                                        focusedTarget = .query
                                                    }
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
                        .focusSection()
                    } else {
                        Spacer()
                    }
                }
                .onChange(of: viewModel.isLoading) { loading in
                    if !loading && viewModel.hasSearched {
                        if let firstId = viewModel.searchResults.first?.id {
                            focusedTarget = .drama(firstId)
                        } else {
                            focusedTarget = .clear
                        }
                    }
                }
            }
        }
        .onAppear {
            if let req = DeepLinkSearchCoordinator.shared.latestRequest {
                NSLog("🎬 [SearchRootView] onAppear found active deepLink request: '%@'", req.keyword)
                if handledInitialQuery != req.keyword || viewModel.searchResults.isEmpty {
                    handledInitialQuery = req.keyword
                    viewModel.query = req.keyword
                    Task {
                        await viewModel.executeSearch(keyword: req.keyword)
                    }
                }
            } else {
                runInitialSearchIfNeeded()
            }
        }
        .onReceive(DeepLinkSearchCoordinator.shared.$latestRequest) { request in
            guard let req = request else { return }
            NSLog("🎬 [SearchRootView] onReceive deepLink request: '%@', id=%@", req.keyword, req.id.uuidString)
            handledInitialQuery = req.keyword
            viewModel.query = req.keyword
            focusedTarget = .query
            Task {
                await viewModel.executeSearch(keyword: req.keyword)
            }
        }
        .onChange(of: initialQuery) { _, newQuery in
            NSLog("🎬 [SearchRootView] onChange initialQuery: %@", newQuery ?? "nil")
            if let q = newQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
                handledInitialQuery = q
                viewModel.query = q
                Task { await viewModel.executeSearch(keyword: q) }
            }
        }
        .onChange(of: focusTrigger) { _ in
            if let firstId = viewModel.searchResults.first?.id {
                focusedTarget = .drama(firstId)
            } else {
                focusedTarget = .query
            }
        }
        .onExitCommand {
            guard selectedDrama == nil else { return }
            focusedTarget = nil
            onRequestFocusTopNav?()
        }
        .fullScreenCover(item: $selectedDrama, onDismiss: {
            focusedTarget = returningDramaId.map(SearchFocus.drama)
        }) { drama in
            DramaDetailView(drama: drama)
        }
    }

    private func focusContentBelowInput() {
        if viewModel.hasSearched, let firstDrama = viewModel.searchResults.first {
            focusedTarget = .drama(firstDrama.id)
        } else if !viewModel.suggestions.isEmpty, let firstSug = viewModel.suggestions.first {
            focusedTarget = .suggestion(firstSug)
        } else if !viewModel.historyKeywords.isEmpty, let firstHistory = viewModel.historyKeywords.first {
            focusedTarget = .history(firstHistory)
        }
    }

    private func runInitialSearchIfNeeded() {
        guard let query = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty, handledInitialQuery != query else { return }
        handledInitialQuery = query
        viewModel.query = query
        NSLog("🎬 [SearchRootView] runInitialSearchIfNeeded 执行搜索: query=%@", query)
        Task { await viewModel.executeSearch(keyword: query) }
    }
}
