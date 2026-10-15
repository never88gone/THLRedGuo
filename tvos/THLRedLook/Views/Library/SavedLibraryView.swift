import SwiftUI

public struct SavedLibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var selectedDrama: Drama?
    @FocusState private var focusedMainTab: LibraryViewModel.LibraryTab?
    @FocusState private var focusedFollowFilter: FollowState?
    @FocusState private var focusedDramaId: String?

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)
    ]

    public init() {}

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
                                isSelected: viewModel.selectedTab == tab
                            ) {
                                viewModel.selectedTab = tab
                            }
                            .focused($focusedMainTab, equals: tab)
                        }

                        Spacer()

                        if viewModel.selectedTab == .history && !viewModel.historyList.isEmpty {
                            TVButton(title: "清空历史", icon: "trash") {
                                viewModel.clearHistory()
                            }
                            .padding(.top, 4)
                            .padding(.trailing, 6)
                        }
                    }
                    .padding(.leading, 48)
                    .padding(.trailing, 48)
                    .padding(.top, 28)
                    .focusSection()
                    .defaultFocus($focusedMainTab, viewModel.selectedTab)

                    if viewModel.selectedTab == .follows {
                        HStack(spacing: 24) {
                            ForEach([FollowState.watching, FollowState.wishlist, FollowState.watched, FollowState.updated]) { state in
                                TVCapsuleButton(
                                    title: state.label,
                                    isSelected: viewModel.selectedFollowFilter == state
                                ) {
                                    viewModel.selectedFollowFilter = state
                                }
                                .focused($focusedFollowFilter, equals: state)
                            }
                            Spacer()
                        }
                        .padding(.leading, 48)
                        .padding(.trailing, 48)
                        .padding(.top, 4)
                        .focusSection()
                        .defaultFocus($focusedFollowFilter, viewModel.selectedFollowFilter)
                    }

                    // 列表内容
                    ScrollView {
                        if viewModel.selectedTab == .history {
                            if viewModel.historyList.isEmpty {
                                VStack(spacing: 16) {
                                    Spacer()
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 56))
                                        .foregroundColor(.secondary)
                                    Text("暂无观看记录，快去探索短剧吧")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, minHeight: 400)
                            } else {
                                LazyVGrid(columns: columns, spacing: 36) {
                                    ForEach(viewModel.historyList) { entry in
                                        DramaCardView(
                                            drama: entry.drama,
                                            watchProgress: entry.progressPercent,
                                            progressText: entry.progressLabel
                                        ) {
                                            selectedDrama = entry.drama
                                        }
                                        .focused($focusedDramaId, equals: entry.drama.id)
                                    }
                                }
                                .padding(.horizontal, 48)
                                .padding(.vertical, 24)
                            }
                        } else {
                            if viewModel.followedList.isEmpty {
                                VStack(spacing: 16) {
                                    Spacer()
                                    Image(systemName: "bookmark")
                                        .font(.system(size: 56))
                                        .foregroundColor(.secondary)
                                    Text("暂无追剧记录")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, minHeight: 400)
                            } else {
                                LazyVGrid(columns: columns, spacing: 36) {
                                    ForEach(viewModel.followedList) { drama in
                                        DramaCardView(drama: drama) {
                                            selectedDrama = drama
                                        }
                                        .focused($focusedDramaId, equals: drama.id)
                                    }
                                }
                                .padding(.horizontal, 48)
                                .padding(.vertical, 24)
                            }
                        }
                    }
                    .focusSection()
                    .defaultFocus($focusedDramaId, viewModel.selectedTab == .history ? viewModel.historyList.first?.drama.id : viewModel.followedList.first?.id)
                }
            }
        }
        .fullScreenCover(item: $selectedDrama) { drama in
            DramaDetailView(drama: drama)
        }
        .onChange(of: focusedMainTab) { t in
            NSLog("🎯 [FOCUS_TRACE] Library focusedMainTab = %@", t?.rawValue ?? "nil")
        }
        .onChange(of: focusedFollowFilter) { f in
            NSLog("🎯 [FOCUS_TRACE] Library focusedFollowFilter = %@", f?.rawValue ?? "nil")
        }
        .onChange(of: focusedDramaId) { d in
            NSLog("🎯 [FOCUS_TRACE] Library focusedDramaId = %@", d ?? "nil")
        }
    }
}
