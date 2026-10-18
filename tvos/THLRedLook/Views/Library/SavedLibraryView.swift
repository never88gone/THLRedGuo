import SwiftUI

public struct SavedLibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var selectedDrama: Drama?
    @State private var lastOpenedID: String?
    @State private var detailDismissedAt = Date.distantPast
    @State private var showingClearHistory = false
    @State private var focusSequence = 0

    public enum FocusTarget: Hashable {
        case mainTab(LibraryViewModel.LibraryTab)
        case followFilter(FollowState)
        case clearHistory
        case card(String)
        case emptyAction
    }
    @FocusState private var focusedTarget: FocusTarget?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 32), count: 6)
    public var focusCategoryTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)?

    public init(focusCategoryTrigger: Int = 0, onRequestFocusTopNav: (() -> Void)? = nil) {
        self.focusCategoryTrigger = focusCategoryTrigger
        self.onRequestFocusTopNav = onRequestFocusTopNav
    }

    private var dramas: [Drama] {
        viewModel.selectedTab == .history ? viewModel.historyList.map(\.drama) : viewModel.followedList
    }

    private var listHeader: FocusTarget {
        viewModel.selectedTab == .history ? .mainTab(.history) : .followFilter(viewModel.selectedFollowFilter)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 20) {
                HStack(spacing: 32) {
                    ForEach(LibraryViewModel.LibraryTab.allCases) { tab in
                        TVCapsuleButton(
                            title: tab.label,
                            isSelected: viewModel.selectedTab == tab,
                            isFocused: focusedTarget == .mainTab(tab),
                            onUpCommand: requestTopNavigation,
                            onDownCommand: {
                                focus(tab == .follows ? .followFilter(viewModel.selectedFollowFilter) : firstCardTarget, with: proxy)
                            }
                        ) { viewModel.selectedTab = tab }
                        .focused($focusedTarget, equals: .mainTab(tab))
                        .accessibilityIdentifier("library.tab.\(tab.rawValue)")
                    }
                    Spacer()
                    if viewModel.selectedTab == .history && !viewModel.historyList.isEmpty {
                        TVButton(title: "清空历史", icon: "trash", isFocused: focusedTarget == .clearHistory,
                                 onUpCommand: requestTopNavigation,
                                 onDownCommand: { focus(firstCardTarget, with: proxy) }) {
                            showingClearHistory = true
                        }
                        .focused($focusedTarget, equals: .clearHistory)
                        .accessibilityIdentifier("library.clearHistory")
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 28)
                .focusSection()

                if viewModel.selectedTab == .follows {
                    HStack(spacing: 24) {
                        ForEach([FollowState.none, .wishlist, .watching, .watched, .updated]) { state in
                            TVCapsuleButton(
                                title: state == .none ? "全部" : state.label,
                                isSelected: viewModel.selectedFollowFilter == state,
                                isFocused: focusedTarget == .followFilter(state),
                                onUpCommand: { focus(.mainTab(.follows), with: proxy) },
                                onDownCommand: { focus(firstCardTarget, with: proxy) }
                            ) { viewModel.selectedFollowFilter = state }
                            .focused($focusedTarget, equals: .followFilter(state))
                            .accessibilityIdentifier("library.filter.\(state == .none ? "all" : state.rawValue)")
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 48)
                }

                ScrollView {
                    if dramas.isEmpty {
                        VStack(spacing: 24) {
                            Image(systemName: viewModel.selectedTab == .history ? "clock.arrow.circlepath" : "bookmark")
                                .font(.system(size: 64))
                                .foregroundColor(TVTheme.primary)
                            Text(viewModel.selectedTab == .history ? "暂无观看记录" : "暂无收藏记录")
                                .font(.system(size: 29, weight: .medium))
                            TVButton(title: "去探索短剧", icon: "sparkles.tv", isFocused: focusedTarget == .emptyAction,
                                     onUpCommand: { focus(listHeader, with: proxy) }) {
                                requestTopNavigation()
                            }
                            .focused($focusedTarget, equals: .emptyAction)
                            .accessibilityIdentifier("library.emptyAction")
                            .id(FocusTarget.emptyAction)
                        }
                        .frame(maxWidth: .infinity, minHeight: 400)
                    } else {
                        LazyVGrid(columns: columns, spacing: 36) {
                            ForEach(Array(dramas.enumerated()), id: \.element.id) { index, drama in
                                let entry = viewModel.historyList.first { $0.drama.id == drama.id }
                                DramaCardView(
                                    drama: drama,
                                    isFocused: focusedTarget == .card(drama.id),
                                    watchProgress: entry?.progressPercent,
                                    progressText: entry?.progressLabel,
                                    onUpCommand: index < columns.count ? { focus(listHeader, with: proxy) } : nil
                                ) {
                                    lastOpenedID = drama.id
                                    selectedDrama = drama
                                }
                                .focused($focusedTarget, equals: .card(drama.id))
                                .accessibilityIdentifier("library.card.\(drama.id)")
                                .accessibilityValue(entry?.progressLabel ?? "本地收藏")
                                .id(FocusTarget.card(drama.id))
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.vertical, 24)
                    }
                }
                .focusSection()
            }
            .defaultFocus($focusedTarget, .mainTab(viewModel.selectedTab))
            .fullScreenCover(item: $selectedDrama, onDismiss: {
                detailDismissedAt = Date()
                let target = lastOpenedID.flatMap { id in dramas.contains { $0.id == id } ? FocusTarget.card(id) : nil } ?? firstCardTarget
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focus(target, with: proxy) }
            }) { drama in
                DramaDetailView(drama: drama)
            }
            .confirmationDialog("清空当前站源的观看历史？", isPresented: $showingClearHistory, titleVisibility: .visible) {
                Button("清空历史", role: .destructive) { viewModel.clearHistory() }
                Button("取消", role: .cancel) {}
            }
            .onChange(of: showingClearHistory) { _, shown in
                if !shown {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        focus(viewModel.historyList.isEmpty ? .mainTab(.history) : .clearHistory, with: proxy)
                    }
                }
            }
            .onChange(of: focusCategoryTrigger) { _, _ in
                focus(.mainTab(viewModel.selectedTab), with: proxy)
            }
            .onExitCommand {
                guard selectedDrama == nil, !showingClearHistory, Date().timeIntervalSince(detailDismissedAt) > 0.5 else { return }
                requestTopNavigation()
            }
        }
    }

    private var firstCardTarget: FocusTarget {
        dramas.first.map { .card($0.id) } ?? .emptyAction
    }

    private func requestTopNavigation() {
        focusSequence += 1
        focusedTarget = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onRequestFocusTopNav?() }
    }

    private func focus(_ target: FocusTarget, with proxy: ScrollViewProxy) {
        focusSequence += 1
        let sequence = focusSequence
        proxy.scrollTo(target, anchor: .center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard sequence == focusSequence, selectedDrama == nil else { return }
            focusedTarget = target
        }
    }
}
