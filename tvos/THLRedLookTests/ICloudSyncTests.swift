import XCTest
@testable import THLRedLook

private final class MemoryICloudStore: ICloudKeyValueStore {
    var values: [String: String] = [:]
    var writes: [String] = []
    var available = true
    var onSynchronize: (() -> Void)?
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: Any?, forKey key: String) {
        values[key] = value as? String
        writes.append(key)
    }
    func synchronize() -> Bool {
        let callback = onSynchronize
        onSynchronize = nil
        callback?()
        return available
    }
}

@MainActor
final class ICloudSyncTests: XCTestCase {
    private func setup() throws -> (ICloudSyncService, MemoryICloudStore, LocalStore) {
        let name = "THLRedLook.QA.ICloud." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(true, forKey: "thl_icloud_sync_enabled")
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let cloud = MemoryICloudStore()
        return (ICloudSyncService(kvStore: cloud, defaults: defaults, observeChanges: false), cloud, LocalStore(defaults: defaults))
    }

    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("test/fixtures/icloud_flutter_v1.json"))) as! [String: Any]
    }

    private func seed(_ cloud: MemoryICloudStore) throws {
        let data = try fixture()
        for (key, section) in [(ICloudSyncService.keyHistory, "history"), (ICloudSyncService.keyFollows, "follows"), (ICloudSyncService.keySettings, "settings")] {
            cloud.values[key] = String(decoding: try JSONSerialization.data(withJSONObject: data[section]!, options: [.sortedKeys]), as: UTF8.self)
        }
    }

    func testFlutterPayloadImportsHistoryFavoritesAndSettingsWithoutEchoUpload() throws {
        let (service, cloud, store) = try setup()
        try seed(cloud)
        let before = cloud.values
        service.syncWithCloud(store: store)
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.history.first?.drama.cleanSourceId, "7688558312157088793")
        XCTAssertEqual(store.history.first?.episode, 3)
        XCTAssertEqual(store.history.first?.position, 45.25)
        XCTAssertEqual(store.followedDramas.count, 1)
        XCTAssertEqual(store.follows["hongguo:7688558312157088793"], .watching)
        XCTAssertFalse(store.danmakuEnabled)
        XCTAssertEqual(cloud.values, before)
        XCTAssertTrue(cloud.writes.isEmpty)
        service.syncWithCloud(store: store)
        XCTAssertTrue(cloud.writes.isEmpty)
    }

    func testNewestHistoryWinsAndBothLocalAndRemoteFavoritesRemain() throws {
        let (service, cloud, store) = try setup()
        try seed(cloud)
        let old = Drama(id: "hongguo:local", title: "本地合成剧")
        let shared = Drama(id: "hongguo:7688558312157088793", sourceId: "7688558312157088793", title: "同步合成短剧")
        store.applySyncedData(history: [WatchEntry(drama: shared, episode: 8, position: 88, duration: 120, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))],
                              follows: [old.id: .wishlist], followedDramas: [old])
        service.syncWithCloud(store: store)
        XCTAssertEqual(store.history.first?.episode, 8)
        XCTAssertEqual(store.followedDramas.count, 2)
        let uploaded = try ICloudSyncService.historyDecoder().decode([WatchEntry].self, from: Data(cloud.values[ICloudSyncService.keyHistory]!.utf8))
        XCTAssertEqual(uploaded.first?.episode, 8)
        let writes = cloud.writes.count
        service.syncWithCloud(store: store)
        XCTAssertEqual(cloud.writes.count, writes)
    }

    func testMalformedRecordDoesNotDiscardGoodHistoryOrRewriteCloudOriginal() throws {
        let (service, cloud, store) = try setup()
        try seed(cloud)
        var rows = try JSONSerialization.jsonObject(with: Data(cloud.values[ICloudSyncService.keyHistory]!.utf8)) as! [Any]
        rows.insert(["drama": ["id": "bad"], "updatedAt": false], at: 0)
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        cloud.values[ICloudSyncService.keyHistory] = raw
        service.syncWithCloud(store: store)
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(cloud.values[ICloudSyncService.keyHistory], raw)
        XCTAssertTrue(service.lastStatusMessage.contains("格式不兼容"))
    }

    func testUnavailableCloudDoesNotUploadOrClaimSuccess() throws {
        let (service, cloud, store) = try setup()
        cloud.available = false
        service.syncWithCloud(store: store)
        XCTAssertTrue(cloud.writes.isEmpty)
        XCTAssertNil(service.lastSyncDate)
        XCTAssertTrue(service.lastStatusMessage.contains("不可用"))
    }

    func testCloudSettingsImportDoesNotScheduleTheTwoSecondUploadLoop() throws {
        let name = "THLRedLook.QA.ICloud.Loop." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        var uploads = 0
        let store = LocalStore(defaults: defaults, cloudUpload: { _ in uploads += 1 })
        store.applySyncedData(history: [], follows: [:], followedDramas: [], source: "hongguo", danmaku: false)
        XCTAssertEqual(uploads, 0)
        store.danmakuEnabled = false
        store.setSource("hongguo")
        XCTAssertEqual(uploads, 0)
        store.danmakuEnabled = true
        XCTAssertEqual(uploads, 1)
    }

    func testDisableDuringSyncCannotApplyOrUploadStaleData() throws {
        let (service, cloud, store) = try setup()
        try seed(cloud)
        cloud.onSynchronize = { service.isSyncEnabled = false }
        service.syncWithCloud(store: store)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(cloud.writes.isEmpty)
        XCTAssertEqual(service.lastStatusMessage, "已停用")
    }

    func testSyncRequestDuringSyncRunsAgainInsteadOfBeingDropped() async throws {
        let (service, cloud, store) = try setup()
        try seed(cloud)
        cloud.onSynchronize = { service.syncWithCloud(store: store) }
        service.syncWithCloud(store: store)
        let count = cloud.writes.count
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(service.isSyncing)
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(cloud.writes.count, count)
    }

    private func oldHistoryDocument() throws -> [String: Any] {
        if let path = ProcessInfo.processInfo.environment["ICLOUD_OLD_IOS_HISTORY"] {
            return try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        }
        let template = (try fixture()["history"] as! [[String: Any]])[0]
        var rows: [[String: Any]] = []
        var expected: [[String: Any]] = []
        for index in 0..<180 {
            var row = template
            var drama = row["drama"] as! [String: Any]
            drama["id"] = "hongguo:old-ios-\(index)"
            drama["sourceId"] = "old-ios-\(index)"
            drama["cover"] = ""
            row["drama"] = drama
            let date = Date(timeIntervalSince1970: 1_787_000_000 + Double(index * 60))
            row["updatedAt"] = ISO8601DateFormatter().string(from: date)
            rows.append(row)
            expected.append(["id": drama["id"]!, "episode": row["episode"]!, "position": row["position"]!, "duration": row["duration"]!, "updatedAtMillis": date.timeIntervalSince1970 * 1000])
        }
        return ["history": String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self), "expected": expected, "count": rows.count]
    }

    private func verifyOldHistory(_ document: [String: Any]) throws {
        let name = "THLRedLook.QA.ICloud.OldHistory." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(true, forKey: "thl_icloud_sync_enabled")
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let cloud = MemoryICloudStore()
        let service = ICloudSyncService(kvStore: cloud, defaults: defaults, observeChanges: false)
        let store = LocalStore(defaults: defaults, cloudUpload: { _ in })
        let existing = Drama(id: "hongguo:tv-existing", title: "电视本地合成剧")
        store.applySyncedData(history: [WatchEntry(drama: existing, episode: 2, position: 12, duration: 300)], follows: [existing.id: .wishlist], followedDramas: [existing])
        service.syncWithCloud(store: store)
        XCTAssertNotNil(service.lastSyncDate)
        cloud.values[ICloudSyncService.keyHistory] = document["history"] as? String
        service.syncWithCloud(store: store)
        let expected = document["expected"] as! [[String: Any]]
        XCTAssertEqual(store.history.count, expected.count + 1)
        for row in expected {
            let entry = try XCTUnwrap(store.getWatchEntry(dramaId: row["id"] as! String))
            XCTAssertEqual(entry.episode, (row["episode"] as! NSNumber).intValue)
            XCTAssertEqual(entry.position, (row["position"] as! NSNumber).doubleValue, accuracy: 0.001)
            XCTAssertEqual(entry.duration, (row["duration"] as! NSNumber).doubleValue, accuracy: 0.001)
            XCTAssertEqual(entry.updatedAt.timeIntervalSince1970 * 1000, (row["updatedAtMillis"] as! NSNumber).doubleValue, accuracy: 1)
            let detail = DetailViewModel(drama: entry.drama, store: store)
            XCTAssertEqual(detail.lastWatchEntry?.episode, entry.episode)
            XCTAssertEqual(detail.lastWatchEntry?.position, entry.position)
        }
        XCTAssertEqual(LibraryViewModel(store: store).historyList.count, expected.count + 1)
        let newDrama = Drama(id: "hongguo:tv-new", title: "电视新观看合成剧")
        store.recordWatch(drama: newDrama, episode: 1, position: 8, duration: 300)
        XCTAssertEqual(store.history.count, expected.count + 2)
        let restored = LocalStore(defaults: defaults, cloudUpload: { _ in })
        XCTAssertEqual(restored.history, store.history)
        XCTAssertEqual(restored.followedDramas, [existing])
        if expected.count == 180, let path = ProcessInfo.processInfo.environment["ICLOUD_OLD_TV_DEFAULTS"] {
            let preferences: [String: Any] = [
                "zgj_tv_history": try JSONEncoder().encode(restored.history),
                "zgj_tv_follows": try JSONEncoder().encode(restored.follows),
                "zgj_tv_followed_dramas": try JSONEncoder().encode(restored.followedDramas),
                "zgj_tv_current_source": "hongguo",
                "thl_icloud_sync_enabled": false
            ]
            try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0).write(to: URL(fileURLWithPath: path))
        }
        service.syncWithCloud(store: store)
        let count = cloud.writes.count
        service.syncWithCloud(store: store)
        XCTAssertEqual(cloud.writes.count, count)
        print("THL_OLD_HISTORY imported=\(expected.count) library=true resumeFields=true newPlaybackPreservesOld=true persisted=true favoritesPreserved=true")
    }

    func testOldIOSHistoryImportsEvenAfterLastSyncAndSurvivesNewTVPlayback() throws {
        try verifyOldHistory(oldHistoryDocument())
    }

    func testArchivedIOSHistoryUsesTheSameImportAndResumePath() throws {
        guard let path = ProcessInfo.processInfo.environment["ICLOUD_ARCHIVED_IOS_HISTORY"] else { throw XCTSkip("Archived history fixture not supplied") }
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        try verifyOldHistory(document)
    }

    func testNewTVPlaybackRetainsTheSame300HistoryLimitAsIOS() {
        let name = "THLRedLook.QA.ICloud.HistoryLimit." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let store = LocalStore(defaults: defaults, cloudUpload: { _ in })
        let entries = (0..<300).reversed().map { index in
            WatchEntry(drama: Drama(id: "hongguo:limit-\(index)", title: "合成旧记录 \(index)"), episode: 2, position: 10, duration: 300, updatedAt: Date(timeIntervalSince1970: 1_787_000_000 + Double(index)))
        }
        store.applySyncedData(history: entries, follows: [:], followedDramas: [])
        store.recordWatch(drama: entries[100].drama, episode: 3, position: 28, duration: 300)
        XCTAssertEqual(Set(store.history.map(\.id)), Set(entries.map(\.id)))
        store.recordWatch(drama: Drama(id: "hongguo:limit-new", title: "合成新观看"), episode: 1, position: 6, duration: 300)
        XCTAssertEqual(store.history.count, 300)
        XCTAssertNil(store.getWatchEntry(dramaId: "hongguo:limit-0"))
        XCTAssertNotNil(store.getWatchEntry(dramaId: "hongguo:limit-new"))
        XCTAssertEqual(LocalStore(defaults: defaults, cloudUpload: { _ in }).history, store.history)
    }
}
