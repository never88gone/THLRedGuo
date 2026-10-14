import SwiftUI



public struct RankingsView: View {
    @StateObject private var viewModel = RankingsViewModel()
    @EnvironmentObject private var jsService: JSSourceService
    @EnvironmentObject private var store: LocalStore
    @State private var selectedDrama: Drama?

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)
    ]

    public init() {}

    private var currentActiveSource: String {
        let active = jsService.activeSourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !active.isEmpty {
            return active
        }
        return store.currentSourceId
    }

    public var body: some View {
        ZStack {
            if currentActiveSource.isEmpty {
                TVSourceBlankStateView {
                    Task {
                        await viewModel.loadBoards(forSource: currentActiveSource)
                        await viewModel.loadRankings()
                    }
                }
            } else {
                VStack(spacing: 20) {
                    // 榜单切换 Tab（支持横向遥控平滑滚动，并预留上侧、左侧、右侧防裁切间距）
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 24) {
                            ForEach(viewModel.boards.filter(\.isAllowedOnTV)) { board in
                                TVRankingBoardButton(
                                    board: board,
                                    isSelected: viewModel.selectedBoard?.id == board.id,
                                    onFocused: {
                                        viewModel.selectBoard(board)
                                    }
                                ) {
                                    viewModel.selectBoard(board)
                                }
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                    }
                    .clipShape(Rectangle().inset(by: -30))

                    if viewModel.isLoading && viewModel.items.isEmpty {
                        Spacer()
                        ProgressView("正在载入排行榜...")
                        Spacer()
                    } else if viewModel.items.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 64))
                                .foregroundColor(TVTheme.primary.opacity(0.8))
                            Text("当前数据源暂未收录该榜单剧集")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 36) {
                                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, drama in
                                    ZStack(alignment: .topLeading) {
                                        DramaCardView(drama: drama) {
                                            selectedDrama = drama
                                        }

                                        // 前三名金银铜徽章
                                        Text("\(index + 1)")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(.white)
                                            .frame(width: 28, height: 28)
                                            .background(
                                                index == 0 ? Color.yellow : (index == 1 ? Color.gray : (index == 2 ? Color.orange : Color.black.opacity(0.6)))
                                            )
                                            .clipShape(Circle())
                                            .padding(8)
                                    }
                                }
                            }
                            .padding(.horizontal, 48)
                            .padding(.vertical, 24)
                        }
                    }
                }
                .task(id: currentActiveSource) {
                    await viewModel.loadBoards(forSource: currentActiveSource)
                    await viewModel.loadRankings()
                }
            }
        }
        .fullScreenCover(item: $selectedDrama) { drama in
            DramaDetailView(drama: drama)
        }
    }
}

public struct RecommendationsView: View {
    @StateObject private var viewModel = RecommendationsViewModel()
    @StateObject private var jsService = JSSourceService.shared
    @StateObject private var store = LocalStore.shared
    @State private var selectedDrama: Drama?

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)
    ]

    public var initialCategory: String? = nil

    public init(initialCategory: String? = nil) {
        self.initialCategory = initialCategory
    }

    private var currentActiveSource: String {
        let active = jsService.activeSourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        return active.isEmpty ? store.currentSourceId : active
    }

    public var body: some View {
        ZStack {
            if currentActiveSource.isEmpty {
                TVSourceBlankStateView {
                    Task {
                        await viewModel.loadRecommendations(forSource: currentActiveSource)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    HStack(spacing: 26) {
                        ForEach(viewModel.subCategories, id: \.self) { cat in
                            TVCapsuleButton(
                                title: cat,
                                isSelected: viewModel.selectedSubCategory == cat,
                                onFocused: {
                                    viewModel.selectSubCategory(cat)
                                }
                            ) {
                                viewModel.selectSubCategory(cat)
                            }
                        }
                        Spacer()
                    }
                    .padding(.leading, 48)
                    .padding(.trailing, 48)
                    .padding(.top, 32)
                    .padding(.bottom, 8)

                    if viewModel.isLoading && viewModel.items.isEmpty {
                        Spacer()
                        ProgressView("正在探索精选推荐...")
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 36) {
                                ForEach(viewModel.items) { drama in
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
                .task(id: currentActiveSource) {
                    if let initCat = initialCategory, !initCat.isEmpty {
                        viewModel.selectSubCategory(initCat)
                    } else {
                        await viewModel.loadRecommendations(forSource: currentActiveSource)
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedDrama) { drama in
            DramaDetailView(drama: drama)
        }
    }
}
