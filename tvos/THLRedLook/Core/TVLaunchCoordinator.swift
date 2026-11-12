import SwiftUI

@MainActor
final class TVLaunchCoordinator {
    static let shared = TVLaunchCoordinator()
    private init() {}

    func parseLaunchMode(
        store: LocalStore,
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        selectedTab: Binding<TVAppTab>,
        focusedNavTab: FocusState<TVAppTab?>.Binding,
        settingsInitialCategory: Binding<SettingsCategory>,
        isSettingsActiveDemo: Binding<Bool>,
        isCardFocusedDemo: Binding<Bool>,
        catalogInitialCategory: Binding<String?>,
        feedFocusTrigger: Binding<Int>,
        deepLinkQuery: Binding<String?>,
        directPlayerEpisodes: Binding<[Episode]>,
        directPlayerControls: Binding<Bool>,
        directPlayerDrawer: Binding<Bool>,
        directPlayerDrama: Binding<Drama?>,
        directDetailDrama: Binding<Drama?>
    ) {
        UserDefaults.standard.removeObject(forKey: "testPage")
        let testPage = ProcessInfo.processInfo.environment["TEST_PAGE"]
            ?? getArgument(named: "-testPage")

        guard let page = testPage?.trimmingCharacters(in: .whitespacesAndNewlines), !page.isEmpty else {
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = selectedTab.wrappedValue
            }
            return
        }

        switch page {
        case "cleanBlank", "catalog":
            selectedTab.wrappedValue = .catalog
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .catalog
            }
        case "importFlow", "settings", "settings_sources":
            selectedTab.wrappedValue = .settings
            settingsInitialCategory.wrappedValue = .sources
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .settings
            }
        case "settings_cache", "settings_about", "settings_help", "settings_contact", "settings_sync", "settings_release_notes":
            selectedTab.wrappedValue = .settings
            if page == "settings_help" {
                settingsInitialCategory.wrappedValue = .help
            } else if page == "settings_contact" {
                settingsInitialCategory.wrappedValue = .contact
            } else if page == "settings_about" {
                settingsInitialCategory.wrappedValue = .about
            } else if page == "settings_cache" {
                settingsInitialCategory.wrappedValue = .cache
            } else if page == "settings_sync" {
                settingsInitialCategory.wrappedValue = .sync
            } else if page == "settings_release_notes" {
                settingsInitialCategory.wrappedValue = .releaseNotes
            }
            columnVisibility.wrappedValue = .detailOnly
            focusedNavTab.wrappedValue = nil
        case "settingsActive":
            selectedTab.wrappedValue = .settings
            isSettingsActiveDemo.wrappedValue = true
            columnVisibility.wrappedValue = .detailOnly
            focusedNavTab.wrappedValue = nil
        case "cardFocused":
            selectedTab.wrappedValue = .catalog
            isCardFocusedDemo.wrappedValue = true
            columnVisibility.wrappedValue = .detailOnly
            focusedNavTab.wrappedValue = nil
        case "catalog_real":
            selectedTab.wrappedValue = .catalog
            catalogInitialCategory.wrappedValue = "app:discover:playlet"
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .catalog
            }
        case "catalog_comic":
            selectedTab.wrappedValue = .catalog
            catalogInitialCategory.wrappedValue = "app:discover:motion_comic"
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .catalog
            }
        case "feed":
            selectedTab.wrappedValue = .feed
            columnVisibility.wrappedValue = .detailOnly
            focusedNavTab.wrappedValue = nil
            feedFocusTrigger.wrappedValue += 1
        case "recommendations":
            selectedTab.wrappedValue = .catalog
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .catalog
            }
        case "recommendations_comic":
            selectedTab.wrappedValue = .catalog
            catalogInitialCategory.wrappedValue = "app:discover:motion_comic"
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .catalog
            }
        case "rankings":
            selectedTab.wrappedValue = .rankings
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .rankings
            }
        case "search":
            selectedTab.wrappedValue = .search
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .search
            }
            Task {
                await JSSourceService.shared.initialize()
                await MainActor.run {
                    let q = deepLinkQuery.wrappedValue ?? "万妖图录"
                    store.addSearchKeyword(q)
                    store.addSearchKeyword("万妖图录")
                    store.addSearchKeyword("逆袭")
                    store.addSearchKeyword("总裁")
                    deepLinkQuery.wrappedValue = q
                }
            }
        case "library":
            selectedTab.wrappedValue = .library
            columnVisibility.wrappedValue = .detailOnly
            focusedNavTab.wrappedValue = nil
            Task {
                await JSSourceService.shared.initialize()
                let sourceId = JSSourceService.shared.activeSourceId.isEmpty ? store.currentSourceId : JSSourceService.shared.activeSourceId
                guard !sourceId.isEmpty else { return }
                let hasActiveHistory = store.history.contains { $0.drama.source.lowercased() == sourceId.lowercased() }
                let hasActiveFollows = store.followedDramas.contains { $0.source.lowercased() == sourceId.lowercased() }
                if !CommandLine.arguments.contains("-noLibraryFixtures") && !HongguoAccountModel.shared.loggedIn && (!hasActiveHistory || !hasActiveFollows) && !CommandLine.arguments.contains("-openAccountLogin") {
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
                        NSLog("[TVLaunchCoordinator] library 预热失败: %@", error.localizedDescription)
                    }
                }
            }
        case "downloads", "testDownload":
            selectedTab.wrappedValue = .downloads
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .downloads
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
                        NSLog("[TVLaunchCoordinator] downloads 触发失败: %@", error.localizedDescription)
                    }
                }
            }
        case "playDownloaded":
            selectedTab.wrappedValue = .downloads
            columnVisibility.wrappedValue = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedNavTab.wrappedValue = .downloads
            }
            Task {
                await JSSourceService.shared.initialize()
                let sourceId = JSSourceService.shared.activeSourceId.isEmpty ? store.currentSourceId : JSSourceService.shared.activeSourceId
                try? await Task.sleep(nanoseconds: 600_000_000)
                if let completedJob = DownloadService.shared.jobs.first(where: { $0.isCompleted && (sourceId.isEmpty || $0.drama.source.lowercased() == sourceId.lowercased()) }) {
                    await MainActor.run {
                        directPlayerEpisodes.wrappedValue = [completedJob.episode]
                        directPlayerControls.wrappedValue = true
                        directPlayerDrawer.wrappedValue = false
                        directPlayerDrama.wrappedValue = completedJob.drama
                    }
                }
            }
        case "detail":
            if directDetailDrama.wrappedValue == nil {
                Task {
                    await JSSourceService.shared.initialize()
                    let sourceId = JSSourceService.shared.activeSourceId.isEmpty ? store.currentSourceId : JSSourceService.shared.activeSourceId
                    guard !sourceId.isEmpty else { return }
                    if let cat = try? await NativeRepository.shared.loadCatalog(source: sourceId, page: 1), let first = cat.items.first {
                        await MainActor.run { directDetailDrama.wrappedValue = first }
                    }
                }
            }
        case "player", "controls", "drawer":
            if directPlayerDrama.wrappedValue == nil {
                Task {
                    await JSSourceService.shared.initialize()
                    let sourceId = JSSourceService.shared.activeSourceId.isEmpty ? store.currentSourceId : JSSourceService.shared.activeSourceId
                    guard !sourceId.isEmpty else { return }
                    if let target = (try? await NativeRepository.shared.loadCatalog(source: sourceId, page: 1))?.items.first {
                        let detail = (try? await NativeRepository.shared.loadDetail(drama: target))
                            ?? DramaDetail(drama: target, episodes: (1...max(20, target.episodes)).map { Episode(id: "\(target.id)_\($0)", title: "第 \($0) 集", number: $0) }, warning: "")
                        let eps = !detail.episodes.isEmpty ? detail.episodes : (1...max(20, target.episodes)).map { Episode(id: "\(target.id)_\($0)", title: "第 \($0) 集", number: $0) }
                        await MainActor.run {
                            directPlayerEpisodes.wrappedValue = eps
                            directPlayerDrama.wrappedValue = detail.drama
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
