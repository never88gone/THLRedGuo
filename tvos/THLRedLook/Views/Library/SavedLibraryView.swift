import SwiftUI

public struct SavedLibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @ObservedObject private var account = HongguoAccountModel.shared
    @State private var selectedDrama: Drama?
    @State private var selectedAnchor: Anchor?
    @State private var lastOpenedID: String?
    @State private var lastAnchorID: String?
    @State private var anchorFollowingChanged = false
    @State private var detailDismissedAt = Date.distantPast
    @State private var showingClearHistory = false
    @State private var showingLogin = false
    @State private var showingAccountMenu = false
    @State private var openedDebugLogin = false
    @State private var focusSequence = 0

    @FocusState private var focusedTarget: LibraryFocusTarget?
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
        viewModel.officialAccount ? HongguoAccountLibraryCache.shared.entries(history: viewModel.selectedTab == .history) : viewModel.historyList
    }
    private var dramas: [Drama] {
        if viewModel.selectedTab == .liked {
            return viewModel.likedList
        }
        if viewModel.selectedTab == .anchors {
            return []
        }
        return viewModel.officialAccount || viewModel.selectedTab == .history ? entries.map(\.drama) : viewModel.followedList
    }
    private struct VideoRow: Identifiable {
        let id: String
        let drama: Drama
        let subtitle: String?
    }
    private var videoRows: [VideoRow] {
        if viewModel.officialAccount && viewModel.selectedTab == .liked {
            return viewModel.officialLikes.compactMap { row in
                row.drama.map { VideoRow(id: row.id, drama: $0, subtitle: row.subtitle) }
            }
        }
        return dramas.map { VideoRow(id: $0.id, drama: $0, subtitle: nil) }
    }
    private var listHeader: LibraryFocusTarget {
        !viewModel.officialAccount && viewModel.selectedTab == .follows ? .followFilter(viewModel.selectedFollowFilter) : .mainTab(viewModel.selectedTab)
    }
    private var firstCardTarget: LibraryFocusTarget {
        if viewModel.selectedTab == .anchors {
            return viewModel.followedAnchorsList.first.map { .anchorCard($0.id) } ?? .emptyAction
        }
        return videoRows.first.map { .card($0.id) } ?? .emptyAction
    }

    public var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 24) {
                headerView(proxy: proxy)

                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(LibraryTab.allCases) { tab in
                            TVCapsuleButton(
                                title: tab.label,
                                isSelected: viewModel.selectedTab == tab,
                                isFocused: focusedTarget == .mainTab(tab),
                                isCompact: true,
                                onFocused: {
                                    if viewModel.selectedTab != tab {
                                        viewModel.selectedTab = tab
                                    }
                                },
                                onUpCommand: tab == .history ? requestTopNavigation : nil,
                                onDownCommand: nil,
                                onRightCommand: { focus(firstCardTarget, with: proxy) }
                            ) { viewModel.selectedTab = tab }
                            .focused($focusedTarget, equals: .mainTab(tab))
                            .accessibilityIdentifier("library.tab.\(tab.rawValue)")
                        }
                        Spacer()
                    }
                    .frame(width: 140)
                    .padding(.leading, 48)
                    .focusSection()

                    VStack(spacing: 20) {
                        HStack {
                            Text(viewModel.officialAccount ? "红果账号" : "本机记录").foregroundStyle(.secondary)
                            Spacer()
                            if viewModel.officialAccount {
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
                        }
                        .font(.system(size: 24))
                        .padding(.horizontal, 20)

                        if !viewModel.officialAccount && viewModel.selectedTab == .follows {
                            HStack(spacing: 16) {
                                ForEach([FollowState.none, .wishlist, .watching, .watched, .updated]) { state in
                                    TVCapsuleButton(
                                        title: state == .none ? "全部" : state.label,
                                        isSelected: viewModel.selectedFollowFilter == state,
                                        isFocused: focusedTarget == .followFilter(state),
                                        isCompact: true,
                                        onFocused: {
                                            if viewModel.selectedFollowFilter != state {
                                                viewModel.selectedFollowFilter = state
                                            }
                                        },
                                        onUpCommand: { focus(.account, with: proxy) },
                                        onDownCommand: { focus(firstCardTarget, with: proxy) }
                                    ) { viewModel.selectedFollowFilter = state }
                                    .focused($focusedTarget, equals: .followFilter(state))
                                    .accessibilityIdentifier("library.filter.\(state == .none ? "all" : state.rawValue)")
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }
                        if viewModel.officialAccount && viewModel.loadingTabs.contains(viewModel.selectedTab) { ProgressView("正在获取账号列表") }
                        if viewModel.officialAccount, let error = viewModel.accountErrors[viewModel.selectedTab] {
                            Text(error).foregroundStyle(.orange).font(.system(size: 24)).padding(.horizontal, 20).accessibilityIdentifier("library.error")
                        }
                        ScrollView {
                          VStack(spacing: 24) {
                            if viewModel.selectedTab == .anchors {
                                if viewModel.followedAnchorsList.isEmpty {
                                    VStack(spacing: 24) {
                                        Text(emptyMessage).font(.system(size: 29, weight: .medium))
                                        TVButton(title: (!viewModel.officialAccount && viewModel.selectedTab == .anchors) ? "登录红果账号" : (viewModel.officialAccount ? "刷新列表" : "去探索短剧"),
                                            icon: (!viewModel.officialAccount && viewModel.selectedTab == .anchors) ? "person.crop.circle.badge.plus" : (viewModel.officialAccount ? "arrow.clockwise" : "sparkles.tv"),
                                            isFocused: focusedTarget == .emptyAction, onUpCommand: { focus(.account, with: proxy) }) {
                                            if !viewModel.officialAccount && viewModel.selectedTab == .anchors {
                                                showingLogin = true
                                            } else if viewModel.officialAccount {
                                                Task { await viewModel.loadAccount(.anchors, refresh: true) }
                                            } else {
                                                requestTopNavigation()
                                            }
                                        }.focused($focusedTarget, equals: .emptyAction).accessibilityIdentifier("library.emptyAction").id(LibraryFocusTarget.emptyAction)
                                    }.frame(maxWidth: .infinity, minHeight: 300)
                                } else {
                                    LazyVGrid(columns: columns, spacing: 36) {
                                        ForEach(Array(viewModel.followedAnchorsList.enumerated()), id: \.element.id) { index, anchor in
                                            Button(action: { lastAnchorID = anchor.id; anchorFollowingChanged = false; selectedAnchor = anchor }) {
                                                AnchorCardView(anchor: anchor, isFocused: focusedTarget == .anchorCard(anchor.id))
                                            }
                                            .buttonStyle(TVZeroHighlightButtonStyle())
                                            .focused($focusedTarget, equals: .anchorCard(anchor.id))
                                            .accessibilityIdentifier("library.anchor.\(anchor.id)")
                                            .id(LibraryFocusTarget.anchorCard(anchor.id))
                                            .onMoveCommand { direction in
                                                if direction == .left && index % columns.count == 0 { focus(.mainTab(.anchors), with: proxy) }
                                                if direction == .down && index / columns.count == (viewModel.followedAnchorsList.count - 1) / columns.count && viewModel.accountErrors[.anchors] != nil { focus(.loadMore, with: proxy) }
                                            }
                                            .onAppear { Task { await viewModel.loadMoreIfNeeded(.anchors, index: index, count: viewModel.followedAnchorsList.count) } }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 24)
                                }
                            } else if videoRows.isEmpty {
                                VStack(spacing: 24) {
                                    Text(emptyMessage).font(.system(size: 29, weight: .medium))
                                    TVButton(title: (!viewModel.officialAccount && viewModel.selectedTab == .liked) ? "登录红果账号" : (viewModel.officialAccount ? "刷新列表" : "去探索短剧"),
                                        icon: (!viewModel.officialAccount && viewModel.selectedTab == .liked) ? "person.crop.circle.badge.plus" : (viewModel.officialAccount ? "arrow.clockwise" : "sparkles.tv"),
                                        isFocused: focusedTarget == .emptyAction, onUpCommand: { focus(.account, with: proxy) }) {
                                        if !viewModel.officialAccount && viewModel.selectedTab == .liked {
                                            showingLogin = true
                                        } else if viewModel.officialAccount {
                                            Task { await viewModel.loadAccount(viewModel.selectedTab, refresh: true) }
                                        } else {
                                            requestTopNavigation()
                                        }
                                    }.focused($focusedTarget, equals: .emptyAction).accessibilityIdentifier("library.emptyAction").id(LibraryFocusTarget.emptyAction)
                                }.frame(maxWidth: .infinity, minHeight: 300)
                            } else {
                                LazyVGrid(columns: columns, spacing: 36) {
                                    ForEach(Array(videoRows.enumerated()), id: \.element.id) { index, row in
                                        let drama = row.drama
                                        let entry = viewModel.selectedTab == .history ? entries.first { $0.drama.id == drama.id } : nil
                                        DramaCardView(drama: drama, isFocused: focusedTarget == .card(row.id),
                                            watchProgress: entry?.progressPercent, progressText: row.subtitle ?? entry?.progressLabel,
                                            onUpCommand: index < columns.count ? { focus(.account, with: proxy) } : nil,
                                            onLeftCommand: index % columns.count == 0 ? { focus(.mainTab(viewModel.selectedTab), with: proxy) } : nil,
                                            onDownCommand: index / columns.count == (videoRows.count - 1) / columns.count && viewModel.accountErrors[viewModel.selectedTab] != nil ? { focus(.loadMore, with: proxy) } : nil) {
                                            lastOpenedID = row.id; selectedDrama = drama
                                        }.focused($focusedTarget, equals: .card(row.id))
                                        .accessibilityIdentifier("library.card.\(row.id)")
                                        .accessibilityValue(row.subtitle ?? entry?.progressLabel ?? (viewModel.selectedTab == .liked ? "点赞视频" : (viewModel.officialAccount ? "账号追剧" : "本地收藏")))
                                        .id(LibraryFocusTarget.card(row.id))
                                        .onAppear { Task { await viewModel.loadMoreIfNeeded(viewModel.selectedTab, index: index, count: videoRows.count) } }
                                        .contextMenu {
                                            if !viewModel.officialAccount {
                                                Button(role: .destructive) {
                                                    if viewModel.selectedTab == .follows { viewModel.removeFollow(dramaId: drama.id) }
                                                    else { viewModel.removeHistory(dramaId: drama.id) }
                                                } label: { Label(viewModel.selectedTab == .follows ? "取消追剧" : "删除观看记录", systemImage: "trash") }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 24)
                            }
                            if viewModel.officialAccount && viewModel.moreTabs.contains(viewModel.selectedTab) {
                                if viewModel.accountErrors[viewModel.selectedTab] != nil {
                                    Button("重试加载") { Task { await retryMore(with: proxy) } }
                                        .focused($focusedTarget, equals: .loadMore).accessibilityIdentifier("library.more.retry").id(LibraryFocusTarget.loadMore)
                                        .onMoveCommand { if $0 == .left { focus(.mainTab(viewModel.selectedTab), with: proxy) } }
                                } else {
                                    ProgressView("正在加载更多").accessibilityIdentifier("library.more.loading")

                                }
                            }
                            if viewModel.officialAccount && viewModel.selectedTab == .liked && viewModel.officialLikes.contains(where: { $0.drama == nil }) {
                                Text("部分点赞内容暂无关联短剧，暂不支持打开").foregroundStyle(.secondary)
                            }
                          }.padding(.bottom, 36)
                        }.focusSection()
                    }.padding(.trailing, 48)
                }
            }
            .defaultFocus($focusedTarget, .mainTab(viewModel.selectedTab))
            .fullScreenCover(item: $selectedDrama, onDismiss: {
                detailDismissedAt = Date()
                let target = lastOpenedID.flatMap { id in videoRows.contains { $0.id == id } ? LibraryFocusTarget.card(id) : nil } ?? firstCardTarget
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focus(target, with: proxy) }
            }) { drama in DramaDetailView(drama: drama) }
            .fullScreenCover(item: $selectedAnchor, onDismiss: {
                detailDismissedAt = Date()
                let target = lastAnchorID.map { LibraryFocusTarget.anchorCard($0) } ?? firstCardTarget
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focus(target, with: proxy) }
                if anchorFollowingChanged { Task {
                    await viewModel.loadAccount(.anchors, refresh: true)
                    if let id = lastAnchorID, !viewModel.followedAnchorsList.contains(where: { $0.id == id }) { focus(firstCardTarget, with: proxy) }
                } }
            }) { anchor in
                AnchorDetailView(anchor: anchor, profileRequest: viewModel.profileRequest, allowsWrites: !viewModel.fixtureMode, onFollowingChanged: { anchorFollowingChanged = true })
            }
            .fullScreenCover(isPresented: $showingLogin, onDismiss: {
                if !viewModel.officialAccount || !account.verified { account.cancel() }
                onRequestFocusContent?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus(.account, with: proxy) }
            }) {
                #if DEBUG
                if CommandLine.arguments.contains("-openOfficialQr") { TVQrLoginView() }
                else { TVLoginOptionsView() }
                #else
                TVLoginOptionsView()
                #endif
            }
            .confirmationDialog("红果账号", isPresented: $showingAccountMenu, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { account.logout(); focusedTarget = .account }
                Button("取消", role: .cancel) { focusedTarget = .account }
            } message: { Text("退出后显示本机追剧与历史，原有资料会保留。") }
            .confirmationDialog("清空当前站源的观看历史？", isPresented: $showingClearHistory, titleVisibility: .visible) {
                Button("清空历史", role: .destructive) { viewModel.clearHistory(); focusedTarget = .mainTab(.history) }
                Button("取消", role: .cancel) { focusedTarget = .clearHistory }
            }
            .task(id: HongguoAccountVault.shared.snapshot.revision) {
                viewModel.syncAccountOwner()
                if !viewModel.fixtureMode { await account.verify() }
                await viewModel.loadAccount(viewModel.selectedTab)
                #if DEBUG
                if !openedDebugLogin && !viewModel.officialAccount && CommandLine.arguments.contains("-openAccountLogin") {
                    openedDebugLogin = true
                    showingLogin = true
                }
                #endif
            }
            .onChange(of: viewModel.selectedTab) { _, tab in Task { await viewModel.loadAccount(tab) } }
            .onChange(of: focusedTarget) { _, target in
                if case .mainTab(let tab) = target {
                    if viewModel.selectedTab != tab {
                        viewModel.selectedTab = tab
                    }
                }
                if case .followFilter(let state) = target {
                    if viewModel.selectedFollowFilter != state {
                        viewModel.selectedFollowFilter = state
                    }
                }
            }
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
                guard selectedDrama == nil, selectedAnchor == nil, !showingClearHistory, !showingLogin, !showingAccountMenu, Date().timeIntervalSince(detailDismissedAt) > 0.5 else { return }
                requestTopNavigation()
            }
        }
    }

    private func retryMore(with proxy: ScrollViewProxy) async {
        let tab = viewModel.selectedTab
        let count = tab == .anchors ? viewModel.followedAnchorsList.count : videoRows.count
        await viewModel.loadAccount(tab, more: true)
        guard tab == viewModel.selectedTab else { return }
        if viewModel.accountErrors[tab] != nil { focus(.loadMore, with: proxy) }
        else if tab == .anchors, !viewModel.followedAnchorsList.isEmpty {
            focus(.anchorCard(viewModel.followedAnchorsList[min(count, viewModel.followedAnchorsList.count - 1)].id), with: proxy)
        } else if !videoRows.isEmpty { focus(.card(videoRows[min(count, videoRows.count - 1)].id), with: proxy) }
    }

    private var emptyMessage: String {
        if viewModel.officialAccount {
            if viewModel.loadingTabs.contains(viewModel.selectedTab) { return "正在获取账号列表" }
            if viewModel.accountErrors[viewModel.selectedTab] != nil { return "暂时无法读取账号列表" }
        }
        if viewModel.selectedTab == .liked { return "暂无点赞视频" }
        if viewModel.selectedTab == .anchors { return "暂无关注的主播" }
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
    private func focus(_ target: LibraryFocusTarget, with proxy: ScrollViewProxy) {
        focusSequence += 1; let sequence = focusSequence
        if case .card = target { proxy.scrollTo(target, anchor: .center) }
        if case .anchorCard = target { proxy.scrollTo(target, anchor: .center) }
        if target == .loadMore { proxy.scrollTo(target, anchor: .bottom) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard sequence == focusSequence, selectedDrama == nil, selectedAnchor == nil else { return }
            focusedTarget = target
        }
    }

    @ViewBuilder
    private func headerView(proxy: ScrollViewProxy) -> some View {
        HStack {
            Text("我的").font(.system(size: 42, weight: .bold))
            Spacer()
            accountButton(proxy: proxy)
        }
        .padding(.horizontal, 48)
        .padding(.top, 28)
    }

    @ViewBuilder
    private func accountButton(proxy: ScrollViewProxy) -> some View {
        let isAccountFocused = (focusedTarget == .account)
        Button {
            if viewModel.officialAccount { showingAccountMenu = true } else { showingLogin = true }
        } label: {
            accountButtonLabel(isFocused: isAccountFocused)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .focused($focusedTarget, equals: .account)
        .accessibilityIdentifier(viewModel.officialAccount ? "hongguo-account-menu" : "hongguo-account-login")
        .onMoveCommand { direction in
            if direction == .up { requestTopNavigation() }
            if direction == .down { focus(firstCardTarget, with: proxy) }
            if direction == .left { focus(.mainTab(viewModel.selectedTab), with: proxy) }
        }
    }

    @ViewBuilder
    private func accountButtonLabel(isFocused: Bool) -> some View {
        HStack(spacing: 12) {
            if viewModel.officialAccount {
                avatar
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.2))
                Text(account.account?.nickname ?? "红果用户")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isFocused ? .white : TVColors.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isFocused ? .white.opacity(0.8) : TVColors.textMuted)
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(isFocused ? .white : TVColors.primary)
                Text("登录")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isFocused ? .white : TVColors.textPrimary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isFocused ? AnyShapeStyle(TVColors.prominentGradient) : AnyShapeStyle(Color.white.opacity(0.08)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 2.5 : 1.0)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .shadow(
            color: isFocused ? TVColors.focusedShadowStrong : Color.clear,
            radius: isFocused ? 14 : 0,
            x: 0,
            y: isFocused ? 4 : 0
        )
        .animation(TVTheme.focusSpringAnimation, value: isFocused)
    }
}
