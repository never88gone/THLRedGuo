import SwiftUI

public struct RankingsView: View {
    @StateObject private var viewModel = RankingsViewModel()
    @EnvironmentObject private var jsService: JSSourceService
    @EnvironmentObject private var store: LocalStore
    @State private var selectedDrama: Drama?
    @State private var pendingNextRow: String?
    @State private var pendingBoardFocus = false
    @State private var pendingCardFocus = false
    @State private var autoSelectBoardTask: Task<Void, Never>?

    public enum FocusTarget: Hashable {
        case board(String)
        case card(String)
        case retryButton
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
                    boardsHeader

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
                            TVButton(
                                title: "重新加载榜单",
                                icon: "arrow.clockwise",
                                isFocused: focusedTarget == .retryButton,
                                onUpCommand: {
                                    focusSelectedBoard()
                                }
                            ) {
                                Task {
                                    await viewModel.loadBoards(forSource: currentActiveSource)
                                    await viewModel.loadRankings()
                                }
                            }
                            .focused($focusedTarget, equals: .retryButton)
                            .accessibilityIdentifier("ranking.retry")
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
                                                focusSelectedBoard()
                                                NSLog("🎯 [FOCUS_TRACE] Rankings 卡片第 1 行按向上 -> 精确回到当前榜单")
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
                                        if index >= viewModel.items.count - 8 {
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
            if pendingCardFocus, let first = items.first {
                pendingCardFocus = false
                focusedTarget = .card(first.id)
                NSLog("🎯 [FOCUS_TRACE] Rankings pendingCardFocus -> 成功聚焦首项卡片: %@", first.id)
            } else if case .card(let currentId) = focusedTarget {
                // 如果当前选中的卡片在内容刷新后不存在，平滑对齐到新内容的第一项
                if !items.contains(where: { $0.id == currentId }), let first = items.first {
                    focusedTarget = .card(first.id)
                    NSLog("🎯 [FOCUS_TRACE] Rankings 内容切换平滑落焦首项卡片: %@", first.id)
                }
            }
            NSLog("🎯 [FOCUS_TRACE] Rankings viewModel.items updated: count = %ld, firstId = %@", items.count, items.first?.id ?? "nil")
        }
        .onChange(of: focusedTarget) { target in
            if let pendingNextRow, target != .card(pendingNextRow) { self.pendingNextRow = nil }
            if case .card(let id) = target,
               let index = viewModel.items.firstIndex(where: { $0.id == id }),
               index >= viewModel.items.count - columns.count {
                Task { await viewModel.loadMore() }
            }
            if case .board(let id) = target {
                if let board = viewModel.boards.first(where: { $0.id == id }) {
                    scheduleAutoSelectBoard(board)
                }
            } else {
                cancelAutoSelectBoard()
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
        .onExitCommand {
            if selectedDrama == nil {
                cancelAutoSelectBoard()
                focusedTarget = nil
                onRequestFocusTopNav?()
            }
        }
    }

    private var selectedBoardID: String {
        viewModel.selectedBoard?.id ?? viewModel.boards.first(where: \.isAllowedOnTV)?.id ?? ""
    }

    private var boardsHeader: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(viewModel.boards.filter(\.isAllowedOnTV)) { board in
                        TVRankingBoardButton(
                            board: board,
                            isSelected: viewModel.selectedBoard?.id == board.id,
                            isFocused: focusedTarget == .board(board.id),
                            onUpCommand: {
                                cancelAutoSelectBoard()
                                focusedTarget = nil
                                onRequestFocusTopNav?()
                            },
                            onDownCommand: {
                                cancelAutoSelectBoard()
                                focusFirstCard()
                            },
                            onLeftCommand: nil,
                            onRightCommand: nil
                        ) {
                            pendingNextRow = nil
                            cancelAutoSelectBoard()
                            viewModel.selectBoard(board)
                        }
                        .id("board_\(board.id)")
                        .focused($focusedTarget, equals: .board(board.id))
                        .accessibilityIdentifier("ranking.board.\(board.id)")
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
            .clipShape(Rectangle().inset(by: -30))
            .defaultFocus($focusedTarget, .board(selectedBoardID))
            .onChange(of: focusedTarget) { target in
                if case .board(let id) = target {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        proxy.scrollTo("board_\(id)", anchor: .center)
                    }
                }
            }
        }
    }

    private func focusSelectedBoard() {
        guard let target = viewModel.selectedBoard?.id ?? viewModel.boards.first(where: \.isAllowedOnTV)?.id else { return }
        pendingBoardFocus = false
        focusedTarget = .board(target)
    }

    private func focusFirstCard() {
        if let first = viewModel.items.first {
            pendingCardFocus = false
            focusedTarget = .card(first.id)
            NSLog("🎯 [FOCUS_TRACE] Rankings onDownCommand -> 成功聚焦首项卡片: %@", first.id)
        } else if viewModel.errorMessage != nil {
            focusedTarget = .retryButton
        } else {
            pendingCardFocus = true
            NSLog("🎯 [FOCUS_TRACE] Rankings onDownCommand -> items 为空，等待加载完成并落焦")
        }
    }

    private func scheduleAutoSelectBoard(_ board: RankingBoard) {
        guard viewModel.selectedBoard?.id != board.id else { return }
        autoSelectBoardTask?.cancel()
        autoSelectBoardTask = Task { @MainActor in
            // 防抖 200ms：快速滑动掠过时不频繁发请求，一旦焦点停留自动切换内容，无需用户额外按确认键
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            if case .board(let currentId) = focusedTarget, currentId == board.id {
                pendingNextRow = nil
                viewModel.selectBoard(board)
                NSLog("🎯 [FOCUS_TRACE] Rankings 标题切换自动更新内容: %@", board.name)
            }
        }
    }

    private func cancelAutoSelectBoard() {
        autoSelectBoardTask?.cancel()
        autoSelectBoardTask = nil
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
                Task { await viewModel.loadMore() }
            }
            return
        }
        let nextID = viewModel.items[min(index + columns.count, viewModel.items.count - 1)].id
        pendingNextRow = nil
        guard selectedDrama == nil else { return }
        focusedTarget = .card(nextID)
    }
}
