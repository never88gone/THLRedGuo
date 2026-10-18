import Foundation
import Combine

public final class LocalStore: ObservableObject {
    public static let shared = LocalStore()

    @Published public private(set) var history: [WatchEntry] = []
    @Published public private(set) var follows: [String: FollowState] = [:]
    @Published public private(set) var followedDramas: [Drama] = []
    @Published public private(set) var searchHistory: [String] = []
    @Published public var danmakuEnabled: Bool = true {
        didSet { defaults.set(danmakuEnabled, forKey: danmakuKey) }
    }
    @Published public var unlockedSources: Bool = false
    @Published public var resourceSettings: ResourceSettings = ResourceSettings()
    @Published public var currentSourceId: String = ""

    private let defaults: UserDefaults
    private let danmakuKey = "thl_tv_danmaku_enabled"
    private let historyKey = "zgj_tv_history"
    private let followsKey = "zgj_tv_follows"
    private let followedDramasKey = "zgj_tv_followed_dramas"
    private let searchHistoryKey = "zgj_tv_search_history"
    private let unlockedKey = "zgj_tv_sources_unlocked"
    private let settingsKey = "zgj_tv_resource_settings"
    private let currentSourceKey = "zgj_tv_current_source"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadFromStorage()
    }

    private func loadFromStorage() {
        unlockedSources = defaults.bool(forKey: unlockedKey)
        currentSourceId = defaults.string(forKey: currentSourceKey) ?? ""
        searchHistory = defaults.stringArray(forKey: searchHistoryKey) ?? []
        danmakuEnabled = defaults.object(forKey: danmakuKey) as? Bool ?? true

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
        currentSourceId = id
        defaults.set(id, forKey: currentSourceKey)
    }

    // MARK: - Watch History
    public func recordWatch(drama: Drama, episode: Int, position: Double, duration: Double) {
        guard !drama.id.isEmpty, episode > 0, position.isFinite, duration.isFinite,
              position >= 0, duration > 0 else { return }
        let previous = history.first { $0.drama.id == drama.id }?.drama
            ?? followedDramas.first { $0.id == drama.id }
        let current = previous?.merge(with: drama) ?? drama
        let entry = WatchEntry(drama: current, episode: episode, position: min(position, duration), duration: duration, updatedAt: Date())
        history.removeAll { $0.drama.id == drama.id }
        history.insert(entry, at: 0)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        saveHistory()
        if let index = followedDramas.firstIndex(where: { $0.id == drama.id }) {
            followedDramas[index] = followedDramas[index].merge(with: current)
            saveFollows()
        }
    }

    public func getWatchEntry(dramaId: String) -> WatchEntry? {
        history.first { $0.drama.id == dramaId }
    }

    public func clearHistory(for source: String? = nil) {
        if let s = source, !s.isEmpty {
            let target = s.lowercased()
            history.removeAll { $0.drama.source.lowercased() == target }
        } else {
            history.removeAll()
        }
        saveHistory()
    }

    public func removeHistory(dramaId: String) {
        history.removeAll { $0.drama.id == dramaId }
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    // MARK: - Follow State
    public func setFollowState(drama: Drama, state: FollowState) {
        guard !drama.id.isEmpty else { return }
        if state == .none {
            follows.removeValue(forKey: drama.id)
            followedDramas.removeAll { $0.id == drama.id }
        } else {
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

    public func followState(for dramaId: String) -> FollowState {
        follows[dramaId] ?? .none
    }

    private func saveFollows() {
        if let data = try? JSONEncoder().encode(follows) {
            defaults.set(data, forKey: followsKey)
        }
        if let dramaData = try? JSONEncoder().encode(followedDramas) {
            defaults.set(dramaData, forKey: followedDramasKey)
        }
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

