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
