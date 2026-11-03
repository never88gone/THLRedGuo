import SwiftUI

public struct SavedLibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @ObservedObject private var account = HongguoAccountModel.shared
    @State private var selectedDrama: Drama?
    @State private var lastOpenedID: String?
    @State private var detailDismissedAt = Date.distantPast
    @State private var showingClearHistory = false
    @State private var showingLogin = false
    @State private var showingAccountMenu = false
    @State private var openedDebugLogin = false
    @State private var focusSequence = 0

    public enum FocusTarget: Hashable {
        case mainTab(LibraryViewModel.LibraryTab)
        case followFilter(FollowState)
        case clearHistory
        case account
        case refresh
        case card(String)
        case emptyAction
    }
    @FocusState private var focusedTarget: FocusTarget?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: 5)
    public var focusCategoryTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)?
    public var onRequestFocusContent: (() -> Void)?

    public init(focusCategoryTrigger: Int = 0, onRequestFocusTopNav: (() -> Void)? = nil, onRequestFocusContent: (() -> Void)? = nil) {
        self.focusCategoryTrigger = focusCategoryTrigger
        self.onRequestFocusTopNav = onRequestFocusTopNav
        self.onRequestFocusContent = onRequestFocusContent
    }

    private var entries: [WatchEntry] {
        account.loggedIn ? viewModel.accountLists[viewModel.selectedTab] ?? [] : viewModel.historyList
    }
    private var dramas: [Drama] {
        account.loggedIn || viewModel.selectedTab == .history ? entries.map(\.drama) : viewModel.followedList
    }
    private var listHeader: FocusTarget {
        !account.loggedIn && viewModel.selectedTab == .follows ? .followFilter(viewModel.selectedFollowFilter) : .mainTab(viewModel.selectedTab)
    }
    private var firstCardTarget: FocusTarget { dramas.first.map { .card($0.id) } ?? .emptyAction }

    public var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 24) {
                HStack {
                    Text("我的").font(.system(size: 42, weight: .bold))
                    Spacer()
                    Button {
                        if account.loggedIn { showingAccountMenu = true } else { showingLogin = true }
                    } label: {
                        HStack(spacing: 16) {
                            if account.loggedIn {
                                avatar
                                Text(account.account?.nickname ?? "红果用户").lineLimit(1)
                            } else { Label("登录", systemImage: "person.crop.circle") }
                        }.font(.system(size: 29, weight: .semibold))
                    }
                    .focused($focusedTarget, equals: .account)
                    .accessibilityIdentifier(account.loggedIn ? "hongguo-account-menu" : "hongguo-account-login")
                    .onMoveCommand { direction in
                        if direction == .up { requestTopNavigation() }
                        if direction == .down { focus(firstCardTarget, with: proxy) }
                        if direction == .left { focus(.mainTab(viewModel.selectedTab), with: proxy) }
                    }
                }.padding(.horizontal, 48).padding(.top, 28)

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(LibraryViewModel.LibraryTab.allCases) { tab in
                            TVCapsuleButton(title: tab == .follows ? "追剧" : "历史记录",
                                isSelected: viewModel.selectedTab == tab,
                                isFocused: focusedTarget == .mainTab(tab),
                                onUpCommand: tab == .history ? requestTopNavigation : nil,
                                onDownCommand: nil,
                                onRightCommand: { focus(firstCardTarget, with: proxy) }) { viewModel.selectedTab = tab }
                            .focused($focusedTarget, equals: .mainTab(tab))
                            .accessibilityIdentifier("library.tab.\(tab.rawValue)")
                        }
                        Spacer()
                    }.frame(width: 230).padding(.leading, 48).focusSection()
                    VStack(spacing: 20) {
                        HStack {
                            Text(account.loggedIn ? "红果账号" : "本机记录").foregroundStyle(.secondary)
                            Spacer()
                            if account.loggedIn {
                                TVButton(title: "刷新", icon: "arrow.clockwise", isFocused: focusedTarget == .refresh,
                                    onUpCommand: { focus(.account, with: proxy) }, onDownCommand: { focus(firstCardTarget, with: proxy) }) {
                                    Task { await viewModel.loadAccount(viewModel.selectedTab, refresh: true) }
                                }.focused($focusedTarget, equals: .refresh).accessibilityIdentifier("library.refresh")
                            } else if viewModel.selectedTab == .history && !entries.isEmpty {
                                TVButton(title: "清空历史", icon: "trash", isFocused: focusedTarget == .clearHistory,
                                    onUpCommand: { focus(.account, with: proxy) }, onDownCommand: { focus(firstCardTarget, with: proxy) }) {
                                    showingClearHistory = true
                                }.focused($focusedTarget, equals: .clearHistory).accessibilityIdentifier("library.clearHistory")
                            }
                        }.font(.system(size: 29))
                        if !account.loggedIn && viewModel.selectedTab == .follows {
                            HStack(spacing: 20) {
                                ForEach([FollowState.none, .wishlist, .watching, .watched, .updated]) { state in
                                    TVCapsuleButton(title: state == .none ? "全部" : state.label,
                                        isSelected: viewModel.selectedFollowFilter == state,
                                        isFocused: focusedTarget == .followFilter(state),
                                        onUpCommand: { focus(.account, with: proxy) },
                                        onDownCommand: { focus(firstCardTarget, with: proxy) }) { viewModel.selectedFollowFilter = state }
                                    .focused($focusedTarget, equals: .followFilter(state))
                                    .accessibilityIdentifier("library.filter.\(state == .none ? "all" : state.rawValue)")
                                }
                                Spacer()
                            }
                        }
                        if account.loggedIn && viewModel.loadingTabs.contains(viewModel.selectedTab) { ProgressView("正在获取账号列表") }
                        if account.loggedIn, let error = viewModel.accountErrors[viewModel.selectedTab] {
                            Text(error).foregroundStyle(.orange).font(.system(size: 29)).accessibilityIdentifier("library.error")
                        }
                        ScrollView {
                            if dramas.isEmpty {
                                VStack(spacing: 24) {
                                    Text(emptyMessage).font(.system(size: 29, weight: .medium))
                                    TVButton(title: account.loggedIn ? "刷新列表" : "去探索短剧", icon: account.loggedIn ? "arrow.clockwise" : "sparkles.tv",
                                        isFocused: focusedTarget == .emptyAction, onUpCommand: { focus(.account, with: proxy) }) {
                                        if account.loggedIn { Task { await viewModel.loadAccount(viewModel.selectedTab, refresh: true) } }
                                        else { requestTopNavigation() }
                                    }.focused($focusedTarget, equals: .emptyAction).accessibilityIdentifier("library.emptyAction").id(FocusTarget.emptyAction)
                                }.frame(maxWidth: .infinity, minHeight: 300)
                            } else {
                                LazyVGrid(columns: columns, spacing: 36) {
                                    ForEach(Array(dramas.enumerated()), id: \.element.id) { index, drama in
                                        let entry = viewModel.selectedTab == .history ? entries.first { $0.drama.id == drama.id } : nil
                                        DramaCardView(drama: drama, isFocused: focusedTarget == .card(drama.id),
                                            watchProgress: entry?.progressPercent, progressText: entry?.progressLabel,
                                            onUpCommand: index < columns.count ? { focus(.account, with: proxy) } : nil,
                                            onLeftCommand: index % columns.count == 0 ? { focus(.mainTab(viewModel.selectedTab), with: proxy) } : nil) {
                                            lastOpenedID = drama.id; selectedDrama = drama
                                        }.focused($focusedTarget, equals: .card(drama.id))
                                        .accessibilityIdentifier("library.card.\(drama.id)")
                                        .accessibilityValue(entry?.progressLabel ?? (account.loggedIn ? "账号追剧" : "本地收藏"))
                                        .id(FocusTarget.card(drama.id))
                                        .contextMenu {
                                            if !account.loggedIn {
                                                Button(role: .destructive) {
                                                    if viewModel.selectedTab == .follows { viewModel.removeFollow(dramaId: drama.id) }
                                                    else { viewModel.removeHistory(dramaId: drama.id) }
                                                } label: { Label(viewModel.selectedTab == .follows ? "取消追剧" : "删除观看记录", systemImage: "trash") }
                                            }
                                        }
                                    }
                                }.padding(.vertical, 24)
                            }
                        }.focusSection()
                    }.padding(.trailing, 48)
                }
            }
            .defaultFocus($focusedTarget, .mainTab(viewModel.selectedTab))
            .fullScreenCover(item: $selectedDrama, onDismiss: {
                detailDismissedAt = Date()
                let target = lastOpenedID.flatMap { id in dramas.contains { $0.id == id } ? FocusTarget.card(id) : nil } ?? firstCardTarget
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focus(target, with: proxy) }
            }) { drama in DramaDetailView(drama: drama) }
            .fullScreenCover(isPresented: $showingLogin, onDismiss: {
                if !account.loggedIn || !account.verified { account.cancel() }
                onRequestFocusContent?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus(.account, with: proxy) }
            }) { TVLoginOptionsView() }
            .confirmationDialog("红果账号", isPresented: $showingAccountMenu, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { account.logout(); focusedTarget = .account }
                Button("取消", role: .cancel) { focusedTarget = .account }
            } message: { Text("退出后显示本机追剧与历史，原有资料会保留。") }
            .confirmationDialog("清空当前站源的观看历史？", isPresented: $showingClearHistory, titleVisibility: .visible) {
                Button("清空历史", role: .destructive) { viewModel.clearHistory(); focusedTarget = .mainTab(.history) }
                Button("取消", role: .cancel) { focusedTarget = .clearHistory }
            }
            .task(id: HongguoAccountVault.shared.snapshot.revision) {
                await account.verify()
                await viewModel.loadAccount(viewModel.selectedTab)
            }
            .onChange(of: viewModel.selectedTab) { _, tab in Task { await viewModel.loadAccount(tab) } }
            .onChange(of: focusCategoryTrigger) { _, _ in
                focus(.mainTab(viewModel.selectedTab), with: proxy)
                #if DEBUG
                if !openedDebugLogin && CommandLine.arguments.contains("-openAccountLogin") {
                    openedDebugLogin = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showingLogin = true }
                }
                #endif
            }
            .onExitCommand {
                guard selectedDrama == nil, !showingClearHistory, !showingLogin, !showingAccountMenu, Date().timeIntervalSince(detailDismissedAt) > 0.5 else { return }
                requestTopNavigation()
            }
        }
    }

    private var emptyMessage: String {
        if account.loggedIn {
            if viewModel.loadingTabs.contains(viewModel.selectedTab) { return "正在获取账号列表" }
            if viewModel.accountErrors[viewModel.selectedTab] != nil { return "暂时无法读取账号列表" }
        }
        return viewModel.selectedTab == .history ? "暂无观看记录" : "暂无追剧记录"
    }
    private var avatar: some View {
        Group {
            if ProcessInfo.processInfo.environment["DISABLE_REMOTE_IMAGES"] != "1", let raw = account.account?.avatar, let url = URL(string: raw), url.scheme == "https" {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").resizable() }
            } else { Image(systemName: "person.crop.circle.fill").resizable() }
        }.frame(width: 48, height: 48).clipShape(Circle())
    }
    private func requestTopNavigation() { focusSequence += 1; focusedTarget = nil; onRequestFocusTopNav?() }
    private func focus(_ target: FocusTarget, with proxy: ScrollViewProxy) {
        focusSequence += 1; let sequence = focusSequence
        if case .card = target { proxy.scrollTo(target, anchor: .center) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard sequence == focusSequence, selectedDrama == nil else { return }
            focusedTarget = target
        }
    }
}
