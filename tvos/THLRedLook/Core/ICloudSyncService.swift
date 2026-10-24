import Foundation
import Combine

protocol ICloudKeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ICloudKeyValueStore {}

public final class ICloudSyncService: ObservableObject {
    public static let shared = ICloudSyncService()

    @Published public var isSyncEnabled: Bool {
        didSet {
            defaults.set(isSyncEnabled, forKey: syncEnabledKey)
            debounceWorkItem?.cancel()
            if isSyncEnabled {
                syncWithCloud()
            } else {
                pendingStore = nil
                lastStatusMessage = "已停用"
            }
        }
    }

    @Published public private(set) var lastSyncDate: Date? {
        didSet {
            if let date = lastSyncDate {
                defaults.set(date.timeIntervalSince1970, forKey: lastSyncDateKey)
            }
        }
    }

    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastStatusMessage = "未开启"

    public static let keyHistory = "thl_icloud_sync_v1_history"
    public static let keyFollows = "thl_icloud_sync_v1_follows"
    public static let keySettings = "thl_icloud_sync_v1_settings"
    public static let keyMeta = "thl_icloud_sync_v1_meta"

    private let kvStore: ICloudKeyValueStore
    private let defaults: UserDefaults
    private let syncEnabledKey = "thl_icloud_sync_enabled"
    private let lastSyncDateKey = "thl_icloud_last_sync_date"
    private var debounceWorkItem: DispatchWorkItem?
    private var pendingStore: LocalStore?

    init(kvStore: ICloudKeyValueStore = NSUbiquitousKeyValueStore.default, defaults: UserDefaults = .standard, observeChanges: Bool = true) {
        self.kvStore = kvStore
        self.defaults = defaults
        isSyncEnabled = defaults.bool(forKey: syncEnabledKey)
        let timestamp = defaults.double(forKey: lastSyncDateKey)
        if timestamp > 0 { lastSyncDate = Date(timeIntervalSince1970: timestamp) }
        lastStatusMessage = isSyncEnabled ? "就绪" : "未开启"
        if observeChanges {
            NotificationCenter.default.addObserver(self, selector: #selector(handleICloudChangeNotification(_:)), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil)
        }
    }

    deinit {
        debounceWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleICloudChangeNotification(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isSyncEnabled else { return }
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                self.lastStatusMessage = "iCloud 同步空间不足，本地记录已保留"
                return
            }
            self.syncWithCloud()
        }
    }

    public func syncWithCloud(store: LocalStore = .shared) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.syncWithCloud(store: store) }
            return
        }
        guard isSyncEnabled else { return }
        if isSyncing {
            pendingStore = store
            return
        }
        debounceWorkItem?.cancel()
        isSyncing = true
        lastStatusMessage = "正在同步..."
        defer {
            isSyncing = false
            if let pending = pendingStore {
                pendingStore = nil
                DispatchQueue.main.async { [weak self] in self?.syncWithCloud(store: pending) }
            }
        }

        guard kvStore.synchronize() else {
            lastStatusMessage = "iCloud 暂不可用，请检查 Apple 账号和同步权限"
            return
        }

        do {
            let remoteHistory: ([WatchEntry], Int) = try decodeRows(kvStore.string(forKey: Self.keyHistory), decoder: Self.historyDecoder())
            let followsJSON = try dictionary(kvStore.string(forKey: Self.keyFollows))
            let remoteDramas: ([Drama], Int) = try decodeRows(followsJSON["dramas"], decoder: JSONDecoder())
            let remoteSettings = try dictionary(kvStore.string(forKey: Self.keySettings))
            guard isSyncEnabled else { return }

            var history = Dictionary(store.history.map { ($0.id, $0) }, uniquingKeysWith: { old, new in old.updatedAt > new.updatedAt ? old : new })
            for entry in remoteHistory.0 where history[entry.id] == nil || entry.updatedAt > history[entry.id]!.updatedAt {
                history[entry.id] = entry
            }
            let mergedHistory = history.values.sorted {
                $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
            }
            var dramas = Dictionary(store.followedDramas.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for drama in remoteDramas.0 {
                dramas[drama.id] = dramas[drama.id]?.merge(with: drama) ?? drama
            }
            var follows = store.follows
            var remoteFollows: [String: FollowState] = [:]
            for (id, value) in followsJSON["follows"] as? [String: Any] ?? [:] {
                let status = (value as? String) ?? (value as? [String: Any])?["status"] as? String ?? ""
                let state = FollowState.from(string: status)
                if state != .none {
                    follows[id] = state
                    remoteFollows[id] = state
                }
            }
            let mergedDramas = dramas.values.sorted { $0.id < $1.id }
            store.applySyncedData(history: mergedHistory, follows: follows, followedDramas: mergedDramas,
                                  source: remoteSettings["source"] as? String, danmaku: remoteSettings["danmaku"] as? Bool)

            var wrote = false
            if remoteHistory.1 == 0 && Set(remoteHistory.0) != Set(mergedHistory.prefix(300)) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                encoder.dateEncodingStrategy = .custom { date, encoder in
                    var container = encoder.singleValueContainer()
                    try container.encode(formatter.string(from: date))
                }
                wrote = setChanged(String(decoding: try encoder.encode(Array(mergedHistory.prefix(300))), as: UTF8.self), key: Self.keyHistory) || wrote
            }
            if remoteDramas.1 == 0 && (remoteFollows != follows || Set(remoteDramas.0) != Set(mergedDramas)) {
                let dramaData = try JSONEncoder().encode(mergedDramas)
                wrote = try setChangedJSON([
                    "follows": follows.mapValues(\.rawValue),
                    "dramas": JSONSerialization.jsonObject(with: dramaData)
                ], key: Self.keyFollows) || wrote
            }
            var settings = remoteSettings
            settings["source"] = store.currentSourceId
            settings["danmaku"] = store.danmakuEnabled
            wrote = try setChangedJSON(settings, key: Self.keySettings) || wrote
            if wrote {
                let meta: [String: Any] = ["device": "Apple TV (tvOS)", "timestamp": Date().timeIntervalSince1970]
                kvStore.set(String(decoding: try JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys]), as: UTF8.self), forKey: Self.keyMeta)
                guard kvStore.synchronize() else {
                    lastStatusMessage = "记录已合并，iCloud 上传失败，请重试"
                    return
                }
            }
            lastSyncDate = Date()
            let skipped = remoteHistory.1 + remoteDramas.1
            lastStatusMessage = skipped > 0
                ? "部分记录格式不兼容，已保留云端原文（\(skipped)条）"
                : "已合并（\(mergedHistory.count)条记录，\(mergedDramas.count)部追剧），等待 iCloud 分发"
        } catch {
            lastStatusMessage = "云端数据读取失败，本地和云端原文已保留"
        }
    }

    public func scheduleUpload(store: LocalStore = .shared) {
        guard isSyncEnabled else { return }
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.syncWithCloud(store: store) }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    private func setChanged(_ value: String, key: String) -> Bool {
        guard kvStore.string(forKey: key) != value else { return false }
        kvStore.set(value, forKey: key)
        return true
    }

    private func setChangedJSON(_ value: [String: Any], key: String) throws -> Bool {
        var payload = value
        payload.removeValue(forKey: "updatedAt")
        var previous = try dictionary(kvStore.string(forKey: key))
        previous.removeValue(forKey: "updatedAt")
        if NSDictionary(dictionary: payload).isEqual(to: previous) { return false }
        payload["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        return setChanged(String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self), key: key)
    }

    private func dictionary(_ raw: String?) throws -> [String: Any] {
        guard let raw, !raw.isEmpty else { return [:] }
        guard let value = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return value
    }

    private func decodeRows<T: Decodable>(_ raw: Any?, decoder: JSONDecoder) throws -> ([T], Int) {
        guard let raw else { return ([], 0) }
        let value: Any
        if let text = raw as? String {
            if text.isEmpty { return ([], 0) }
            value = try JSONSerialization.jsonObject(with: Data(text.utf8))
        } else { value = raw }
        guard let rows = value as? [Any] else { throw CocoaError(.coderReadCorrupt) }
        var decoded: [T] = []
        var skipped = 0
        for row in rows {
            do {
                let data = try JSONSerialization.data(withJSONObject: row, options: [.fragmentsAllowed])
                decoded.append(try decoder.decode(T.self, from: data))
            } catch { skipped += 1 }
        }
        return (decoded, skipped)
    }

    static func historyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let isoFormatters = [ISO8601DateFormatter.Options([.withInternetDateTime, .withFractionalSeconds]), [.withInternetDateTime]].map { options in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            return formatter
        }
        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = TimeZone.current
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let timestamp = try? value.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp)
            }
            let text = try value.decode(String.self)
            for formatter in isoFormatters {
                if let date = formatter.date(from: text) { return date }
            }
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
                localFormatter.dateFormat = format
                if let date = localFormatter.date(from: text) { return date }
            }
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unsupported iCloud history date")
        }
        return decoder
    }
}
