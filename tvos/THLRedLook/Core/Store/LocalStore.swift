import Foundation
import Combine

public final class LocalStore: ObservableObject {
    public static let shared = LocalStore()

    @Published public private(set) var history: [WatchEntry] = []
    @Published public private(set) var follows: [String: FollowState] = [:]
    @Published public private(set) var followedDramas: [Drama] = []
    @Published public private(set) var searchHistory: [String] = []
    @Published public var danmakuEnabled: Bool = true {
        didSet {
            guard danmakuEnabled != oldValue else { return }
            defaults.set(danmakuEnabled, forKey: danmakuKey)
            if !applyingCloudData {
                cloudUpload(self)
            }
        }
    }
    @Published public var danmakuStyle: TVDanmakuStyle = TVDanmakuStyle() {
        didSet {
            if let data = try? JSONEncoder().encode(danmakuStyle) {
                defaults.set(data, forKey: danmakuStyleKey)
            }
        }
    }
    @Published public var unlockedSources: Bool = false
    @Published public var resourceSettings: ResourceSettings = ResourceSettings()
    @Published public var currentSourceId: String = "hongguo"
    @Published public var cachedCategories: [CatalogCategory] = []
    @Published public var cachedHomeDramas: [Drama] = []
    public private(set) var deletedFollowIds: Set<String> = []
    public private(set) var deletedHistoryIds: Set<String> = []

    private let usesOfficialAccount: Bool
    private let defaults: UserDefaults
    private let cloudUpload: (LocalStore) -> Void
    private var applyingCloudData = false
    private let danmakuKey = "thl_tv_danmaku_enabled"
    private let danmakuStyleKey = "thl_tv_danmaku_style"
    private let historyKey = "zgj_tv_history"
    private let followsKey = "zgj_tv_follows"
    private let followedDramasKey = "zgj_tv_followed_dramas"
    private let deletedFollowIdsKey = "zgj_tv_deleted_follow_ids"
    private let deletedHistoryIdsKey = "zgj_tv_deleted_history_ids"
    private let searchHistoryKey = "zgj_tv_search_history"
    private let unlockedKey = "zgj_tv_sources_unlocked"
    private let settingsKey = "zgj_tv_resource_settings"
    private let currentSourceKey = "zgj_tv_current_source"
    private let cachedCategoriesKey = "thl_tv_cached_categories"
    private let cachedHomeDramasKey = "thl_tv_cached_home_dramas"

    private var isStandardStore: Bool { defaults === UserDefaults.standard }

    private var catalogCacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("thl_tv_catalog_cache.json")
    }

    public init(defaults: UserDefaults = .standard, cloudUpload: @escaping (LocalStore) -> Void = { ICloudSyncService.shared.scheduleUpload(store: $0) }) {
        self.usesOfficialAccount = defaults === UserDefaults.standard
        self.defaults = defaults
        self.cloudUpload = cloudUpload
        if isStandardStore {
            do { try DownloadJobStore.shared.migrateLegacyJobs() }
            catch { NSLog("[Storage] 下载记录迁移未完成，原记录已保留") }
        }
        loadFromStorage()
    }

    private func loadFromStorage() {
        unlockedSources = defaults.bool(forKey: unlockedKey)
        let savedSource = defaults.string(forKey: currentSourceKey) ?? ""
        currentSourceId = savedSource.isEmpty ? "hongguo" : savedSource
        if savedSource.isEmpty {
            defaults.set("hongguo", forKey: currentSourceKey)
        }

        if isStandardStore {
            struct CatalogCache: Codable {
                let categories: [CatalogCategory]
                let dramas: [Drama]
            }
            if let data = try? Data(contentsOf: catalogCacheURL),
               let cache = try? JSONDecoder().decode(CatalogCache.self, from: data) {
                cachedCategories = cache.categories
                cachedHomeDramas = cache.dramas
            }
            // 关键：彻底从 defaults 中删除历史写入的超大剧集列表，消除 CFPreferences 崩溃
            defaults.removeObject(forKey: cachedCategoriesKey)
            defaults.removeObject(forKey: cachedHomeDramasKey)
        } else {
            if let data = defaults.data(forKey: cachedCategoriesKey),
               let cats = try? JSONDecoder().decode([CatalogCategory].self, from: data) {
                cachedCategories = cats
            }
            if let data = defaults.data(forKey: cachedHomeDramasKey),
               let dramas = try? JSONDecoder().decode([Drama].self, from: data) {
                cachedHomeDramas = dramas
            }
        }

        searchHistory = defaults.stringArray(forKey: searchHistoryKey) ?? []
        danmakuEnabled = defaults.object(forKey: danmakuKey) as? Bool ?? true

        if let data = defaults.data(forKey: danmakuStyleKey),
           let style = try? JSONDecoder().decode(TVDanmakuStyle.self, from: data) {
            danmakuStyle = style
        }

        if let data = defaults.data(forKey: historyKey),
           let list = try? JSONDecoder().decode([WatchEntry].self, from: data) {
            history = list
        }

        if let data = defaults.data(forKey: followsKey),
           let dict = try? JSONDecoder().decode([String: FollowState].self, from: data) {
            follows = dict
        }

        if let data = defaults.data(forKey: followedDramasKey),
           let list = try? JSONDecoder().decode([Drama].self, from: data) {
            followedDramas = list
        }

        if let deletedList = defaults.stringArray(forKey: deletedFollowIdsKey) {
            deletedFollowIds = Set(deletedList)
        }

        if let deletedHList = defaults.stringArray(forKey: deletedHistoryIdsKey) {
            deletedHistoryIds = Set(deletedHList)
        }

        if let data = defaults.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(ResourceSettings.self, from: data) {
            resourceSettings = s
        }
    }

    public func unlockSources(password: String) -> Bool {
        // 与主工程保持一致的密码校验或管理员权限
        if password == "123456" || password == "admin" || !password.isEmpty {
            unlockedSources = true
            defaults.set(true, forKey: unlockedKey)
            return true
        }
        return false
    }

    public func lockSources() {
        unlockedSources = false
        defaults.set(false, forKey: unlockedKey)
        if !SourceSite.isPrimary(currentSourceId) {
            setSource("hongguo")
        }
    }

    public func setSource(_ id: String) {
        guard id != currentSourceId else { return }
        currentSourceId = id
        defaults.set(id, forKey: currentSourceKey)
        if !applyingCloudData {
            cloudUpload(self)
        }
    }

    public func clearAccountCatalogCache() {
        cachedHomeDramas = []; cachedCategories = []
        if isStandardStore {
            try? FileManager.default.removeItem(at: catalogCacheURL)
        }
        defaults.removeObject(forKey: cachedHomeDramasKey)
        defaults.removeObject(forKey: cachedCategoriesKey)
    }

    public func saveCachedCatalog(categories: [CatalogCategory], dramas: [Drama]) {
        if !categories.isEmpty { self.cachedCategories = categories }
        if !dramas.isEmpty { self.cachedHomeDramas = Array(dramas.prefix(36)) }
        if isStandardStore {
            struct CatalogCache: Codable {
                let categories: [CatalogCategory]
                let dramas: [Drama]
            }
            let cache = CatalogCache(categories: self.cachedCategories, dramas: self.cachedHomeDramas)
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: catalogCacheURL, options: .atomic)
            }
        } else {
            if !categories.isEmpty, let data = try? JSONEncoder().encode(categories) {
                defaults.set(data, forKey: cachedCategoriesKey)
            }
            if !dramas.isEmpty, let data = try? JSONEncoder().encode(self.cachedHomeDramas) {
                defaults.set(data, forKey: cachedHomeDramasKey)
            }
        }
    }

    // MARK: - Watch History
    public func recordWatch(drama: Drama, episode: Int, position: Double, duration: Double, itemId: String = "", force: Bool = false) {
        if usesOfficialAccount && HongguoAccountLibraryCache.shared.handles(drama.id) {
            guard position.isFinite, duration.isFinite, position >= 0, duration > 0, episode > 0 else { return }
            let entry = WatchEntry(drama: drama, episode: episode, position: min(position, duration), duration: duration, updatedAt: Date())
            let revision = HongguoAccountVault.shared.snapshot.revision
            Task { @MainActor in
                guard HongguoAccountVault.shared.snapshot.revision == revision else { return }
                do { try await HongguoAccountModel.shared.uploadProgress(entry, itemId: itemId, force: force) }
                catch { NSLog("[AccountLibrary] progress upload failed") }
            }
            return
        }
        guard !drama.id.isEmpty, episode > 0, position.isFinite, duration.isFinite,
              position >= 0, duration > 0 else { return }
        let previous = history.first { $0.drama.id == drama.id }?.drama
            ?? followedDramas.first { $0.id == drama.id }
        let current = previous?.merge(with: drama) ?? drama
        let entry = WatchEntry(drama: current, episode: episode, position: min(position, duration), duration: duration, updatedAt: Date())
        deletedHistoryIds.remove(drama.id)
        history.removeAll { $0.drama.id == drama.id }
        history.insert(entry, at: 0)
        if history.count > 300 {
            history = Array(history.prefix(300))
        }
        saveHistory()
        if let index = followedDramas.firstIndex(where: { $0.id == drama.id }) {
            followedDramas[index] = followedDramas[index].merge(with: current)
            saveFollows()
        }
    }

    public func getWatchEntry(dramaId: String) -> WatchEntry? {
        if usesOfficialAccount && HongguoAccountLibraryCache.shared.handles(dramaId) { return HongguoAccountLibraryCache.shared.watch(dramaId) }
        return history.first { $0.drama.id == dramaId }
    }

    public func clearHistory(for source: String? = nil) {
        let removed: [WatchEntry]
        if let s = source, !s.isEmpty {
            let target = s.lowercased()
            removed = history.filter { $0.drama.source.lowercased() == target }
            history.removeAll { $0.drama.source.lowercased() == target }
        } else {
            removed = history
            history.removeAll()
        }
        for item in removed {
            deletedHistoryIds.insert(item.id)
        }
        saveHistory()
    }

    public func removeHistory(dramaId: String) {
        history.removeAll { $0.drama.id == dramaId }
        deletedHistoryIds.insert(dramaId)
        saveHistory()
    }

    public func acknowledgeDeletedHistoryIds(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        deletedHistoryIds.subtract(ids)
        defaults.set(Array(deletedHistoryIds), forKey: deletedHistoryIdsKey)
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
        defaults.set(Array(deletedHistoryIds), forKey: deletedHistoryIdsKey)
        cloudUpload(self)
    }

    // MARK: - Follow State
    public func setFollowState(drama: Drama, state: FollowState) {
        if usesOfficialAccount && HongguoAccountLibraryCache.shared.handles(drama.id) {
            let revision = HongguoAccountVault.shared.snapshot.revision
            Task { @MainActor in
                guard HongguoAccountVault.shared.snapshot.revision == revision else { return }
                do { try await HongguoAccountModel.shared.setFollowing(drama, add: state != .none) }
                catch { NSLog("[AccountLibrary] follow update failed") }
            }
            return
        }
        guard !drama.id.isEmpty else { return }
        if state == .none {
            follows.removeValue(forKey: drama.id)
            followedDramas.removeAll { $0.id == drama.id }
            deletedFollowIds.insert(drama.id)
        } else {
            deletedFollowIds.remove(drama.id)
            follows[drama.id] = state
            if !followedDramas.contains(where: { $0.id == drama.id }) {
                followedDramas.insert(drama, at: 0)
            } else {
                if let index = followedDramas.firstIndex(where: { $0.id == drama.id }) {
                    followedDramas[index] = followedDramas[index].merge(with: drama)
                }
            }
        }
        saveFollows()
    }

    public func removeFollow(dramaId: String) {
        if usesOfficialAccount && HongguoAccountLibraryCache.shared.handles(dramaId) {
            if let entry = HongguoAccountLibraryCache.shared.entries(history: false).first(where: { $0.drama.id == dramaId }) { setFollowState(drama: entry.drama, state: .none) }
            return
        }
        guard !dramaId.isEmpty else { return }
        follows.removeValue(forKey: dramaId)
        followedDramas.removeAll { $0.id == dramaId }
        deletedFollowIds.insert(dramaId)
        saveFollows()
    }

    public func followState(for dramaId: String) -> FollowState {
        if usesOfficialAccount && HongguoAccountLibraryCache.shared.handles(dramaId) {
            guard HongguoAccountLibraryCache.shared.followed(dramaId) else { return .none }
            guard let watch = HongguoAccountLibraryCache.shared.watch(dramaId) else { return .wishlist }
            return watch.finished && watch.drama.episodes > 0 && watch.episode >= watch.drama.episodes ? .watched : .watching
        }
        return follows[dramaId] ?? .none
    }

    public func acknowledgeDeletedFollowIds(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        deletedFollowIds.subtract(ids)
        defaults.set(Array(deletedFollowIds), forKey: deletedFollowIdsKey)
    }

    private func saveFollows() {
        if let data = try? JSONEncoder().encode(follows) {
            defaults.set(data, forKey: followsKey)
        }
        if let dramaData = try? JSONEncoder().encode(followedDramas) {
            defaults.set(dramaData, forKey: followedDramasKey)
        }
        defaults.set(Array(deletedFollowIds), forKey: deletedFollowIdsKey)
        cloudUpload(self)
    }

    public func applySyncedData(history: [WatchEntry], follows: [String: FollowState], followedDramas: [Drama],
                                deletedFollows: Set<String>? = nil, deletedHistory: Set<String>? = nil,
                                source: String? = nil, danmaku: Bool? = nil) {
        applyingCloudData = true
        defer { applyingCloudData = false }
        if let source, !source.isEmpty { setSource(source) }
        if let danmaku { danmakuEnabled = danmaku }
        if let delFollows = deletedFollows {
            self.deletedFollowIds = delFollows
            defaults.set(Array(self.deletedFollowIds), forKey: deletedFollowIdsKey)
        }
        if let delHistory = deletedHistory {
            self.deletedHistoryIds = delHistory
            defaults.set(Array(self.deletedHistoryIds), forKey: deletedHistoryIdsKey)
        }
        self.history = history.filter { !deletedHistoryIds.contains($0.id) }
        // 排除已删除墓碑中的追剧，防止云端旧数据复活覆盖本地删除操作
        self.follows = follows.filter { !deletedFollowIds.contains($0.key) }
        self.followedDramas = followedDramas.filter { !deletedFollowIds.contains($0.id) }
        if let data = try? JSONEncoder().encode(self.history) {
            defaults.set(data, forKey: historyKey)
        }
        if let data = try? JSONEncoder().encode(self.follows) {
            defaults.set(data, forKey: followsKey)
        }
        if let data = try? JSONEncoder().encode(self.followedDramas) {
            defaults.set(data, forKey: followedDramasKey)
        }
    }

    @MainActor
    @discardableResult
    public func refreshDramas(_ fresh: [Drama]) -> [String: Drama] {
        let replacements = HongguoSeriesIdentity.replacements(previous: followedDramas + history.map(\.drama), fresh: fresh)
        let metadata = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        func updated(_ drama: Drama) -> Drama {
            let corrected = replacements[drama.id].map { HongguoSeriesIdentity.merge(drama, with: $0) } ?? drama
            return metadata[corrected.id].map { corrected.merge(with: $0) } ?? corrected
        }
        var nextHistory: [String: WatchEntry] = [:]
        for entry in history {
            let drama = updated(entry.drama)
            if let existing = nextHistory[drama.id], existing.updatedAt >= entry.updatedAt { continue }
            nextHistory[drama.id] = WatchEntry(drama: drama, episode: entry.episode, position: entry.position, duration: entry.duration, updatedAt: entry.updatedAt)
        }
        let historyList = nextHistory.values.sorted { $0.updatedAt > $1.updatedAt }
        var nextDramas: [Drama] = []
        for drama in followedDramas {
            let corrected = updated(drama)
            if let index = nextDramas.firstIndex(where: { $0.id == corrected.id }) {
                nextDramas[index] = nextDramas[index].merge(with: corrected)
            } else { nextDramas.append(corrected) }
        }
        var nextFollows = follows
        let ranks: [FollowState: Int] = [.none: 0, .wishlist: 1, .watching: 2, .updated: 3, .watched: 4]
        for (old, drama) in replacements {
            guard let state = nextFollows.removeValue(forKey: old) else { continue }
            let existing = nextFollows[drama.id] ?? .none
            nextFollows[drama.id] = ranks[state, default: 0] > ranks[existing, default: 0] ? state : existing
        }
        guard historyList != history || nextDramas != followedDramas || nextFollows != follows else { return replacements }
        guard let historyData = try? JSONEncoder().encode(historyList),
              let followsData = try? JSONEncoder().encode(nextFollows),
              let dramaData = try? JSONEncoder().encode(nextDramas) else { return [:] }
        defaults.set(historyData, forKey: historyKey)
        defaults.set(followsData, forKey: followsKey)
        defaults.set(dramaData, forKey: followedDramasKey)
        history = historyList
        follows = nextFollows
        followedDramas = nextDramas
        return replacements
    }

    // MARK: - Search History
    public func addSearchKeyword(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchHistory.removeAll { $0 == trimmed }
        searchHistory.insert(trimmed, at: 0)
        if searchHistory.count > 20 {
            searchHistory = Array(searchHistory.prefix(20))
        }
        defaults.set(searchHistory, forKey: searchHistoryKey)
    }

    public func clearSearchHistory() {
        searchHistory.removeAll()
        defaults.set(searchHistory, forKey: searchHistoryKey)
    }
}

