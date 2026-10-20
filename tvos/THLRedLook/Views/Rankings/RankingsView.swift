import SwiftUI

public struct RankingsView: View {
    @StateObject private var viewModel = RankingsViewModel()
    @EnvironmentObject private var jsService: JSSourceService
    @EnvironmentObject private var store: LocalStore
    @State private var selectedDrama: Drama?
    @State private var pendingNextRow: String?
    @State private var pendingBoardFocus = false

    public enum FocusTarget: Hashable {
        case board(String)
        case card(String)
    }
    @FocusState private var focusedTarget: FocusTarget?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 32), count: 6)

    public var focusCategoryTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)? = nil

    public init(focusCategoryTrigger: Int = 0, onRequestFocusTopNav: (() -> Void)? = nil) {
        self.focusCategoryTrigger = focusCategoryTrigger
        self.onRequestFocusTopNav = onRequestFocusTopNav
    }

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
                                    isFocused: focusedTarget == .board(board.id),
                                    onUpCommand: {
                                        focusedTarget = nil
                                        onRequestFocusTopNav?()
                                    },
                                    onDownCommand: {
                                        if let first = viewModel.items.first {
                                            focusedTarget = .card(first.id)
                                            NSLog("🎯 [FOCUS_TRACE] Rankings onDownCommand -> 成功聚焦首项卡片: %@", first.id)
                                        } else {
                                            NSLog("🎯 [FOCUS_TRACE] Rankings onDownCommand -> items 为空，等待加载完成")
                                        }
                                    },
                                    onLeftCommand: { moveBoard(from: board, offset: -1) },
                                    onRightCommand: { moveBoard(from: board, offset: 1) }
                                ) {
                                    viewModel.selectBoard(board)
                                }
                                .focused($focusedTarget, equals: .board(board.id))
                                .accessibilityIdentifier("ranking.board.\(board.id)")
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                    }
                    .clipShape(Rectangle().inset(by: -30))
                    .focusSection()
                    .defaultFocus($focusedTarget, .board(viewModel.selectedBoard?.id ?? viewModel.boards.first(where: \.isAllowedOnTV)?.id ?? ""))

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
                            Text(viewModel.errorMessage ?? "当前榜单暂无可展示剧集")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            TVButton(title: "重新加载榜单", icon: "arrow.clockwise") {
                                Task {
                                    await viewModel.loadBoards(forSource: currentActiveSource)
                                    await viewModel.loadRankings()
                                }
                            }
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 36) {
                                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, drama in
                                    ZStack(alignment: .topLeading) {
                                        DramaCardView(
                                            drama: drama,
                                            isFocused: focusedTarget == .card(drama.id),
                                            onUpCommand: (index < columns.count) ? {
                                                let targetBoard = viewModel.selectedBoard?.id ?? viewModel.boards.first(where: \.isAllowedOnTV)?.id ?? ""
                                                focusedTarget = .board(targetBoard)
                                                NSLog("🎯 [FOCUS_TRACE] Rankings 卡片第 1 行按向上 -> 精确回到当前榜单: %@", targetBoard)
                                            } : nil,
                                            onDownCommand: index + columns.count >= viewModel.items.count && viewModel.hasMore ? {
                                                focusNextRow(after: drama.id)
                                            } : nil
                                        ) {
                                            selectedDrama = drama
                                        }
                                        .focused($focusedTarget, equals: .card(drama.id))
                                        .accessibilityIdentifier("ranking.result.\(index)")

                                        // 前三名金银铜徽章
                                        Text("\(viewModel.ranks[drama.id] ?? index + 1)")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(.white)
                                            .frame(width: 28, height: 28)
                                            .background(
                                                index == 0 ? Color.yellow : (index == 1 ? Color.gray : (index == 2 ? Color.orange : Color.black.opacity(0.6)))
                                            )
                                            .clipShape(Circle())
                                            .padding(8)
                                    }
                                    .onAppear {
                                        if index >= viewModel.items.count - 4 {
                                            Task { await viewModel.loadMore() }
                                        }
                                    }
                                }
                                if viewModel.isLoadingMore { ProgressView("正在加载更多榜单剧集...") }
                                if let message = viewModel.errorMessage {
                                    Text(message).foregroundColor(.secondary)
                                    TVButton(title: "刷新榜单", icon: "arrow.clockwise") {
                                        Task { await viewModel.loadRankings() }
                                    }
                                }
                            }
                            .padding(.horizontal, 48)
                            .padding(.vertical, 24)
                        }
                        .focusSection()
                        .defaultFocus($focusedTarget, viewModel.items.first.map { FocusTarget.card($0.id) })
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
        .onChange(of: viewModel.items) { items in
            finishPendingRowFocus()
            NSLog("🎯 [FOCUS_TRACE] Rankings viewModel.items updated: count = %ld, firstId = %@", items.count, items.first?.id ?? "nil")
        }
        .onChange(of: focusedTarget) { target in
            if let pendingNextRow, target != .card(pendingNextRow) { self.pendingNextRow = nil }
            if case .card(let id) = target,
               let index = viewModel.items.firstIndex(where: { $0.id == id }),
               index >= viewModel.items.count - columns.count {
                Task { await viewModel.loadMore() }
            }
            NSLog("🎯 [FOCUS_TRACE] Rankings focusedTarget = %@", String(describing: target))
        }
        .onChange(of: viewModel.selectedBoard?.id) { _, _ in
            if pendingBoardFocus { focusSelectedBoard() }
        }
        .onChange(of: focusCategoryTrigger) { _, _ in
            pendingBoardFocus = true
            DispatchQueue.main.async { focusSelectedBoard() }
        }
    }

    private func focusSelectedBoard() {
        guard let target = viewModel.selectedBoard?.id ?? viewModel.boards.first(where: \.isAllowedOnTV)?.id else { return }
        pendingBoardFocus = false
        focusedTarget = .board(target)
    }

    private func moveBoard(from board: RankingBoard, offset: Int) {
        let boards = viewModel.boards.filter(\.isAllowedOnTV)
        guard let index = boards.firstIndex(where: { $0.id == board.id }) else { return }
        let target = boards[min(max(index + offset, 0), boards.count - 1)]
        pendingNextRow = nil
        viewModel.selectBoard(target)
        focusedTarget = .board(target.id)
    }

    private func focusNextRow(after id: String) {
        pendingNextRow = id
        Task {
            await viewModel.loadMore()
            finishPendingRowFocus()
        }
    }

    private func finishPendingRowFocus() {
        guard let id = pendingNextRow, focusedTarget == .card(id),
              let index = viewModel.items.firstIndex(where: { $0.id == id }) else { return }
        guard index + columns.count < viewModel.items.count else {
            if !viewModel.hasMore || viewModel.errorMessage != nil { pendingNextRow = nil }
            return
        }
        let nextID = viewModel.items[index + columns.count].id
        pendingNextRow = nil
        DispatchQueue.main.async {
            guard focusedTarget == .card(id), selectedDrama == nil else { return }
            focusedTarget = .card(nextID)
        }
    }
}
