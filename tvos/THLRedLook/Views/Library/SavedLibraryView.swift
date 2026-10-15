import SwiftUI

public struct SavedLibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var selectedDrama: Drama?

    public enum FocusTarget: Hashable {
        case mainTab(LibraryViewModel.LibraryTab)
        case followFilter(FollowState)
        case clearHistory
        case card(String)
        case emptyAction
    }
    @FocusState private var focusedTarget: FocusTarget?

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)
    ]

    public var focusCategoryTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)? = nil

    public init(focusCategoryTrigger: Int = 0, onRequestFocusTopNav: (() -> Void)? = nil) {
        self.focusCategoryTrigger = focusCategoryTrigger
        self.onRequestFocusTopNav = onRequestFocusTopNav
    }

    public var body: some View {
        ZStack {
            if viewModel.currentSource.isEmpty {
                TVSourceBlankStateView()
            } else {
                VStack(spacing: 20) {
                    HStack(spacing: 32) {
                        ForEach(LibraryViewModel.LibraryTab.allCases) { tab in
                            TVCapsuleButton(
                                title: tab.label,
                                isSelected: viewModel.selectedTab == tab,
                                isFocused: focusedTarget == .mainTab(tab),
                                onUpCommand: {
                                    focusedTarget = nil
                                    onRequestFocusTopNav?()
                                },
                                onDownCommand: {
                                    NSLog("🎯 [FOCUS_TRACE] Library onDownCommand: tab = %@, historyCount = %ld, followCount = %ld", tab.rawValue, viewModel.historyList.count, viewModel.followedList.count)
                                    if tab == .follows {
                                        focusedTarget = .followFilter(viewModel.selectedFollowFilter)
                                    } else {
                                        if let first = viewModel.historyList.first {
                                            focusedTarget = .card(first.drama.id)
                                            NSLog("🎯 [FOCUS_TRACE] Library focusedTarget set to .card(%@)", first.drama.id)
                                        } else {
                                            focusedTarget = .emptyAction
                                            NSLog("🎯 [FOCUS_TRACE] Library historyList is EMPTY, focusedTarget set to .emptyAction")
                                        }
                                    }
                                }
                            ) {
                                viewModel.selectedTab = tab
                            }
                            .focused($focusedTarget, equals: .mainTab(tab))
                        }

                        Spacer()

                        if viewModel.selectedTab == .history && !viewModel.historyList.isEmpty {
                            TVButton(
                                title: "清空历史",
                                icon: "trash",
                                isFocused: focusedTarget == .clearHistory,
                                onUpCommand: {
                                    focusedTarget = nil
                                    onRequestFocusTopNav?()
                                },
                                onDownCommand: {
                                    if let first = viewModel.historyList.first {
                                        focusedTarget = .card(first.drama.id)
                                    } else {
                                        focusedTarget = .emptyAction
                                    }
                                }
                            ) {
                                viewModel.clearHistory()
                            }
                            .focused($focusedTarget, equals: .clearHistory)
                            .padding(.top, 4)
                            .padding(.trailing, 6)
                        }
                    }
                    .padding(.leading, 48)
                    .padding(.trailing, 48)
                    .padding(.top, 28)
                    .focusSection()
                    .defaultFocus($focusedTarget, .mainTab(.history))

                    if viewModel.selectedTab == .follows {
                        HStack(spacing: 24) {
                            ForEach([FollowState.watching, FollowState.wishlist, FollowState.watched, FollowState.updated]) { state in
                                TVCapsuleButton(
                                    title: state.label,
                                    isSelected: viewModel.selectedFollowFilter == state,
                                    isFocused: focusedTarget == .followFilter(state),
                                    onUpCommand: {
                                        focusedTarget = .mainTab(.follows)
                                    },
                                    onDownCommand: {
                                        if let first = viewModel.followedList.first {
                                            focusedTarget = .card(first.id)
                                        } else {
                                            focusedTarget = .emptyAction
                                        }
                                    }
                                ) {
                                    viewModel.selectedFollowFilter = state
                                }
                                .focused($focusedTarget, equals: .followFilter(state))
                            }
                            Spacer()
                        }
                        .padding(.leading, 48)
                        .padding(.trailing, 48)
                        .padding(.top, 4)
                    }

                    // 列表内容
                    ScrollView {
                        if viewModel.selectedTab == .history {
                            if viewModel.historyList.isEmpty {
                                VStack(spacing: 20) {
                                    Spacer()
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 64))
                                        .foregroundColor(TVTheme.primary.opacity(0.8))
                                    Text("暂无观看记录，快去探索短剧吧")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    TVButton(
                                        title: "去探索短剧",
                                        icon: "sparkles.tv",
                                        isFocused: focusedTarget == .emptyAction,
                                        onUpCommand: {
                                            focusedTarget = .mainTab(.history)
                                        }
                                    ) {
                                        onRequestFocusTopNav?()
                                    }
                                    .focused($focusedTarget, equals: .emptyAction)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, minHeight: 400)
                            } else {
                                LazyVGrid(columns: columns, spacing: 36) {
                                    ForEach(Array(viewModel.historyList.enumerated()), id: \.element.id) { index, entry in
                                        DramaCardView(
                                            drama: entry.drama,
                                            isFocused: focusedTarget == .card(entry.drama.id),
                                            watchProgress: entry.progressPercent,
                                            progressText: entry.progressLabel,
                                            onUpCommand: (index < 6) ? {
                                                focusedTarget = .mainTab(.history)
                                            } : nil
                                        ) {
                                            selectedDrama = entry.drama
                                        }
                                        .focused($focusedTarget, equals: .card(entry.drama.id))
                                    }
                                }
                                .padding(.horizontal, 48)
                                .padding(.vertical, 24)
                            }
                        } else {
                            if viewModel.followedList.isEmpty {
                                VStack(spacing: 20) {
                                    Spacer()
                                    Image(systemName: "bookmark")
                                        .font(.system(size: 64))
                                        .foregroundColor(TVTheme.primary.opacity(0.8))
                                    Text("暂无追剧记录")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    TVButton(
                                        title: "去探索短剧",
                                        icon: "sparkles.tv",
                                        isFocused: focusedTarget == .emptyAction,
                                        onUpCommand: {
                                            focusedTarget = .followFilter(viewModel.selectedFollowFilter)
                                        }
                                    ) {
                                        onRequestFocusTopNav?()
                                    }
                                    .focused($focusedTarget, equals: .emptyAction)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, minHeight: 400)
                            } else {
                                LazyVGrid(columns: columns, spacing: 36) {
                                    ForEach(Array(viewModel.followedList.enumerated()), id: \.element.id) { index, drama in
                                        DramaCardView(
                                            drama: drama,
                                            isFocused: focusedTarget == .card(drama.id),
                                            onUpCommand: (index < 6) ? {
                                                focusedTarget = .followFilter(viewModel.selectedFollowFilter)
                                            } : nil
                                        ) {
                                            selectedDrama = drama
                                        }
                                        .focused($focusedTarget, equals: .card(drama.id))
                                    }
                                }
                                .padding(.horizontal, 48)
                                .padding(.vertical, 24)
                            }
                        }
                    }
                    .focusSection()
                }
            }
        }
        .fullScreenCover(item: $selectedDrama) { drama in
            DramaDetailView(drama: drama)
        }
        .onChange(of: focusedTarget) { target in
            NSLog("🎯 [FOCUS_TRACE] Library focusedTarget = %@", String(describing: target))
        }
        .onChange(of: focusCategoryTrigger) { _ in
            focusedTarget = .mainTab(viewModel.selectedTab)
            NSLog("🎯 [FOCUS_TRACE] Library 收到导航栏向下指令 -> 精确聚焦Tab: %@", viewModel.selectedTab.rawValue)
        }
    }
}
