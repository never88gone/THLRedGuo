import SwiftUI

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
    @State private var tabDebounceTask: Task<Void, Never>? = nil

    private let pipCoordinator = TVPictureInPictureCoordinator.shared
    @State private var pipRestoreDrama: Drama?
    @State private var pipRestoreSession: TVPictureInPictureSession?

    @State private var directDetailDrama: Drama?
    @State private var directPlayerDrama: Drama?
    @State private var directPlayerEpisodes: [Episode] = []
    @State private var directPlayerControls: Bool = false
    @State private var directPlayerDrawer: Bool = false
    @State private var directPlayerFocusPiP: Bool = false
    @State private var isCardFocusedDemo: Bool = false
    @State private var isSettingsActiveDemo: Bool = false
    @State private var settingsInitialCategory: SettingsCategory = .sources
    @State private var catalogInitialCategory: String? = nil
    @State private var deepLinkQuery: String? = nil
    @State private var deepLinkEpisode: Int? = nil
    @State private var testInitialEpisodeIndex: Int = 1

    @State private var visibleAccountRevision: UInt64 = 0

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
        var initPlayerFocusPiP: Bool = false
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
            case "settings_release_notes":
                initTab = .settings
                initSettingsCategory = .releaseNotes
            case "settings", "importFlow", "settings_sources":
                initTab = .settings
                initSettingsCategory = .sources
            case "settingsActive":
                initTab = .settings
                initSettingsActive = true
            case "detail", "anchor":
                initDetailDrama = representativeDrama
            case "player", "controls", "drawer", "pipFocused":
                initPlayerDrama = representativeDrama
                initPlayerEpisodes = representativeEpisodes
                initPlayerControls = (p == "controls" || p == "pipFocused")
                initPlayerDrawer = (p == "drawer")
                initPlayerFocusPiP = (p == "pipFocused")
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
        _directPlayerFocusPiP = State(initialValue: initPlayerFocusPiP)
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
                    initialRestoreFocusTarget: directPlayerFocusPiP ? .pip : nil,
                    onDismiss: {
                        directPlayerDrama = nil
                        directPlayerEpisodes = []
                        directPlayerDrawer = false
                        directPlayerFocusPiP = false
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
                                },
                                onRequestFocusContent: {
                                    enterContentArea(for: .library)
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
                    tabDebounceTask?.cancel()
                    if let tab = newTab {
                        if tab == .feed {
                            tabDebounceTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                guard !Task.isCancelled, focusedNavTab == tab else { return }
                                selectedTab = tab
                            }
                        } else {
                            selectedTab = tab
                        }
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
            TVLaunchCoordinator.shared.parseLaunchMode(
                store: store,
                columnVisibility: $columnVisibility,
                selectedTab: $selectedTab,
                focusedNavTab: $focusedNavTab,
                settingsInitialCategory: $settingsInitialCategory,
                isSettingsActiveDemo: $isSettingsActiveDemo,
                isCardFocusedDemo: $isCardFocusedDemo,
                catalogInitialCategory: $catalogInitialCategory,
                feedFocusTrigger: $feedFocusTrigger,
                deepLinkQuery: $deepLinkQuery,
                directPlayerEpisodes: $directPlayerEpisodes,
                directPlayerControls: $directPlayerControls,
                directPlayerDrawer: $directPlayerDrawer,
                directPlayerDrama: $directPlayerDrama,
                directDetailDrama: $directDetailDrama
            )
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .feed { feedFocusTrigger += 1 }
        }
        .onReceive(HongguoAccountModel.shared.$account) { _ in
            let revision = HongguoAccountVault.shared.snapshot.revision
            guard revision != visibleAccountRevision else { return }
            visibleAccountRevision = revision
            store.clearAccountCatalogCache()
            Task { await videoFeedViewModel.refresh() }
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
        .onReceive(pipCoordinator.$shouldRestoreFullScreen) { shouldRestore in
            guard shouldRestore, let session = pipCoordinator.currentSession else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard pipCoordinator.shouldRestoreFullScreen else { return }
                NSLog("🎯 [MainTabView] 兜底处理画中画全屏恢复: drama='%@', episode=%d", session.drama.title, session.episodeIndex)
                pipCoordinator.markRestoreHandled()
                self.pipRestoreSession = session
                self.pipRestoreDrama = session.drama
            }
        }
        .fullScreenCover(item: $pipRestoreDrama) { drama in
            if let session = pipRestoreSession {
                TVPlayerView(
                    drama: drama,
                    episodes: session.allEpisodes,
                    initialEpisodeIndex: session.episodeIndex,
                    initialPosition: session.currentPosition,
                    onDismiss: {
                        pipRestoreDrama = nil
                        pipRestoreSession = nil
                    }
                )
            }
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
        .background {
            TVGlobalPiPHostView()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
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
}
