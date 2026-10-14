import SwiftUI

public struct SearchRootView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var selectedDrama: Drama?

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)
    ]

    public var initialQuery: String?
    public var targetEpisode: Int?

    public init(initialQuery: String? = nil, targetEpisode: Int? = nil) {
        self.initialQuery = initialQuery
        self.targetEpisode = targetEpisode
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
                            .onSubmit {
                                Task { await viewModel.executeSearch() }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .tvPanelStyle(cornerRadius: 14)

                        TVButton(title: "搜索", icon: "magnifyingglass", isProminent: true) {
                            Task { await viewModel.executeSearch() }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)

                    // 联想建议列表 (Suggestions)（增加上侧、左侧、右侧防裁切间距）
                    if !viewModel.suggestions.isEmpty {
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
                            Text("未找到相关剧集，请尝试更简短的名称")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 36) {
                                ForEach(viewModel.searchResults) { drama in
                                    DramaCardView(drama: drama) {
                                        selectedDrama = drama
                                    }
                                }
                            }
                            .padding(.horizontal, 48)
                            .padding(.vertical, 24)
                        }
                    }
                }
                .onAppear {
                    if let q = initialQuery, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task {
                            await viewModel.executeSearch(keyword: q)
                        }
                    }
                }
                .onChange(of: initialQuery) { newQuery in
                    if let q = newQuery, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task {
                            await viewModel.executeSearch(keyword: q)
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedDrama) { drama in
            DramaDetailView(drama: drama)
        }
    }
}
