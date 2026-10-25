import SwiftUI

public enum TVAppTab: String, CaseIterable, Identifiable {
    case catalog = "catalog"
    case feed = "feed"
    case rankings = "rankings"
    case search = "search"
    case library = "library"
    case downloads = "downloads"
    case settings = "settings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .catalog: return "发现"
        case .feed: return "推荐"
        case .rankings: return "榜单"
        case .search: return "搜索"
        case .library: return "追剧与历史"
        case .downloads: return "下载"
        case .settings: return "设置"
        }
    }

    public var icon: String {
        switch self {
        case .catalog: return "sparkles.tv"
        case .feed: return "play.rectangle.fill"
        case .rankings: return "chart.bar.fill"
        case .search: return "magnifyingglass"
        case .library: return "bookmark.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    public var nextTab: TVAppTab? {
        let all = TVAppTab.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    public var prevTab: TVAppTab? {
        let all = TVAppTab.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return nil }
        return all[idx - 1]
    }
}

public struct MainTabView: View {
    @StateObject private var lanService = LanSyncService.shared
    @StateObject private var store = LocalStore.shared
    @StateObject private var videoFeedViewModel = VideoFeedViewModel()

    @State private var selectedTab: TVAppTab = .catalog
    @FocusState private var focusedNavTab: TVAppTab?
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    @State private var catalogCategoryFocusTrigger: Int = 0
    @State private var feedFocusTrigger = 0
    @State private var rankingsBoardFocusTrigger: Int = 0
    @State private var searchFocusTrigger: Int = 0
    @State private var libraryTabFocusTrigger: Int = 0
    @State private var downloadsFocusTrigger: Int = 0
    @State private var settingsSidebarTrigger: Int = 0

    @State private var handoffDrama: Drama?
    @State private var handoffEpIndex: Int = 1
    @State private var handoffPosition: Double = 0

    @State private var directDetailDrama: Drama?
    @State private var directPlayerDrama: Drama?
    @State private var directPlayerEpisodes: [Episode] = []
    @State private var directPlayerControls: Bool = false
    @State private var directPlayerDrawer: Bool = false
    @State private var isCardFocusedDemo: Bool = false
    @State private var isSettingsActiveDemo: Bool = false
    @State private var settingsInitialCategory: SettingsCategory = .sources
    @State private var catalogInitialCategory: String? = nil
    @State private var deepLinkQuery: String? = nil
    @State private var deepLinkEpisode: Int? = nil
    @State private var testInitialEpisodeIndex: Int = 1

    public init() {
        let args = CommandLine.arguments
        var targetPage: String? = nil
        if let idx = args.firstIndex(of: "-testPage"), idx + 1 < args.count {
            targetPage = args[idx + 1]
        } else if let envPage = ProcessInfo.processInfo.environment["TEST_PAGE"], !envPage.isEmpty {
            targetPage = envPage
        }

        var initTab: TVAppTab = .catalog
        var initDetailDrama: Drama? = nil
        var initPlayerDrama: Drama? = nil
        var initPlayerEpisodes: [Episode] = []
        var initPlayerControls: Bool = false
        var initPlayerDrawer: Bool = false
        var initCardFocused: Bool = false
        var initSettingsActive: Bool = false
        var initSettingsCategory: SettingsCategory = .sources
        var initCategory: String? = nil

        var customDramaId: String? = nil
        var customDramaTitle: String? = nil
        var customQuery: String? = nil
        if let idx = args.firstIndex(of: "-testDramaId"), idx + 1 < args.count {
            customDramaId = args[idx + 1]
        } else if let envId = ProcessInfo.processInfo.environment["TEST_DRAMA_ID"], !envId.isEmpty {
            customDramaId = envId
        }
        if let idx = args.firstIndex(of: "-testDramaTitle"), idx + 1 < args.count {
            customDramaTitle = args[idx + 1]
        } else if let envTitle = ProcessInfo.processInfo.environment["TEST_DRAMA_TITLE"], !envTitle.isEmpty {
            customDramaTitle = envTitle
        }
        if let idx = args.firstIndex(of: "-testQuery"), idx + 1 < args.count {
            customQuery = args[idx + 1]
        } else if let envQuery = ProcessInfo.processInfo.environment["TEST_QUERY"], !envQuery.isEmpty {
            customQuery = envQuery
        }

        var customEpisodeIndex: Int = 1
        if let idx = args.firstIndex(of: "-testEpisode"), idx + 1 < args.count, let n = Int(args[idx + 1]) {
            customEpisodeIndex = n
        } else if let envEp = ProcessInfo.processInfo.environment["TEST_EPISODE"], let n = Int(envEp) {
            customEpisodeIndex = n
        }

        let defaultDrama = Drama(
            id: customDramaId ?? "test_hongguo_1001",
            source: "hongguo",
            title: customDramaTitle ?? "都市逆袭之王者归来",
            description: "一代战神龙王隐忍三年，龙殿重聚之时，风云再起，震惊四海八荒！",
            cover: "https://example.com/cover.jpg",
            episodes: 80
        )
        let representativeDrama = defaultDrama
        let representativeEpisodes = (1...80).map { Episode(id: "\(representativeDrama.id)_\($0)", title: "第 \($0) 集", number: $0) }

        if let p = targetPage?.trimmingCharacters(in: .whitespacesAndNewlines) {
            switch p {
            case "cleanBlank", "catalog":
                initTab = .catalog
            case "catalog_real":
                initTab = .catalog
                initCategory = "app:discover:playlet"
            case "catalog_comic":
                initTab = .catalog
                initCategory = "app:discover:motion_comic"
            case "cardFocused":
                initTab = .catalog
                initCardFocused = true
            case "feed":
                initTab = .feed
            case "recommendations":
                initTab = .catalog
            case "recommendations_comic":
                initTab = .catalog
                initCategory = "app:discover:motion_comic"
            case "rankings":
                initTab = .rankings
            case "search":
                initTab = .search
            case "library":
                initTab = .library
            case "downloads", "testDownload":
                initTab = .downloads
            case "settings_sync":
                initTab = .settings
                initSettingsCategory = .sync
            case "settings_help":
                initTab = .settings
                initSettingsCategory = .help
            case "settings_contact":
                initTab = .settings
                initSettingsCategory = .contact
            case "settings_about":
                initTab = .settings
                initSettingsCategory = .about
            case "settings_cache":
                initTab = .settings
                initSettingsCategory = .cache
            case "settings", "importFlow", "settings_sources":
                initTab = .settings
                initSettingsCategory = .sources
            case "settingsActive":
                initTab = .settings
                initSettingsActive = true
            case "detail":
                initDetailDrama = representativeDrama
            case "player", "controls", "drawer":
                initPlayerDrama = representativeDrama
                initPlayerEpisodes = representativeEpisodes
                initPlayerControls = (p == "controls")
                initPlayerDrawer = (p == "drawer")
            default:
                break
            }
        }

        _selectedTab = State(initialValue: initTab)
        _directDetailDrama = State(initialValue: initDetailDrama)
        _directPlayerDrama = State(initialValue: initPlayerDrama)
        _directPlayerEpisodes = State(initialValue: initPlayerEpisodes)
        _directPlayerControls = State(initialValue: initPlayerControls)
        _directPlayerDrawer = State(initialValue: initPlayerDrawer)
        _isCardFocusedDemo = State(initialValue: initCardFocused)
        _isSettingsActiveDemo = State(initialValue: initSettingsActive)
        _settingsInitialCategory = State(initialValue: initSettingsCategory)
        _catalogInitialCategory = State(initialValue: initCategory)
        _deepLinkQuery = State(initialValue: customQuery)
        _testInitialEpisodeIndex = State(initialValue: customEpisodeIndex)
    }

    public var body: some View {
        Group {
            if let drama = directPlayerDrama, !directPlayerEpisodes.isEmpty {
                TVPlayerView(
                    drama: drama,
                    episodes: directPlayerEpisodes,
                    initialEpisodeIndex: testInitialEpisodeIndex,
                    initialPosition: 0,
                    initialShowControls: directPlayerControls,
                    keepControlsVisible: directPlayerControls,
                    initialShowDrawer: directPlayerDrawer,
                    onDismiss: {
                        directPlayerDrama = nil
                        directPlayerEpisodes = []
                        directPlayerDrawer = false
                    }
                )
                .id("player_\(directPlayerControls)_\(directPlayerDrawer)_\(drama.id)")
            } else if let drama = directDetailDrama {
                DramaDetailView(drama: drama)
                    .id("detail_\(drama.id)")
            } else {
                // 参考 thldytv MainView.swift 实现的 TVCustomSplitView 导航系统
                TVCustomSplitView(columnVisibility: $columnVisibility) {
                    TVSidebarView(
                        selectedTab: $selectedTab,
                        focusedNavTab: $focusedNavTab,
                        onSelectTab: { tab in
                            selectedTab = tab
                            enterContentArea(for: tab)
                        },
                        onMoveRight: { tab in
                            selectedTab = tab
                            enterContentArea(for: tab)
                        },
                        onRefreshCurrentTab: {
                            refreshCurrentTab()
                        }
                    )
                } detail: {
                    ZStack {
                        switch selectedTab {
                        case .catalog:
                            CatalogView(
                                store: store,
                                forceFocusFirstCard: isCardFocusedDemo,
                                initialCategory: catalogInitialCategory,
                                focusCategoryTrigger: catalogCategoryFocusTrigger,
                                onRequestFocusTopNav: {
                                    requestFocusSidebar()
                                }
                            )
                            .padding(.top, 32)
                            .id("catalog_\(isCardFocusedDemo)_\(catalogInitialCategory ?? "")")
                        case .feed:
                            TVVideoFeedView(
                                viewModel: videoFeedViewModel,
                                isSidebarVisible: columnVisibility != .detailOnly,
                                focusTrigger: feedFocusTrigger,
                                onRequestFocusTopNav: {
                                    requestFocusSidebar()
                                }
                            )
                        case .rankings:
                            RankingsView(
                                focusCategoryTrigger: rankingsBoardFocusTrigger,
                                onRequestFocusTopNav: {
                                    requestFocusSidebar()
                                }
                            )
                            .padding(.top, 32)
                        case .search:
                            SearchRootView(
                                initialQuery: deepLinkQuery,
                                targetEpisode: deepLinkEpisode,
                                focusTrigger: searchFocusTrigger,
                                onRequestFocusTopNav: {
                                    requestFocusSidebar()
                                }
                            )
                            .padding(.top, 32)
                        case .library:
                            SavedLibraryView(
                                focusCategoryTrigger: libraryTabFocusTrigger,
                                onRequestFocusTopNav: {
                                    requestFocusSidebar()
                                }
                            )
                            .padding(.top, 32)
                        case .downloads:
                            DownloadsView(
                                focusTrigger: downloadsFocusTrigger,
                                onRequestFocusTopNav: {
                                    requestFocusSidebar()
                                }
                            )
                            .padding(.top, 32)
                        case .settings:
                            SettingsView(
                                initialCategory: settingsInitialCategory,
                                forceFocusActiveSource: isSettingsActiveDemo,
                                focusSidebarTrigger: settingsSidebarTrigger,
                                onRequestFocusTopNav: {
                                    requestFocusSidebar()
                                }
                            )
                            .padding(.top, 32)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TVTheme.backgroundGradient.ignoresSafeArea())
                }
                .onExitCommand {
                    requestFocusSidebar()
                }
                .onChange(of: focusedNavTab) { _, newTab in
                    NSLog("🎯 [FOCUS_TRACE] Sidebar focusedNavTab = %@", newTab?.rawValue ?? "nil")
                    if let tab = newTab {
                        selectedTab = tab
                        if columnVisibility != .all {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                columnVisibility = .all
                            }
                        }
                    } else {
                        // 当焦点离开侧边栏（进入设置页等主内容区），立即平滑收起侧边栏浮层，杜绝遮挡内容与阻碍操作
                        if columnVisibility != .detailOnly {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                columnVisibility = .detailOnly
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            parseLaunchMode()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .feed { feedFocusTrigger += 1 }
        }
        .onReceive(lanService.$incomingPlayback) { incoming in
            guard let inc = incoming else { return }
            handoffDrama = inc.drama
            handoffEpIndex = inc.episodeIndex
            handoffPosition = inc.position
            lanService.incomingPlayback = nil
        }
        .fullScreenCover(item: $handoffDrama) { drama in
            TVPlayerView(
                drama: drama,
                episodes: [Episode(id: "\(drama.id)_ep_\(handoffEpIndex)", title: "第 \(handoffEpIndex) 集", number: handoffEpIndex)],
                initialEpisodeIndex: handoffEpIndex,
                initialPosition: handoffPosition
            )
        }
        .onReceive(DeepLinkSearchCoordinator.shared.$latestRequest) { request in
            guard let req = request else { return }
            NSLog("🎯 [MainTabView] Observed DeepLink request: '%@', episode=%@", req.keyword, String(describing: req.episode))
            self.handoffDrama = nil
            self.directPlayerDrama = nil
            self.directDetailDrama = nil
            self.selectedTab = .search
            self.deepLinkQuery = req.keyword
            self.deepLinkEpisode = req.episode
            self.enterContentArea(for: .search)
        }
    }

    private func requestFocusSidebar() {
        let current = selectedTab
        focusedNavTab = current
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            columnVisibility = .all
        }
        DispatchQueue.main.async {
            focusedNavTab = current
        }
    }

    private func enterContentArea(for tab: TVAppTab) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            columnVisibility = .detailOnly
        }
        focusedNavTab = nil
        switch tab {
        case .catalog:
            catalogCategoryFocusTrigger += 1
        case .feed:
            feedFocusTrigger += 1
        case .rankings:
            rankingsBoardFocusTrigger += 1
        case .search:
            searchFocusTrigger += 1
        case .library:
            libraryTabFocusTrigger += 1
        case .downloads:
            downloadsFocusTrigger += 1
        case .settings:
            settingsSidebarTrigger += 1
        default:
            break
        }
    }

    private func refreshCurrentTab() {
        switch selectedTab {
        case .catalog:
            catalogCategoryFocusTrigger += 1
        case .feed:
            Task { await videoFeedViewModel.refresh() }
        case .rankings:
            rankingsBoardFocusTrigger += 1
        case .search:
            searchFocusTrigger += 1
        case .library:
            libraryTabFocusTrigger += 1
        case .downloads:
            downloadsFocusTrigger += 1
        case .settings:
            settingsSidebarTrigger += 1
        default:
            break
        }
    }

    private func parseLaunchMode() {
        UserDefaults.standard.removeObject(forKey: "testPage")
        let testPage = ProcessInfo.processInfo.environment["TEST_PAGE"]
            ?? getArgument(named: "-testPage")

        guard let page = testPage?.trimmingCharacters(in: .whitespacesAndNewlines), !page.isEmpty else {
            // 默认启动模式：展开侧边栏并聚焦当前 Tab
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = selectedTab
            }
            return
        }

        switch page {
        case "cleanBlank", "catalog":
            selectedTab = .catalog
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .catalog
            }
        case "importFlow", "settings", "settings_sources":
            selectedTab = .settings
            settingsInitialCategory = .sources
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .settings
            }
        case "settings_cache", "settings_about", "settings_help", "settings_contact", "settings_sync":
            selectedTab = .settings
            if page == "settings_help" {
                settingsInitialCategory = .help
            } else if page == "settings_contact" {
                settingsInitialCategory = .contact
            } else if page == "settings_about" {
                settingsInitialCategory = .about
            } else if page == "settings_cache" {
                settingsInitialCategory = .cache
            } else if page == "settings_sync" {
                settingsInitialCategory = .sync
            }
            columnVisibility = .detailOnly
            focusedNavTab = nil
        case "settingsActive":
            selectedTab = .settings
            isSettingsActiveDemo = true
            columnVisibility = .detailOnly
            focusedNavTab = nil
        case "cardFocused":
            selectedTab = .catalog
            isCardFocusedDemo = true
            columnVisibility = .detailOnly
            focusedNavTab = nil
        case "catalog_real":
            selectedTab = .catalog
            catalogInitialCategory = "app:discover:playlet"
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .catalog
            }
        case "catalog_comic":
            selectedTab = .catalog
            catalogInitialCategory = "app:discover:motion_comic"
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .catalog
            }
        case "feed":
            selectedTab = .feed
            columnVisibility = .detailOnly
            focusedNavTab = nil
            feedFocusTrigger += 1
        case "recommendations":
            selectedTab = .catalog
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .catalog
            }
        case "recommendations_comic":
            selectedTab = .catalog
            catalogInitialCategory = "app:discover:motion_comic"
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .catalog
            }
        case "rankings":
            selectedTab = .rankings
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .rankings
            }
        case "search":
            selectedTab = .search
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .search
            }
            Task {
                await JSSourceService.shared.initialize()
                await MainActor.run {
                    let q = self.deepLinkQuery ?? "万妖图录"
                    store.addSearchKeyword(q)
                    store.addSearchKeyword("万妖图录")
                    store.addSearchKeyword("逆袭")
                    store.addSearchKeyword("总裁")
                    self.deepLinkQuery = q
                }
            }
        case "library":
            selectedTab = .library
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .library
            }
            Task {
                await JSSourceService.shared.initialize()
                let sourceId = JSSourceService.shared.activeSourceId.isEmpty ? store.currentSourceId : JSSourceService.shared.activeSourceId
                guard !sourceId.isEmpty else { return }
                let hasActiveHistory = store.history.contains { $0.drama.source.lowercased() == sourceId.lowercased() }
                let hasActiveFollows = store.followedDramas.contains { $0.source.lowercased() == sourceId.lowercased() }
                if !hasActiveHistory || !hasActiveFollows {
                    do {
                        let cat = try await NativeRepository.shared.loadCatalog(source: sourceId, page: 1)
                        await MainActor.run {
                            for (idx, item) in cat.items.prefix(2).enumerated() {
                                if !hasActiveHistory {
                                    store.recordWatch(drama: item, episode: idx + 1, position: Double((idx + 1) * 35), duration: 120)
                                }
                                store.setFollowState(drama: item, state: .watching)
                            }
                        }
                    } catch {
                        NSLog("[MainTabView] library 预热失败: %@", error.localizedDescription)
                    }
                }
            }
        case "downloads", "testDownload":
            selectedTab = .downloads
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .downloads
            }
            Task {
                await JSSourceService.shared.initialize()
                let sourceId = JSSourceService.shared.activeSourceId.isEmpty ? store.currentSourceId : JSSourceService.shared.activeSourceId
                guard !sourceId.isEmpty else { return }
                let hasActiveJob = DownloadService.shared.jobs.contains { $0.drama.source.lowercased() == sourceId.lowercased() }
                if !hasActiveJob || page == "testDownload" {
                    do {
                        let cat = try await NativeRepository.shared.loadCatalog(source: sourceId, page: 1)
                        if let first = cat.items.first {
                            let detail = try await NativeRepository.shared.loadDetail(drama: first)
                            if let firstEp = detail.episodes.first {
                                await MainActor.run {
                                    DownloadService.shared.enqueue(drama: detail.drama, episodes: [firstEp])
                                }
                            }
                        }
                    } catch {
                        NSLog("[MainTabView] downloads 触发失败: %@", error.localizedDescription)
                    }
                }
            }

        case "playDownloaded":
            selectedTab = .downloads
            columnVisibility = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab = .downloads
            }
            Task {
                await JSSourceService.shared.initialize()
                let sourceId = JSSourceService.shared.activeSourceId.isEmpty ? store.currentSourceId : JSSourceService.shared.activeSourceId
                try? await Task.sleep(nanoseconds: 600_000_000)
                if let completedJob = DownloadService.shared.jobs.first(where: { $0.isCompleted && (sourceId.isEmpty || $0.drama.source.lowercased() == sourceId.lowercased()) }) {
                    await MainActor.run {
                        self.directPlayerEpisodes = [completedJob.episode]
                        self.directPlayerControls = true
                        self.directPlayerDrawer = false
                        self.directPlayerDrama = completedJob.drama
                    }
                }
            }
        case "detail":
            if self.directDetailDrama == nil {
                Task {
                    await JSSourceService.shared.initialize()
                    let sourceId = JSSourceService.shared.activeSourceId.isEmpty ? store.currentSourceId : JSSourceService.shared.activeSourceId
                    guard !sourceId.isEmpty else { return }
                    if let cat = try? await NativeRepository.shared.loadCatalog(source: sourceId, page: 1), let first = cat.items.first {
                        await MainActor.run { self.directDetailDrama = first }
                    }
                }
            }
        case "player", "controls", "drawer":
            if self.directPlayerDrama == nil {
                Task {
                    await JSSourceService.shared.initialize()
                    let sourceId = JSSourceService.shared.activeSourceId.isEmpty ? store.currentSourceId : JSSourceService.shared.activeSourceId
                    guard !sourceId.isEmpty else { return }
                    if let target = (try? await NativeRepository.shared.loadCatalog(source: sourceId, page: 1))?.items.first {
                        let detail = (try? await NativeRepository.shared.loadDetail(drama: target))
                            ?? DramaDetail(drama: target, episodes: (1...max(20, target.episodes)).map { Episode(id: "\(target.id)_\($0)", title: "第 \($0) 集", number: $0) }, warning: "")
                        let eps = !detail.episodes.isEmpty ? detail.episodes : (1...max(20, target.episodes)).map { Episode(id: "\(target.id)_\($0)", title: "第 \($0) 集", number: $0) }
                        await MainActor.run {
                            self.directPlayerEpisodes = eps
                            self.directPlayerDrama = detail.drama
                        }
                    }
                }
            }
        default:
            break
        }
    }

    private func getArgument(named name: String) -> String? {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: name), idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }
}
