import Foundation
import Combine

/// 苹果生态跨端 iCloud 键值同步服务 (iOS / macOS / tvOS 互通)
public final class ICloudSyncService: ObservableObject {
    public static let shared = ICloudSyncService()

    @Published public var isSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: syncEnabledKey)
            if isSyncEnabled {
                syncWithCloud()
            }
        }
    }

    @Published public private(set) var lastSyncDate: Date? {
        didSet {
            if let date = lastSyncDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastSyncDateKey)
            }
        }
    }

    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastStatusMessage: String = "未开启"

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let syncEnabledKey = "thl_icloud_sync_enabled"
    private let lastSyncDateKey = "thl_icloud_last_sync_date"

    // 跨平台统一使用的 iCloud KVS 键名
    public static let keyHistory = "thl_icloud_sync_v1_history"
    public static let keyFollows = "thl_icloud_sync_v1_follows"
    public static let keySettings = "thl_icloud_sync_v1_settings"
    public static let keyMeta = "thl_icloud_sync_v1_meta"

    private var debounceWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: syncEnabledKey)
        let lastTimestamp = UserDefaults.standard.double(forKey: lastSyncDateKey)
        if lastTimestamp > 0 {
            self.lastSyncDate = Date(timeIntervalSince1970: lastTimestamp)
            self.lastStatusMessage = "就绪"
        } else {
            self.lastStatusMessage = isSyncEnabled ? "就绪" : "未开启"
        }

        // 注册 iCloud 外部变动通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleICloudChangeNotification(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil
        )

        // 启动时同步并拉取云端
        if isSyncEnabled {
            kvStore.synchronize()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.syncWithCloud()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleICloudChangeNotification(_ notification: Notification) {
        guard isSyncEnabled else { return }
        kvStore.synchronize()
        DispatchQueue.main.async { [weak self] in
            NSLog("☁️ [iCloud] 收到云端数据变动通知，开始合并...")
            self?.syncWithCloud()
        }
    }

    /// 执行双向数据同步：拉取云端、合并冲突并写回最新状态
    public func syncWithCloud(store: LocalStore = .shared) {
        guard isSyncEnabled else { return }
        guard !isSyncing else { return }
        isSyncing = true
        lastStatusMessage = "正在同步..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.kvStore.synchronize()

            let isoDecoder = JSONDecoder()
            isoDecoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateStr = try container.decode(String.self)

                let isoWithMs = ISO8601DateFormatter()
                isoWithMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoWithMs.date(from: dateStr) { return date }

                let isoStd = ISO8601DateFormatter()
                isoStd.formatOptions = [.withInternetDateTime]
                if let date = isoStd.date(from: dateStr) { return date }

                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                let formats = [
                    "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'",
                    "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
                    "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                    "yyyy-MM-dd'T'HH:mm:ss.SSS",
                    "yyyy-MM-dd'T'HH:mm:ss'Z'",
                    "yyyy-MM-dd'T'HH:mm:ss",
                    "yyyy-MM-dd HH:mm:ss"
                ]
                for fmt in formats {
                    formatter.dateFormat = fmt
                    if let date = formatter.date(from: dateStr) { return date }
                }

                if let timestamp = Double(dateStr) {
                    return timestamp > 1_000_000_000_000
                        ? Date(timeIntervalSince1970: timestamp / 1000.0)
                        : Date(timeIntervalSince1970: timestamp)
                }
                return Date(timeIntervalSince1970: 0)
            }
            let isoEncoder = JSONEncoder()
            isoEncoder.dateEncodingStrategy = .iso8601

            // 1. 同步观看记录 (Watch History)
            var remoteHistory: [WatchEntry] = []
            if let historyStr = self.kvStore.string(forKey: Self.keyHistory),
               let data = historyStr.data(using: .utf8) {
                remoteHistory = (try? isoDecoder.decode([WatchEntry].self, from: data)) ?? []
            }

            // 2. 同步追剧信息 (Follows)
            var remoteFollows: [String: FollowState] = [:]
            var remoteDramas: [Drama] = []
            if let followsStr = self.kvStore.string(forKey: Self.keyFollows),
               let data = followsStr.data(using: .utf8),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                if let dict = json["follows"] as? [String: Any] {
                    for (k, v) in dict {
                        if let str = v as? String {
                            remoteFollows[k] = FollowState.from(string: str)
                        } else if let map = v as? [String: Any], let statusStr = map["status"] as? String {
                            remoteFollows[k] = FollowState.from(string: statusStr)
                        }
                    }
                }
                if let dramaList = json["dramas"] as? [[String: Any]],
                   let listData = try? JSONSerialization.data(withJSONObject: dramaList) {
                    remoteDramas = (try? JSONDecoder().decode([Drama].self, from: listData)) ?? []
                }
            }

            // 3. 同步配置项 (Settings)
            var remoteSettings: [String: Any]? = nil
            if let settingsStr = self.kvStore.string(forKey: Self.keySettings),
               let data = settingsStr.data(using: .utf8) {
                remoteSettings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }

            DispatchQueue.main.async {
                // 合并 Watch History: 以 updatedAt 较新者为准
                var mergedHistoryDict: [String: WatchEntry] = [:]
                for localEntry in store.history {
                    mergedHistoryDict[localEntry.drama.id] = localEntry
                }
                for remoteEntry in remoteHistory {
                    let id = remoteEntry.drama.id
                    if let local = mergedHistoryDict[id] {
                        if remoteEntry.updatedAt > local.updatedAt {
                            mergedHistoryDict[id] = remoteEntry
                        }
                    } else {
                        mergedHistoryDict[id] = remoteEntry
                    }
                }
                let finalHistory = Array(mergedHistoryDict.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(100))

                // 合并 Follows
                var mergedFollows = store.follows
                var mergedDramasDict: [String: Drama] = [:]
                for d in store.followedDramas { mergedDramasDict[d.id] = d }
                for d in remoteDramas { mergedDramasDict[d.id] = d }

                for (id, state) in remoteFollows {
                    if state != .none {
                        mergedFollows[id] = state
                    }
                }
                let finalDramas = Array(mergedDramasDict.values)

                // 合并 Settings
                if let remoteSettings = remoteSettings {
                    if let danmaku = remoteSettings["danmaku"] as? Bool {
                        store.danmakuEnabled = danmaku
                    }
                    if let source = remoteSettings["source"] as? String, !source.isEmpty {
                        store.setSource(source)
                    }
                }

                // 更新 Store
                store.applySyncedData(history: finalHistory, follows: mergedFollows, followedDramas: finalDramas)

                // 回写更新到云端
                if let historyData = try? isoEncoder.encode(finalHistory),
                   let historyJson = String(data: historyData, encoding: .utf8) {
                    self.kvStore.set(historyJson, forKey: Self.keyHistory)
                }

                var followDictString: [String: String] = [:]
                for (k, v) in mergedFollows {
                    followDictString[k] = v.rawValue
                }
                var followsPayload: [String: Any] = [
                    "follows": followDictString,
                    "updatedAt": ISO8601DateFormatter().string(from: Date())
                ]
                if let dramaData = try? JSONEncoder().encode(finalDramas),
                   let dramaJson = (try? JSONSerialization.jsonObject(with: dramaData)) as? [[String: Any]] {
                    followsPayload["dramas"] = dramaJson
                }
                if let followsData = try? JSONSerialization.data(withJSONObject: followsPayload),
                   let followsJson = String(data: followsData, encoding: .utf8) {
                    self.kvStore.set(followsJson, forKey: Self.keyFollows)
                }

                // 设置信息回写
                let settingsPayload: [String: Any] = [
                    "source": store.currentSourceId,
                    "danmaku": store.danmakuEnabled,
                    "updatedAt": ISO8601DateFormatter().string(from: Date())
                ]
                if let settingsData = try? JSONSerialization.data(withJSONObject: settingsPayload),
                   let settingsJson = String(data: settingsData, encoding: .utf8) {
                    self.kvStore.set(settingsJson, forKey: Self.keySettings)
                }

                // 元数据
                let metaPayload: [String: Any] = [
                    "device": "Apple TV (tvOS)",
                    "timestamp": Date().timeIntervalSince1970
                ]
                if let metaData = try? JSONSerialization.data(withJSONObject: metaPayload),
                   let metaJson = String(data: metaData, encoding: .utf8) {
                    self.kvStore.set(metaJson, forKey: Self.keyMeta)
                }

                self.kvStore.synchronize()
                self.lastSyncDate = Date()
                self.isSyncing = false
                self.lastStatusMessage = "已同步 (\(finalHistory.count)条记录, \(finalDramas.count)部追剧)"
                NSLog("☁️ [iCloud] 同步完成: 记录=%ld, 追剧=%ld", finalHistory.count, finalDramas.count)
            }
        }
    }

    /// 当本地数据更新时触发上传 (带防抖避免高频写入)
    public func scheduleUpload(store: LocalStore = .shared) {
        guard isSyncEnabled else { return }
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.syncWithCloud(store: store)
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }
}
