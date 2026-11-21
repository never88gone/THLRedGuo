import Foundation
import Combine
import UIKit

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
