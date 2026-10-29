import XCTest
import Foundation
@testable import THLRedLook

private final class SearchFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var failedOnce = false
    private static var filtered = false
    private static var attempts = 0
    private static var registrations = 0

    static func configure(filtered: Bool) {
        lock.lock()
        self.filtered = filtered
        failedOnce = false
        attempts = 0
        registrations = 0
        lock.unlock()
    }

    static var counts: (Int, Int) {
        lock.lock()
        defer { lock.unlock() }
        return (attempts, registrations)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        Self.lock.lock()
        let isRegistration = url.path.contains("device_register")
        if isRegistration { Self.registrations += 1 } else { Self.attempts += 1 }
        let filtered = Self.filtered
        let fail = !isRegistration && !filtered && !Self.failedOnce
        if fail { Self.failedOnce = true }
        Self.lock.unlock()
        if fail {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost))
            return
        }
        let text: String
        if isRegistration {
            text = #"{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}"#
        } else if filtered {
            text = #"{"code":0,"search_tabs":[{"tab_type":11,"title":"综合","data":[]},{"tab_type":1,"title":"小说","data":[]},{"tab_type":2,"title":"听书","data":[]}]}"#
        } else {
            text = #"{"code":0,"search_tabs":[{"tab_type":29,"title":"剧集","has_more":false,"next_offset":0,"data":[{"video_data":[{"series_id":"7345678901234567000","title":"合成搜索剧","episode_cnt":30}]}]}]}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json; charset=utf-8", "x-tt-logid": "synthetic-log-001"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class OverseasSearchTests: XCTestCase {
    private func bridge(_ recorder: SourceDiagnostics) throws -> NativeBridge {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SearchFixtureProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel() }
        return NativeBridge(baseDirectory: directory, httpSession: session, diagnostics: recorder, diagnosticContext: "合成网络", persistentDeviceSession: false)
    }

    func testNativeDNSFailureRetriesOnceAndRetainsCause() async throws {
        SearchFixtureProtocol.configure(filtered: false)
        let recorder = SourceDiagnostics()
        let core = try bridge(recorder)
        let result = try await core.request(action: "catalog", payload: ["source": "hongguo", "query": "合成剧", "page": 1])
        XCTAssertEqual((result["items"] as? [Any])?.count, 1)
        XCTAssertEqual(SearchFixtureProtocol.counts.0, 2)
        XCTAssertEqual(SearchFixtureProtocol.counts.1, 1)
        XCTAssertTrue(recorder.entries.contains { $0.category == .dnsError && $0.errorCode.hasPrefix("DNS") })
    }

    func testTaiwanFilteredTabsNeverReportHealthyEmptySuccess() async throws {
        SearchFixtureProtocol.configure(filtered: true)
        let recorder = SourceDiagnostics()
        let core = try bridge(recorder)
        do {
            _ = try await core.request(action: "catalog", payload: ["source": "hongguo", "query": "合成剧", "page": 1])
            XCTFail("Filtered categories must be visible as a diagnostic failure")
        } catch {
            XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "SEARCH_TAB_MISSING")
            XCTAssertTrue(((error as NSError).userInfo["diagnosticAdvice"] as? String)?.contains("短剧分类") == true)
        }
        XCTAssertEqual(SearchFixtureProtocol.counts.0, 2)
        XCTAssertTrue(recorder.entries.contains { $0.failed && $0.errorCode == "SEARCH_TAB_MISSING" })
        XCTAssertTrue(recorder.report.contains("synthetic-log-001"))
        XCTAssertTrue(recorder.report.contains("11:综合"))
    }

    func testExportOnlyKeepsStructuralResponseAndSafeQueryFields() throws {
        let recorder = SourceDiagnostics()
        recorder.record(url: URL(string: "https://reading.snssdk.com/reading/bookapi/search/tab/v?tab_type=29&query=private-query&device_id=private-device&token=private-token")!, context: "合成诊断", elapsedMs: 10, status: 200,
                        body: #"{"code":0,"device_id":"private-device","cookie":"private-cookie","query":"private-query","search_tabs":[{"tab_type":11,"title":"综合","data":[]}]}"#,
                        headers: ["x-tt-logid": "synthetic-log-001"])
        let report = recorder.report
        XCTAssertFalse(report.contains("private-"))
        XCTAssertTrue(report.contains("tab_type=29"))
        XCTAssertTrue(report.contains("synthetic-log-001"))
        XCTAssertTrue(report.contains("SEARCH_TAB_MISSING"))
        XCTAssertFalse(SourceDiagnostics.redact("Cookie=private-cookie device_id=private-device").contains("private-"))
        XCTAssertFalse(SourceDiagnostics.redact("Authorization: Bearer private-token\nCookie: sid=private-session; extra=private-cookie").contains("private-"))
        XCTAssertFalse(SourceDiagnostics.redact(#"{"device_id_str":"private-device","query":"private-query"}"#).contains("private-"))
    }

    func testPhoneDownloadsSanitizedReportAndClosingRevokesLink() async throws {
        let server = DiagnosticsShareServer()
        server.start(report: "合成诊断\nCookie=private-cookie\n<script>alert(1)</script>")
        defer { server.stop() }
        for _ in 0..<100 {
            if server.url != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let url = try XCTUnwrap(server.url)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (page, pageResponse) = try await session.data(from: url)
        XCTAssertEqual((pageResponse as? HTTPURLResponse)?.statusCode, 200)
        let html = String(decoding: page, as: UTF8.self)
        XCTAssertTrue(html.contains("复制报告"))
        XCTAssertTrue(html.contains("下载日志文件"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("private-cookie"))
        let (text, response) = try await session.data(from: url.appendingPathComponent("report.txt"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: text, as: UTF8.self).contains("合成诊断"))
        XCTAssertFalse(String(decoding: text, as: UTF8.self).contains("private-cookie"))
        XCTAssertTrue((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.contains("attachment") == true)
        var missing = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        missing.path = "/wrong-token"
        let (_, denied) = try await session.data(from: missing.url!)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 404)
        server.stop()
        XCTAssertNil(server.url)
        try await Task.sleep(nanoseconds: 100_000_000)
        do {
            _ = try await session.data(from: url)
            XCTFail("Closed report must not remain available")
        } catch {}
    }
}

private final class PlaybackResponseFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var nonUTF8 = false
    private static var savedGuestMode = ""
    private static var registeredGuestExpired = false
    private static var registrations = 0
    private static var modelTimes: [Date] = []
    private static var legacyModels = 0
    private static var modelRoutes: [String] = []
    private static var webRequests = 0
    private static var implicitCookieRequests = 0
    private static var searchOffsets: [String] = []
    private static var onFourthModel: (() -> Void)?

    static func configure(nonUTF8: Bool = false, savedGuestMode: String = "") {
        lock.lock()
        defer { lock.unlock() }
        self.nonUTF8 = nonUTF8
        self.savedGuestMode = savedGuestMode
        registeredGuestExpired = false
        registrations = 0
        modelTimes = []
        legacyModels = 0
        modelRoutes = []
        webRequests = 0
        implicitCookieRequests = 0
        searchOffsets = []
        onFourthModel = nil
    }

    static func expireRegisteredGuest() {
        lock.withLock { registeredGuestExpired = true }
    }

    static func acceptUpdatedGuest() {
        lock.withLock {
            savedGuestMode = "expiry"
            registeredGuestExpired = true
        }
    }

    static var observedSearchOffsets: [String] { lock.withLock { searchOffsets } }

    static func afterFourthModel(_ action: @escaping () -> Void) {
        lock.withLock { onFourthModel = action }
    }

    static func rejectAllModels() { lock.withLock { savedGuestMode = "empty" } }

    static var counts: (registrations: Int, modelTimes: [Date], legacyModels: Int, modelRoutes: [String], webRequests: Int, implicitCookieRequests: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (registrations, modelTimes, legacyModels, modelRoutes, webRequests, implicitCookieRequests)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        let registration = url.path.contains("device_register")
        let multi = url.path.contains("multi_video_model")
        let legacy = !multi && url.path.contains("video_model")
        Self.lock.lock()
        let nonUTF8 = Self.nonUTF8
        let mode = Self.savedGuestMode
        if request.httpShouldHandleCookies || request.value(forHTTPHeaderField: "Cookie") != nil { Self.implicitCookieRequests += 1 }
        if registration { Self.registrations += 1 }
        let registrationCount = Self.registrations
        let registeredExpired = Self.registeredGuestExpired
        if multi && url.host == "api5-normal-sinfonlineb.fqnovel.com" { Self.modelTimes.append(Date()) }
        if legacy { Self.legacyModels += 1 }
        if multi || legacy { Self.modelRoutes.append((url.host ?? "") + url.path) }
        if url.host == "hongguoduanju.com" { Self.webRequests += 1 }
        let searchOffset = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value ?? "0"
        if url.path.contains("search/tab/v") { Self.searchOffsets.append(searchOffset) }
        let fourthAction = Self.modelRoutes.count == 4 && (multi || legacy) ? Self.onFourthModel : nil
        Self.lock.unlock()
        fourthAction?()
        let bytes: Data
        var headers = ["Content-Type": "application/json; charset=utf-8", "X-Tt-Logid": "synthetic-playback-log", "Set-Cookie": "private-cookie", "X-Untrusted": "private-header"]
        let status: Int
        if registration {
            status = 200
            let prefix = mode == "expiry" && registrationCount > 1 ? "735" : "734"
            bytes = Data(("{\"device_id_str\":\"" + prefix + "5678901234567100\",\"install_id_str\":\"" + prefix + "5678901234567200\"}").utf8)
        } else if request.httpMethod == "HEAD" {
            status = 200
            bytes = Data()
            headers["Content-Type"] = "video/mp4"
        } else if url.path.contains("search/tab/v") {
            status = 200
            let id = searchOffset == "0" ? "7345678901234567123" : "7345678901234567124"
            bytes = try! JSONSerialization.data(withJSONObject: ["code": 0, "search_tabs": [[
                "tab_type": 29, "title": "剧集", "has_more": searchOffset == "0", "next_offset": 6,
                "passback": "sticky-cursor", "search_id": "synthetic-search",
                "data": [["video_data": [["series_id": id, "title": "合成剧", "episode_cnt": 30]]]]
            ]]])
        } else if multi || legacy {
            let old = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "device_id" && $0.value == "7335678901234567100" } == true
            status = mode == "forbidden" ? 403 : 200
            let renewed = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "device_id" && $0.value == "7355678901234567100" } == true
            if (mode == "recover" && !old) || (mode == "expiry" && !old && (!registeredExpired || renewed)) {
                let media = Data("https://fixture.qznovelvod.com/full.mp4".utf8).base64EncodedString()
                let entry: [String: Any] = ["video_model": ["video_list": ["main": ["codec_type": "h264", "vwidth": 1080, "vheight": 1920, "main_url": media]]]]
                bytes = try! JSONSerialization.data(withJSONObject: ["code": 0, "data": ["7345678901234568456": entry]])
            } else { bytes = nonUTF8 ? Data([0xff, 0xfe, 0x80, 0x00]) : Data() }
            headers["Content-Type"] = nonUTF8 ? "application/x-protobuf" : "application/json"
            headers["Content-Encoding"] = "br"
            headers["Content-Length"] = String(bytes.count)
        } else {
            status = 404
            bytes = Data()
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class OverseasPlaybackTests: XCTestCase {
    private let seriesId = "7345678901234567123"
    private let videoId = "7345678901234568456"

    private func bridge(_ recorder: SourceDiagnostics) throws -> NativeBridge {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlaybackResponseFixtureProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel() }
        return NativeBridge(baseDirectory: root, httpSession: session, diagnostics: recorder, diagnosticContext: "合成海外取流", persistentDeviceSession: false)
    }

    private func model(_ core: NativeBridge) throws -> PlayerViewModel {
        let suite = "THLRedLook.OverseasPlayback." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let episode = Episode(id: videoId, title: "合成分集", number: 1, raw: try JSONSerialization.data(withJSONObject: ["url": "https://hongguoduanju.com/player/\(seriesId)/\(videoId)"]))
        let repository = NativeRepository(bridge: core, playbackBridge: core)
        let model = PlayerViewModel(drama: Drama(id: "hongguo:\(seriesId)", source: "hongguo", sourceId: seriesId, title: "合成海外取流"), allEpisodes: [episode], repository: repository, preloadingRepository: repository, store: LocalStore(defaults: defaults, cloudUpload: { _ in }))
        model.danmakuEnabled = false
        return model
    }

    private func failure(nonUTF8: Bool, code: String, bytes: Int) async throws {
        PlaybackResponseFixtureProtocol.configure(nonUTF8: nonUTF8)
        let recorder = SourceDiagnostics()
        let core = try bridge(recorder)
        do {
            _ = try await core.request(action: "resolve", payload: ["source": "hongguo", "drama": ["id": "hongguo:\(seriesId)"], "index": 184, "chapter": ["url": "https://hongguoduanju.com/player/\(seriesId)/\(videoId)"]])
            XCTFail("Expected unusable playback response")
        } catch {
            XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, code)
        }
        let counts = PlaybackResponseFixtureProtocol.counts
        XCTAssertEqual(counts.registrations, 1)
        XCTAssertEqual(counts.modelTimes.count, 1)
        XCTAssertEqual(counts.legacyModels, 1)
        XCTAssertEqual(counts.modelRoutes, [
            "api5-normal-sinfonlineb.fqnovel.com/novel/player/multi_video_model/v1",
            "reading.snssdk.com/novel/player/multi_video_model/v1",
            "reading.snssdk.com/novel/player/video_model/v1",
            "api5-normal.fqnovel.com/novel/player/multi_video_model/v1"
        ])
        XCTAssertEqual(counts.webRequests, 0)
        let entry = try XCTUnwrap(recorder.entries.last)
        XCTAssertEqual(entry.stage, "播放取流 第184集")
        XCTAssertEqual(entry.errorCode, code)
        XCTAssertEqual(entry.status, 200)
        XCTAssertEqual(entry.bodyBytes, bytes)
        XCTAssertEqual(entry.contentType, nonUTF8 ? "application/x-protobuf" : "application/json")
        XCTAssertEqual(entry.contentEncoding, "br")
        XCTAssertEqual(entry.declaredBodyBytes, bytes)
        XCTAssertEqual(entry.host, "api5-normal.fqnovel.com")
        XCTAssertFalse(entry.url.contains("/player/\(seriesId)"))
        XCTAssertTrue(entry.suggestion.contains("手机热点"))
        let report = recorder.report
        XCTAssertTrue(report.contains(code))
        XCTAssertTrue(report.contains("接收正文字节数: \(bytes)"))
        XCTAssertTrue(report.contains("synthetic-playback-log"))
        XCTAssertFalse(report.contains("private-"))
        print("THL_OVERSEAS_RESPONSE code=\(code) bytes=\(bytes) upstreamRetained=true registrations=\(counts.registrations) modelRequests=\(counts.modelTimes.count)")
    }

    func testHTTP200EmptyBodyRetainsUpstreamAndDoesNotRefreshGuest() async throws {
        try await failure(nonUTF8: false, code: "EMPTY_RESPONSE", bytes: 0)
    }

    func testNonUTF8BodyKeepsHTTP200AndNonzeroByteCount() async throws {
        try await failure(nonUTF8: true, code: "RESPONSE_NOT_UTF8", bytes: 4)
    }

    func testAutomaticRecoveryUsesBackoffAndStopsAfterTwoRetries() async throws {
        PlaybackResponseFixtureProtocol.configure()
        let core = try bridge(SourceDiagnostics())
        let model = try model(core)
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        let deadline = Date().addingTimeInterval(15)
        while model.errorMessage == nil, Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.errorMessage?.contains("EMPTY_RESPONSE") == true)
        let counts = PlaybackResponseFixtureProtocol.counts
        XCTAssertEqual(counts.registrations, 1)
        XCTAssertEqual(counts.modelTimes.count, 3)
        XCTAssertLessThanOrEqual(counts.legacyModels, 6)
        if counts.modelTimes.count == 3 {
            XCTAssertGreaterThanOrEqual(counts.modelTimes[1].timeIntervalSince(counts.modelTimes[0]), 0.95)
            XCTAssertGreaterThanOrEqual(counts.modelTimes[2].timeIntervalSince(counts.modelTimes[1]), 2.95)
        }
        XCTAssertNil(model.plan)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isLoading)
        print("THL_OVERSEAS_BACKOFF automaticRetries=2 guestRegistrations=1 stopped=true")
    }

    func testOfficialPlaybackDoesNotInjectSharedCookieState() async throws {
        PlaybackResponseFixtureProtocol.configure()
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: ".fqnovel.com", .path: "/", .name: "THLSyntheticUnrelated", .value: "synthetic-unrelated-session"]))
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        let config = URLSessionConfiguration.default
        config.protocolClasses = [PlaybackResponseFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = NativeBridge(baseDirectory: root, httpSession: session, diagnostics: SourceDiagnostics(), persistentDeviceSession: false)
        do {
            _ = try await bridge.request(action: "resolve", payload: ["source": "hongguo", "drama": ["id": "hongguo:\(seriesId)"], "index": 1, "chapter": ["url": "https://hongguoduanju.com/player/\(seriesId)/\(videoId)"]])
            XCTFail("Synthetic empty result must remain a failure")
        } catch { XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "EMPTY_RESPONSE") }
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.implicitCookieRequests, 0)
    }

    func testDiagnosticPlaybackUsesBoundedRecoveryAndPreservesError() async throws {
        PlaybackResponseFixtureProtocol.configure()
        let core = try bridge(SourceDiagnostics())
        let start = Date()
        do {
            _ = try await SourceDiagnosticRunner.resolvePlayback(bridge: core, payload: ["source": "hongguo", "drama": ["id": "hongguo:\(seriesId)"], "index": 1, "chapter": ["url": "https://hongguoduanju.com/player/\(seriesId)/\(videoId)"]])
            XCTFail("Persistent empty responses must remain a diagnostic failure")
        } catch { XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "EMPTY_RESPONSE") }
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelTimes.count, 3)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 4)
    }

    func testLeavingPlayerCancelsPendingEmptyResponseRetry() async throws {
        PlaybackResponseFixtureProtocol.configure()
        let core = try bridge(SourceDiagnostics())
        let model = try model(core)
        await model.preparePlayback(episodeIndex: 1)
        model.onDisappear()
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelTimes.count, 1)
        XCTAssertNil(model.player)
    }
}

private final class GuestTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date().timeIntervalSince1970

    func now() -> TimeInterval { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

@MainActor
final class SavedGuestPlaybackTests: XCTestCase {
    private var guestDefaults: UserDefaults!

    private func environment(mode: String, timeProvider: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) throws -> (NativeBridge, URLSession, URL, SourceDiagnostics) {
        let suite = "THLRedLook.SavedGuest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        guestDefaults = defaults
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(#"{"device_id":"7335678901234567100","iid":"7335678901234567200","cdid":"11111111-1111-4111-8111-111111111111"}"#, forKey: "thl_tv_hongguo_device_session")
        defaults.removeObject(forKey: "thl_tv_hongguo_guest_recovery_v2_at")
        PlaybackResponseFixtureProtocol.configure(savedGuestMode: mode)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlaybackResponseFixtureProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let recorder = SourceDiagnostics()
        return (NativeBridge(baseDirectory: root, httpSession: session, diagnostics: recorder, diagnosticContext: "缓存会话恢复", deviceDefaults: defaults, timeProvider: timeProvider), session, root, recorder)
    }

    private var payload: [String: Any] {
        ["source": "hongguo", "drama": ["id": "hongguo:7345678901234567123"], "index": 1, "chapter": ["url": "https://hongguoduanju.com/player/7345678901234567123/7345678901234568456"]]
    }

    func testExpiredSavedGuestRenewsOnceAfterFourEmptyOfficialResponses() async throws {
        let (bridge, _, _, recorder) = try environment(mode: "recover")
        let plan = try await bridge.request(action: "resolve", payload: payload)
        XCTAssertEqual(plan["quality"] as? Int, 1080)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 5)
        XCTAssertTrue(recorder.entries.contains { $0.stage == "游客会话恢复" })
    }

    func testPersistentEmptyResponseCannotRepeatedlyReplaceGuest() async throws {
        let (bridge, session, root, recorder) = try environment(mode: "empty")
        let relaunched = NativeBridge(baseDirectory: root.appendingPathComponent("relaunch"), httpSession: session, diagnostics: recorder, deviceDefaults: guestDefaults)
        for target in [bridge, bridge, relaunched] {
            do { _ = try await target.request(action: "resolve", payload: payload); XCTFail("Empty responses must remain errors") }
            catch { XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "EMPTY_RESPONSE") }
        }
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(recorder.entries.filter { $0.stage == "游客会话恢复" }.count, 1)
    }

    func testLegacyRecoveryCooldownDoesNotBlockCorrectedRecovery() async throws {
        let (bridge, _, _, recorder) = try environment(mode: "recover")
        guestDefaults.set(Date().timeIntervalSince1970, forKey: "thl_tv_hongguo_guest_recovered_at")
        let plan = try await bridge.request(action: "resolve", payload: payload)
        XCTAssertEqual(plan["quality"] as? Int, 1080)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(recorder.entries.filter { $0.stage == "游客会话恢复" }.count, 1)
    }

    func testInheritedExpiredGuestDoesNotReturnAfterAutomaticRecovery() async throws {
        let (bridge, session, root, recorder) = try environment(mode: "recover")
        let defaults = try XCTUnwrap(guestDefaults)
        let registration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        addTeardownBlock { defaults.setVolatileDomain(registration, forName: UserDefaults.registrationDomain) }
        let stale = try XCTUnwrap(defaults.string(forKey: "thl_tv_hongguo_device_session"))
        defaults.register(defaults: ["thl_tv_hongguo_device_session": stale])
        defaults.removeObject(forKey: "thl_tv_hongguo_device_session")
        XCTAssertEqual(defaults.string(forKey: "thl_tv_hongguo_device_session"), stale)
        _ = try await bridge.request(action: "resolve", payload: payload)
        let relaunched = NativeBridge(baseDirectory: root.appendingPathComponent("relaunch"), httpSession: session, diagnostics: recorder, deviceDefaults: guestDefaults)
        _ = try await relaunched.request(action: "resolve", payload: payload)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(recorder.entries.filter { $0.stage == "游客会话恢复" }.count, 1)
        XCTAssertNotEqual(defaults.string(forKey: "thl_tv_hongguo_device_session"), stale)
    }

    func testOfficialResetMasksInheritedGuestAndPreservesLibrary() async throws {
        let (bridge, _, _, _) = try environment(mode: "recover")
        let defaults = try XCTUnwrap(guestDefaults)
        let registration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        addTeardownBlock { defaults.setVolatileDomain(registration, forName: UserDefaults.registrationDomain) }
        let stale = try XCTUnwrap(defaults.string(forKey: "thl_tv_hongguo_device_session"))
        defaults.register(defaults: ["thl_tv_hongguo_device_session": stale])
        defaults.set(Data("saved-history".utf8), forKey: "zgj_tv_history")
        defaults.set(Data("saved-follows".utf8), forKey: "zgj_tv_followed_dramas")
        let history = defaults.data(forKey: "zgj_tv_history")
        let follows = defaults.data(forKey: "zgj_tv_followed_dramas")
        _ = try await bridge.request(action: "jsSource.resetOfficial", payload: [:])
        XCTAssertEqual(defaults.string(forKey: "thl_tv_hongguo_device_session"), "")
        _ = try await bridge.request(action: "resolve", payload: payload)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(defaults.data(forKey: "zgj_tv_history"), history)
        XCTAssertEqual(defaults.data(forKey: "zgj_tv_followed_dramas"), follows)
    }

    func testActiveRegisteredGuestRecoversAfterTenMinutes() async throws {
        let clock = GuestTestClock()
        let (bridge, _, _, recorder) = try environment(mode: "expiry", timeProvider: { clock.now() })
        guestDefaults.set("", forKey: "thl_tv_hongguo_device_session")
        _ = try await bridge.request(action: "resolve", payload: payload)
        clock.advance(660)
        PlaybackResponseFixtureProtocol.expireRegisteredGuest()
        var refresh = payload
        refresh["avoidUrl"] = "https://fixture.qznovelvod.com/expired.mp4"
        let plan = try await bridge.request(action: "resolve", payload: refresh)
        XCTAssertEqual(plan["quality"] as? Int, 1080)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 2)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 6)
        XCTAssertEqual(recorder.entries.filter { $0.stage == "游客会话恢复" }.count, 1)
    }

    func testPreviouslyWorkingGuestCanRecoverBeforeTenMinutes() async throws {
        let clock = GuestTestClock()
        let (bridge, _, _, recorder) = try environment(mode: "expiry", timeProvider: { clock.now() })
        guestDefaults.set("", forKey: "thl_tv_hongguo_device_session")
        _ = try await bridge.request(action: "resolve", payload: payload)
        clock.advance(30)
        PlaybackResponseFixtureProtocol.expireRegisteredGuest()
        var refresh = payload
        refresh["avoidUrl"] = "https://fixture.qznovelvod.com/expired.mp4"
        let plan = try await bridge.request(action: "resolve", payload: refresh)
        XCTAssertEqual(plan["quality"] as? Int, 1080)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 2)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 6)
        XCTAssertEqual(recorder.entries.filter { $0.stage == "游客会话恢复" }.count, 1)
    }

    func testFreshGuestThatNeverPlayedDoesNotRepeatedlyRegister() async throws {
        let (bridge, _, _, recorder) = try environment(mode: "empty")
        guestDefaults.set("", forKey: "thl_tv_hongguo_device_session")
        do { _ = try await bridge.request(action: "resolve", payload: payload); XCTFail("Empty response must remain visible") }
        catch { XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "EMPTY_RESPONSE") }
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 4)
        XCTAssertFalse(recorder.entries.contains { $0.stage == "游客会话恢复" })
    }

    func testUpdatedGuestIsAdoptedBeforeRetryingAnUnsuccessfulContext() async throws {
        let (bridge, _, _, recorder) = try environment(mode: "empty")
        guestDefaults.set("", forKey: "thl_tv_hongguo_device_session")
        do { _ = try await bridge.request(action: "resolve", payload: payload); XCTFail("Initial fixture must fail") }
        catch { XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "EMPTY_RESPONSE") }
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 4)
        PlaybackResponseFixtureProtocol.acceptUpdatedGuest()
        guestDefaults.set(#"{"device_id":"7355678901234567100","iid":"7355678901234567200","cdid":"22222222-2222-4222-8222-222222222222"}"#, forKey: "thl_tv_hongguo_device_session")
        guestDefaults.set(Date().timeIntervalSince1970, forKey: "thl_tv_hongguo_guest_created_at")
        let plan = try await bridge.request(action: "resolve", payload: payload)
        XCTAssertEqual(plan["quality"] as? Int, 1080)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 5)
        XCTAssertFalse(recorder.entries.contains { $0.stage == "游客会话恢复" })
    }

    func testUpdatedGuestPreservesSearchPaginationInExistingContext() async throws {
        let (bridge, _, _, recorder) = try environment(mode: "expiry")
        guestDefaults.set("", forKey: "thl_tv_hongguo_device_session")
        let first = try await bridge.request(action: "catalog", payload: ["source": "hongguo", "query": "合成剧", "page": 1])
        XCTAssertEqual(first["hasMore"] as? Bool, true)
        PlaybackResponseFixtureProtocol.acceptUpdatedGuest()
        guestDefaults.set(#"{"device_id":"7355678901234567100","iid":"7355678901234567200","cdid":"22222222-2222-4222-8222-222222222222"}"#, forKey: "thl_tv_hongguo_device_session")
        let plan = try await bridge.request(action: "resolve", payload: payload)
        XCTAssertEqual(plan["quality"] as? Int, 1080)
        let second = try await bridge.request(action: "catalog", payload: ["source": "hongguo", "query": "合成剧", "page": 2])
        XCTAssertEqual((second["items"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.observedSearchOffsets, ["0", "6"])
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 1)
        XCTAssertEqual(recorder.entries.filter { $0.stage == "游客会话同步" }.count, 1)
    }

    func testOlderPersistedGuestCannotRollBackCurrentContext() async throws {
        let clock = GuestTestClock()
        let (bridge, _, _, recorder) = try environment(mode: "expiry", timeProvider: { clock.now() })
        guestDefaults.set("", forKey: "thl_tv_hongguo_device_session")
        _ = try await bridge.request(action: "resolve", payload: payload)
        let initialCreated = clock.now()
        clock.advance(2)
        PlaybackResponseFixtureProtocol.acceptUpdatedGuest()
        guestDefaults.set(#"{"device_id":"7355678901234567100","iid":"7355678901234567200","cdid":"22222222-2222-4222-8222-222222222222"}"#, forKey: "thl_tv_hongguo_device_session")
        guestDefaults.set(clock.now(), forKey: "thl_tv_hongguo_guest_created_at")
        _ = try await bridge.request(action: "resolve", payload: payload)
        guestDefaults.set(#"{"device_id":"7335678901234567100","iid":"7335678901234567200"}"#, forKey: "thl_tv_hongguo_device_session")
        guestDefaults.set(initialCreated, forKey: "thl_tv_hongguo_guest_created_at")
        var fresh = payload
        fresh["avoidUrl"] = "https://fixture.qznovelvod.com/full.mp4"
        PlaybackResponseFixtureProtocol.rejectAllModels()
        do { _ = try await bridge.request(action: "resolve", payload: fresh); XCTFail("Fixture must fail") }
        catch { XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "EMPTY_RESPONSE") }
        PlaybackResponseFixtureProtocol.acceptUpdatedGuest()
        let plan = try await bridge.request(action: "resolve", payload: fresh)
        XCTAssertEqual(plan["quality"] as? Int, 1080)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 7)
        XCTAssertEqual(recorder.entries.filter { $0.stage == "游客会话同步" }.count, 1)
    }

    func testInProgressRecoveryTombstoneCannotTriggerDuplicateRegistration() async throws {
        let (bridge, _, _, _) = try environment(mode: "recover")
        let defaults = try XCTUnwrap(guestDefaults)
        PlaybackResponseFixtureProtocol.afterFourthModel {
            defaults.set("", forKey: "thl_tv_hongguo_device_session")
            defaults.set(Date().timeIntervalSince1970, forKey: "thl_tv_hongguo_guest_recovery_v2_at")
        }
        do { _ = try await bridge.request(action: "resolve", payload: payload); XCTFail("Another runtime is renewing the guest") }
        catch { XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "EMPTY_RESPONSE") }
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 0)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 4)
    }

    func testCompletedTimestampWriteUpdatesCurrentContextDiagnostics() async throws {
        let clock = GuestTestClock()
        let (bridge, _, _, _) = try environment(mode: "empty", timeProvider: { clock.now() })
        guestDefaults.set("", forKey: "thl_tv_hongguo_device_session")
        do { _ = try await bridge.request(action: "resolve", payload: payload); XCTFail("Fixture must fail") }
        catch { XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "EMPTY_RESPONSE") }
        let initial = clock.now()
        clock.advance(10)
        guestDefaults.set(initial + 5, forKey: "thl_tv_hongguo_guest_created_at")
        do { _ = try await bridge.request(action: "resolve", payload: payload); XCTFail("Fixture must fail") }
        catch { XCTAssertTrue(((error as NSError).userInfo["diagnosticSession"] as? String ?? "").contains("创建距今：5秒")) }
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
    }

    func testValidModelIsReusedUntilPlayerRequestsFreshMedia() async throws {
        let (bridge, _, _, _) = try environment(mode: "recover")
        let first = try await bridge.request(action: "resolve", payload: payload)
        let initialCount = PlaybackResponseFixtureProtocol.counts.modelRoutes.count
        XCTAssertEqual(initialCount, 5)
        var quality = payload
        quality["quality"] = 720
        let reused = try await bridge.request(action: "resolve", payload: quality)
        XCTAssertEqual(reused["quality"] as? Int, 1080)
        XCTAssertEqual(reused["url"] as? String, first["url"] as? String)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, initialCount)
        var refresh = payload
        refresh["avoidUrl"] = first["url"]
        _ = try await bridge.request(action: "resolve", payload: refresh)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, initialCount + 1)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 1)
    }

    func testFailureReportsSessionAgeAndPriorSuccessfulPlayback() async throws {
        let (bridge, _, _, recorder) = try environment(mode: "recover")
        _ = try await bridge.request(action: "resolve", payload: payload)
        PlaybackResponseFixtureProtocol.configure(savedGuestMode: "empty")
        var refresh = payload
        refresh["avoidUrl"] = "https://fixture.qznovelvod.com/expired.mp4"
        do { _ = try await bridge.request(action: "resolve", payload: refresh); XCTFail("Empty responses must remain errors") }
        catch {
            let session = (error as NSError).userInfo["diagnosticSession"] as? String ?? ""
            XCTAssertTrue(session.contains("成功取流：1次"))
            XCTAssertFalse(session.contains("创建距今：未记录"))
        }
        XCTAssertTrue(try XCTUnwrap(recorder.entries.last).sessionStatus.contains("成功取流：1次"))
    }

    func testExplicitForbiddenResponseDoesNotReplaceSavedGuest() async throws {
        let (bridge, _, _, _) = try environment(mode: "forbidden")
        do { _ = try await bridge.request(action: "resolve", payload: payload); XCTFail("Explicit denial must be retained") }
        catch { XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "HTTP_403") }
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.registrations, 0)
        XCTAssertEqual(PlaybackResponseFixtureProtocol.counts.modelRoutes.count, 1)
    }
}

private final class NetworkEgressFixtureProtocol: URLProtocol {
    static let lock = NSLock()
    private static var calls = 0
    private static var failPrimary = false
    static func configure(failPrimary: Bool) {
        lock.lock();defer { lock.unlock() }
        self.failPrimary = failPrimary; calls = 0
    }
    static var count: Int { lock.lock();defer { lock.unlock() };return calls }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.lock();Self.calls += 1;let fail = Self.failPrimary && request.url?.host == "api.ip.sb";Self.lock.unlock()
        let body = Data(#"{"ip":"203.0.113.23","country":"Synthetic Region","country_code":"TW","region":"Synthetic State","city":"Synthetic City","latitude":1,"cookie":"private-cookie"}"#.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: fail ? 503 : 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class NetworkEgressTests: XCTestCase {
    private func lookup() -> NetworkEgressLookup {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NetworkEgressFixtureProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel() }
        return NetworkEgressLookup(session: session)
    }
    func testParsesIPv4AndIPv6WithoutUnrelatedResponseFields() throws {
        for ip in ["203.0.113.23", "2001:db8::23"] {
            let body = Data("{\"ip\":\"\(ip)\",\"country\":\"Synthetic Region\",\"country_code\":\"TW\",\"cookie\":\"private-cookie\"}".utf8)
            let value = try XCTUnwrap(NetworkEgressLookup.parse(body, provider: "IP.SB"))
            XCTAssertEqual(value.ip, ip)
            XCTAssertEqual(value.countryCode, "TW")
            XCTAssertTrue(value.reportLines.joined().contains("IP.SB"))
            XCTAssertFalse(value.reportLines.joined().contains("private-cookie"))
            XCTAssertTrue(value.reportLines.joined().contains("代理分流"))
        }
        XCTAssertNil(NetworkEgressLookup.parse(Data(#"{"ip":"invalid-address"}"#.utf8), provider: "Synthetic"))
        XCTAssertNil(NetworkEgressLookup.parse(Data(#"{"ip":"203.0.113.23","success":false}"#.utf8), provider: "Synthetic"))
    }
    func testProviderFallbackRetainsMatchingIPAndLocation() async {
        NetworkEgressFixtureProtocol.configure(failPrimary: true)
        let value = await lookup().lookup()
        XCTAssertEqual(value.ip, "203.0.113.23")
        XCTAssertEqual(value.countryCode, "TW")
        XCTAssertEqual(value.provider, "IPWho.is")
        XCTAssertEqual(NetworkEgressFixtureProtocol.count, 2)
    }
    func testReportIncludesIPProvenanceAndCoalescesRefresh() async {
        NetworkEgressFixtureProtocol.configure(failPrimary: false)
        let recorder = SourceDiagnostics()
        let lookup = lookup()
        async let first: Void = recorder.refreshNetworkEgress(using: lookup)
        async let second: Void = recorder.refreshNetworkEgress(using: lookup)
        _ = await (first, second)
        await recorder.refreshNetworkEgress(using: lookup)
        XCTAssertEqual(NetworkEgressFixtureProtocol.count, 1)
        let report = recorder.report
        XCTAssertTrue(report.contains("203.0.113.23"))
        XCTAssertTrue(report.contains("Synthetic Region"))
        XCTAssertTrue(report.contains("IP 检测时间"))
        XCTAssertFalse(report.contains("private-cookie"))
        XCTAssertTrue(recorder.entries.isEmpty)
    }
    func testLiveNetworkEgressLookup() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HONGGUO_LIVE"] == "1")
        let result = await NetworkEgressLookup().lookup()
        XCTAssertFalse(result.ip.isEmpty, result.error)
        XCTAssertFalse(result.countryCode.isEmpty)
        print("THL_EGRESS_LIVE validIP=\(!result.ip.isEmpty) countryCode=\(result.countryCode) provider=\(result.provider)")
    }
}
