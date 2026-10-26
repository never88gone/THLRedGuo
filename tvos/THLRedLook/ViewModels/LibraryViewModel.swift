import Foundation
import Combine
import UIKit

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public var selectedTab: LibraryTab = .history
    @Published public var selectedFollowFilter: FollowState = .none
    @Published public var searchQuery: String = ""

    public enum LibraryTab: String, CaseIterable, Identifiable {
        case history = "history"
        case follows = "follows"

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .history: return "最近观看"
            case .follows: return "我的收藏"
            }
        }
    }

    private let store: LocalStore
    private var cancellables = Set<AnyCancellable>()

    public init(store: LocalStore = .shared) {
        self.store = store
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var currentSource: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : store.currentSourceId
        return src.isEmpty ? "hongguo" : src
    }

    public var historyList: [WatchEntry] {
        let target = currentSource.lowercased()
        let sourceMatched = store.history.filter { $0.drama.source.lowercased() == target }
        guard !searchQuery.isEmpty else { return sourceMatched }
        return sourceMatched.filter { $0.drama.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    public var followedList: [Drama] {
        let target = currentSource.lowercased()
        let sourceMatched = store.followedDramas.filter { $0.source.lowercased() == target }
        let filtered: [Drama]
        if selectedFollowFilter == .none {
            filtered = sourceMatched
        } else {
            filtered = sourceMatched.filter { store.followState(for: $0.id) == selectedFollowFilter }
        }
        guard !searchQuery.isEmpty else { return filtered }
        return filtered.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    public func clearHistory() {
        store.clearHistory(for: currentSource)
    }

    public func removeHistory(dramaId: String) {
        store.removeHistory(dramaId: dramaId)
    }
}

@MainActor
public final class DownloadsViewModel: ObservableObject {
    private let downloadService: DownloadService
    private var cancellables = Set<AnyCancellable>()

    public init(downloadService: DownloadService = .shared) {
        self.downloadService = downloadService
        downloadService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var currentSource: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : LocalStore.shared.currentSourceId
        return src
    }

    public var jobs: [DownloadJob] {
        guard !currentSource.isEmpty else { return [] }
        let target = currentSource.lowercased()
        return downloadService.jobs.filter { $0.drama.source.lowercased() == target }
    }

    public func pauseJob(_ id: String) {
        downloadService.pauseJob(id: id)
    }

    public func resumeJob(_ id: String) {
        downloadService.startJob(id: id)
    }

    public func deleteJob(_ id: String) {
        downloadService.deleteJob(id: id)
    }

    public func resumeAll() {
        downloadService.resumeAll()
    }

    public func clearAll() {
        let currentJobs = jobs
        for job in currentJobs {
            downloadService.deleteJob(id: job.id)
        }
    }
}

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var unlockPassword = ""
    @Published public var unlockError: String?
    @Published public var proxyMode: String = "direct"
    @Published public var proxyUrl: String = ""
    @Published public var concurrency: Int = 3
    @Published public var intervalMs: Int = 250
    @Published public var keepScreenOn: Bool = true
    @Published public var currentSourceId: String = ""

    private let store: LocalStore
    private var cancellables = Set<AnyCancellable>()

    public init(store: LocalStore = .shared) {
        self.store = store
        self.currentSourceId = store.currentSourceId
        self.proxyMode = store.resourceSettings.proxyMode
        self.proxyUrl = store.resourceSettings.proxyUrl
        self.concurrency = store.resourceSettings.catalogConcurrency
        self.intervalMs = store.resourceSettings.catalogIntervalMs
        self.keepScreenOn = store.resourceSettings.keepScreenOn

        store.$currentSourceId
            .sink { [weak self] newId in
                self?.currentSourceId = newId
            }
            .store(in: &cancellables)

        store.$unlockedSources
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var currentSource: SourceSite {
        SourceSite.byId(currentSourceId)
    }

    public var availableSources: [SourceSite] {
        SourceSite.visibleValues(unlocked: store.unlockedSources)
    }

    public func selectSource(_ id: String) {
        store.setSource(id)
        currentSourceId = id
    }

    public var isUnlocked: Bool {
        store.unlockedSources
    }

    public func attemptUnlock() -> Bool {
        unlockError = nil
        let success = store.unlockSources(password: unlockPassword)
        if !success {
            unlockError = "密码不正确，请重新输入"
        } else {
            unlockPassword = ""
        }
        return success
    }

    public func lockSources() {
        store.lockSources()
    }

    public func saveSettings() {
        var s = store.resourceSettings
        s.proxyMode = proxyMode
        s.proxyUrl = proxyUrl
        s.catalogConcurrency = concurrency
        s.catalogIntervalMs = intervalMs
        s.keepScreenOn = keepScreenOn
        store.resourceSettings = s
        
        // 立即应用 Wakelock 状态
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = s.keepScreenOn
        }
    }
}

@MainActor
public final class JSSourceService: ObservableObject {
    public static let shared = JSSourceService()

    @Published public private(set) var sources: [[String: Any]] = []
    @Published public private(set) var activeSourceId: String = "hongguo"

    private let repository = NativeRepository.shared
    private var initializationTask: Task<Void, Never>?

    private init() {
        let saved = LocalStore.shared.currentSourceId
        let initial = saved.isEmpty ? "hongguo" : saved
        self.activeSourceId = initial
        self.sources = [[
            "id": "hongguo",
            "name": "官方内置",
            "version": "1.0.0",
            "author": "THL"
        ]]
    }

    public func initialize() async {
        if let task = initializationTask {
            await task.value
            return
        }
        let task = Task { await initializeSources() }
        initializationTask = task
        await task.value
        initializationTask = nil
    }

    private func initializeSources() async {
        // 1. 优先快速获取已安装源（毫秒级）
        if let list = try? await repository.jsSourceList(), !list.isEmpty {
            self.sources = list
        } else {
            _ = try? await repository.jsSourceScan()
            if let list = try? await repository.jsSourceList(), !list.isEmpty {
                self.sources = list
            }
        }

        // 2. 检查是否包含官方内置源，若缺失才补充导入
        if !self.sources.contains(where: { ($0["id"] as? String) == "hongguo" }) {
            _ = await importBuiltInHongguoSource(autoSelect: true)
        }

        await refresh()

        if self.activeSourceId.isEmpty {
            await setActiveSource("hongguo")
        }
    }

    public func refresh() async {
        if let list = try? await repository.jsSourceList() {
            self.sources = list
        }
        if self.sources.isEmpty {
            self.activeSourceId = ""
            LocalStore.shared.setSource("")
            return
        }
        if let active = try? await repository.jsSourceGetActive(), !active.isEmpty {
            if self.sources.contains(where: { ($0["id"] as? String) == active }) {
                self.activeSourceId = active
                LocalStore.shared.setSource(active)
            } else if self.sources.contains(where: { ($0["id"] as? String) == "hongguo" }) {
                self.activeSourceId = "hongguo"
                LocalStore.shared.setSource("hongguo")
            } else if let firstId = self.sources.first?["id"] as? String {
                self.activeSourceId = firstId
                LocalStore.shared.setSource(firstId)
            } else {
                self.activeSourceId = ""
                LocalStore.shared.setSource("")
            }
        } else if self.sources.contains(where: { ($0["id"] as? String) == "hongguo" }) {
            // 优先默认激活官方源
            self.activeSourceId = "hongguo"
            LocalStore.shared.setSource("hongguo")
        } else if let firstId = self.sources.first?["id"] as? String {
            self.activeSourceId = firstId
            LocalStore.shared.setSource(firstId)
        } else {
            self.activeSourceId = ""
            LocalStore.shared.setSource("")
        }
    }

    public func setActiveSource(_ id: String) async {
        let ok = (try? await repository.jsSourceSetActive(sourceId: id)) ?? false
        if ok {
            self.activeSourceId = id
            LocalStore.shared.setSource(id)
            await refresh()
        }
    }

    /// 导入官方规范的内置免费短剧数据源，导入时默认选中该数据源
    @discardableResult
    public func importBuiltInHongguoSource(autoSelect: Bool = true) async -> Bool {
        let script = BuiltInHongguoJSContent
        let ok = (try? await repository.jsSourceSaveAndLoad(script: script, fileName: "hongguo.js", autoSelect: autoSelect)) ?? false
        if ok {
            await refresh()
            if autoSelect || self.activeSourceId.isEmpty {
                await setActiveSource("hongguo")
            }
        }
        return ok
    }

    public func importFromURL(_ urlString: String, autoSelect: Bool = true) async throws -> Bool {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "JSSource", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的 URL 链接"])
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw NSError(domain: "JSSource", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法下载脚本文件：网络错误"])
        }
        
        guard let script = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "JSSource", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法解析脚本文件：非 UTF8 编码"])
        }
        
        let fileName = url.lastPathComponent.isEmpty ? "imported_plugin.js" : url.lastPathComponent
        let ok = try await repository.jsSourceSaveAndLoad(script: script, fileName: fileName, autoSelect: autoSelect)
        
        if ok {
            await refresh()
            let fileId = fileName.replacingOccurrences(of: ".js", with: "")
            // 官方数据源导入时默认选择，或者当 autoSelect 开启 / 当前活跃源为空时自动选择
            if autoSelect || fileId == "hongguo" || self.activeSourceId.isEmpty {
                let targetId = self.sources.contains(where: { ($0["id"] as? String) == fileId }) ? fileId : (self.sources.contains(where: { ($0["id"] as? String) == "hongguo" }) ? "hongguo" : (sources.first?["id"] as? String ?? ""))
                if !targetId.isEmpty {
                    await setActiveSource(targetId)
                }
            }
        }
        return ok
    }

    @discardableResult
    public func removeSource(_ id: String) async -> Bool {
        guard id.lowercased() != "hongguo" else { return false }
        let ok = (try? await repository.jsSourceRemove(sourceId: id)) ?? false
        await refresh()
        if self.activeSourceId == id || self.activeSourceId.isEmpty {
            await setActiveSource("hongguo")
        }
        return ok
    }

    @discardableResult
    public func clearAllSources() async -> Bool {
        let ok = (try? await repository.jsSourceClearAll()) ?? false
        await refresh()
        await setActiveSource("hongguo")
        return ok
    }

    @discardableResult
    public func resetOfficialSourceAndSession() async -> Bool {
        let ok = (try? await repository.jsSourceResetOfficial()) ?? false
        await refresh()
        await setActiveSource("hongguo")
        return ok
    }
}

/// 官方数据源脚本内容
/// 优先从 App Bundle 动态读取，开发/测试期回退直接读取工程目录中的 assets/sources/hongguo.js，避免硬编码重复
public var BuiltInHongguoJSContent: String {
    // 1. 优先从 App Bundle 资源中读取
    if let url = Bundle.main.url(forResource: "hongguo", withExtension: "js"),
       let content = try? String(contentsOf: url, encoding: .utf8),
       !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return content
    }

    // 2. 检查 Bundle 根目录资源
    let bundleFile = URL(fileURLWithPath: Bundle.main.bundlePath).appendingPathComponent("hongguo.js")
    if let content = try? String(contentsOf: bundleFile, encoding: .utf8),
       !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return content
    }

    // 3. 模拟器/测试/本地调试回退：定位工程 assets/sources/hongguo.js 动态读取
    let projectRoot = URL(fileURLWithPath: #file)
        .deletingLastPathComponent() // ViewModels
        .deletingLastPathComponent() // THLRedLook
        .deletingLastPathComponent() // tvos
        .deletingLastPathComponent() // 工程根目录
    let sourceFile = projectRoot.appendingPathComponent("assets/sources/hongguo.js")
    if let content = try? String(contentsOf: sourceFile, encoding: .utf8),
       !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return content
    }

    // 4. 兜底回退工程路径
    let fallbackPath = "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/assets/sources/hongguo.js"
    if let content = try? String(contentsOfFile: fallbackPath, encoding: .utf8),
       !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return content
    }

    return ""
}
