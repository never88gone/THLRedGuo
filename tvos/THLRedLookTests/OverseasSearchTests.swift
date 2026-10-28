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
    private static var registrations = 0
    private static var modelTimes: [Date] = []
    private static var legacyModels = 0
    private static var modelRoutes: [String] = []
    private static var webRequests = 0

    static func configure(nonUTF8: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        self.nonUTF8 = nonUTF8
        registrations = 0
        modelTimes = []
        legacyModels = 0
        modelRoutes = []
        webRequests = 0
    }

    static var counts: (registrations: Int, modelTimes: [Date], legacyModels: Int, modelRoutes: [String], webRequests: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (registrations, modelTimes, legacyModels, modelRoutes, webRequests)
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
        if registration { Self.registrations += 1 }
        if multi && url.host == "api5-normal-sinfonlineb.fqnovel.com" { Self.modelTimes.append(Date()) }
        if legacy { Self.legacyModels += 1 }
        if multi || legacy { Self.modelRoutes.append((url.host ?? "") + url.path) }
        if url.host == "hongguoduanju.com" { Self.webRequests += 1 }
        Self.lock.unlock()
        let bytes: Data
        var headers = ["Content-Type": "application/json; charset=utf-8", "X-Tt-Logid": "synthetic-playback-log", "Set-Cookie": "private-cookie", "X-Untrusted": "private-header"]
        let status: Int
        if registration {
            status = 200
            bytes = Data(#"{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}"#.utf8)
        } else if multi || legacy {
            status = 200
            bytes = nonUTF8 ? Data([0xff, 0xfe, 0x80, 0x00]) : Data()
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
        let model = PlayerViewModel(drama: Drama(id: "hongguo:\(seriesId)", source: "hongguo", sourceId: seriesId, title: "合成海外取流"), allEpisodes: [episode], repository: repository, preloadingRepository: repository, store: LocalStore(defaults: defaults))
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
