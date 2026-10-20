import SwiftUI

public enum TVAppTab: String, CaseIterable, Identifiable {
    case catalog = "catalog"
    case rankings = "rankings"
    case search = "search"
    case library = "library"
    case downloads = "downloads"
    case settings = "settings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .catalog: return "发现"
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
        case .rankings: return "chart.bar.fill"
        case .search: return "magnifyingglass"
        case .library: return "bookmark.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct MainTabView: View {
    @StateObject private var lanService = LanSyncService.shared
    @StateObject private var store = LocalStore.shared

    @State private var selectedTab: TVAppTab = .catalog
    @FocusState private var focusedNavTab: TVAppTab?
    @State private var catalogCategoryFocusTrigger: Int = 0
    @State private var rankingsBoardFocusTrigger: Int = 0
    @State private var searchFocusTrigger: Int = 0
    @State private var libraryTabFocusTrigger: Int = 0
    @State private var settingsSidebarTrigger: Int = 0
    @State private var wasInContentArea: Bool = false

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
            case "settings", "importFlow", "settings_sources", "settings_about", "settings_cache", "settings_community", "settings_network":
                initTab = .settings
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
                VStack(spacing: 0) {
                    // 自定义顶级无白底导航栏（带焦点精准控制）
                    TVTopNavigationBar(
                        selectedTab: $selectedTab,
                        focusedNavTab: $focusedNavTab,
                        onDownCommandForTab: { tab in
                            switch tab {
                            case .catalog:
                                catalogCategoryFocusTrigger += 1
                            case .rankings:
                                rankingsBoardFocusTrigger += 1
                            case .search:
                                searchFocusTrigger += 1
                            case .library:
                                libraryTabFocusTrigger += 1
                            case .settings:
                                settingsSidebarTrigger += 1
                            default:
                                break
                            }
                        }
                    )
                    .padding(.top, 28)
                    .padding(.bottom, 12)
                    .zIndex(100)

                    // 页面切换容器
                    ZStack {
                        switch selectedTab {
                        case .catalog:
                            CatalogView(
                                store: store,
                                forceFocusFirstCard: isCardFocusedDemo,
                                initialCategory: catalogInitialCategory,
                                focusCategoryTrigger: catalogCategoryFocusTrigger,
                                onRequestFocusTopNav: {
                                    focusedNavTab = .catalog
                                }
                            )
                            .id("catalog_\(isCardFocusedDemo)_\(catalogInitialCategory ?? "")")
                        case .rankings:
                            RankingsView(
                                focusCategoryTrigger: rankingsBoardFocusTrigger,
                                onRequestFocusTopNav: {
                                    focusedNavTab = .rankings
                                }
                            )
                        case .search:
                            SearchRootView(
                                initialQuery: deepLinkQuery,
                                targetEpisode: deepLinkEpisode,
                                focusTrigger: searchFocusTrigger,
                                onRequestFocusTopNav: {
                                    focusedNavTab = .search
                                }
                            )
                        case .library:
                            SavedLibraryView(
                                focusCategoryTrigger: libraryTabFocusTrigger,
                                onRequestFocusTopNav: {
                                    focusedNavTab = .library
                                }
                            )
                        case .downloads:
                            DownloadsView()
                        case .settings:
                            SettingsView(
                                forceFocusActiveSource: isSettingsActiveDemo,
                                focusSidebarTrigger: settingsSidebarTrigger,
                                onRequestFocusTopNav: {
                                    focusedNavTab = .settings
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(TVTheme.backgroundGradient.ignoresSafeArea())
                // 需求 1：焦点在内容页面，点击返回页面应该回到导航栏，而不是退出 app
                .onExitCommand {
                    if focusedNavTab == nil {
                        if selectedTab != .settings {
                            focusedNavTab = selectedTab
                            wasInContentArea = false
                        }
                    }
                }
                // 需求 2：从内容页面按上键时，焦点精确重定向到当前激活的 selectedTab
                .onChange(of: focusedNavTab) { _, newTab in
                    NSLog("🎯 [FOCUS_TRACE] TopNav focusedNavTab = %@", newTab?.rawValue ?? "nil")
                    if let tab = newTab {
                        if wasInContentArea && tab != selectedTab {
                            // 修正跳往正上方错误 Tab 的系统默认行为，精确落回当前选中的 Tab
                            focusedNavTab = selectedTab
                        } else {
                            // 需求 4：在导航栏左右切换 Tab 时，内容页面立即自动同步切换
                            selectedTab = tab
                        }
                        wasInContentArea = false
                    } else {
                        // 焦点离开导航栏进入了内容页面
                        wasInContentArea = true
                    }
                }
            }
        }
        .onAppear {
            parseLaunchMode()
            if focusedNavTab == nil {
                focusedNavTab = selectedTab
            }
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
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "thlredlook" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let host = components.host?.lowercased() ?? ""
        if host == "search" {
            let kw = components.queryItems?.first(where: { $0.name == "keyword" })?.value ?? ""
            let epStr = components.queryItems?.first(where: { $0.name == "episode" })?.value
            let ep = epStr.flatMap { Int($0) }
            
            self.selectedTab = .search
            self.focusedNavTab = .search
            self.deepLinkQuery = kw
            self.deepLinkEpisode = ep
            NSLog("🎬 [THLRedLook] 响应 DeepLink 搜索: keyword=%@, episode=%ld", kw, ep ?? 0)
        }
    }

    private func parseLaunchMode() {
        UserDefaults.standard.removeObject(forKey: "testPage")
        let testPage = ProcessInfo.processInfo.environment["TEST_PAGE"]
            ?? getArgument(named: "-testPage")

        guard let page = testPage?.trimmingCharacters(in: .whitespacesAndNewlines), !page.isEmpty else { return }

        switch page {
        case "cleanBlank":
            selectedTab = .catalog
            focusedNavTab = .catalog
        case "importFlow", "settings", "settingsActive", "settings_cache", "settings_about", "settings_sources", "settings_community", "settings_network":
            selectedTab = .settings
            focusedNavTab = .settings
            if page == "settingsActive" {
                isSettingsActiveDemo = true
            }
        case "catalog", "cardFocused":
            selectedTab = .catalog
            isCardFocusedDemo = (page == "cardFocused")
            focusedNavTab = (page == "cardFocused") ? nil : .catalog
        case "catalog_real":
            selectedTab = .catalog
            catalogInitialCategory = "app:discover:playlet"
            focusedNavTab = .catalog
        case "catalog_comic":
            selectedTab = .catalog
            catalogInitialCategory = "app:discover:motion_comic"
            focusedNavTab = .catalog
        case "recommendations":
            selectedTab = .catalog
            focusedNavTab = .catalog
        case "recommendations_comic":
            selectedTab = .catalog
            catalogInitialCategory = "app:discover:motion_comic"
            focusedNavTab = .catalog
        case "rankings":
            selectedTab = .rankings
            focusedNavTab = .rankings
        case "search":
            selectedTab = .search
            focusedNavTab = .search
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
            focusedNavTab = .library
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
            focusedNavTab = .downloads
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.selectedTab = .downloads
                self.focusedNavTab = .downloads
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
            focusedNavTab = .downloads
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

// MARK: - 自定义高奢顶部导航栏（无白底纯净焦点）
public struct TVTopNavigationBar: View {
    @Binding public var selectedTab: TVAppTab
    public var focusedNavTab: FocusState<TVAppTab?>.Binding
    public var onDownCommandForTab: ((TVAppTab) -> Void)? = nil

    public init(
        selectedTab: Binding<TVAppTab>,
        focusedNavTab: FocusState<TVAppTab?>.Binding,
        onDownCommandForTab: ((TVAppTab) -> Void)? = nil
    ) {
        self._selectedTab = selectedTab
        self.focusedNavTab = focusedNavTab
        self.onDownCommandForTab = onDownCommandForTab
    }

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(TVAppTab.allCases) { tab in
                let isFocused = focusedNavTab.wrappedValue == tab
                TVTopNavTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    isFocused: isFocused,
                    onDownCommand: {
                        onDownCommandForTab?(tab)
                    },
                    onLeftCommand: (tab == .settings) ? {
                        focusedNavTab.wrappedValue = .downloads
                        selectedTab = .downloads
                    } : nil
                ) {
                    selectedTab = tab
                }
                .focused(focusedNavTab, equals: tab)
                .accessibilityIdentifier("nav.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.95))
                .shadow(color: Color.black.opacity(0.7), radius: 18, y: 6)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

public struct TVTopNavTabButton: View {
    public let tab: TVAppTab
    public let isSelected: Bool
    public let isFocused: Bool
    public var onDownCommand: (() -> Void)? = nil
    public var onLeftCommand: (() -> Void)? = nil
    public let action: () -> Void

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .bold))
                Text(tab.title)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .white : (isFocused ? .white : Color.white.opacity(0.75)))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? (isFocused ? TVTheme.primaryHover : TVTheme.primary) : (isFocused ? Color(red: 0.22, green: 0.22, blue: 0.26) : Color.clear))
            )
            .tvCapsuleFocus(isFocused: isFocused, lineWidth: 3.5, scale: 1.06)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .down {
                onDownCommand?()
            } else if direction == .left {
                onLeftCommand?()
            }
        }
    }
}

