import XCTest
@testable import THLRedLook

@MainActor
final class LocalLibraryTests: XCTestCase {
    private func storage() throws -> (UserDefaults, String) {
        let name = "THLRedLook.QA.Library." + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    func testOfficialSourceUpgradeRefreshesMetadataAndRuntimeIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let old = "const meta={id:'hongguo',name:'stale',version:'old-cache'};const spider={play:function(){return {url:''}}};"
        try old.write(to: sources.appendingPathComponent("hongguo.js"), atomically: true, encoding: .utf8)
        let recorder = SourceDiagnostics()
        let bridge = NativeBridge(baseDirectory: root, diagnostics: recorder, diagnosticContext: "升级验证", persistentDeviceSession: false)
        let response = try await bridge.request(action: "jsSource.identity", payload: [:])
        XCTAssertEqual(response["sha256"] as? String, SourceDiagnostics.sourceHash)
        XCTAssertEqual(response["runtimeReady"] as? Bool, true)
        XCTAssertEqual(SourceDiagnostics.sourceManifest["sha256"], SourceDiagnostics.sourceHash)
        XCTAssertFalse(SourceDiagnostics.sourceManifest["sourceCommit"]?.isEmpty ?? true)
        let listing = try await bridge.request(action: "jsSource.list", payload: [:])
        let official = (listing["items"] as? [[String: Any]])?.first { $0["id"] as? String == "hongguo" }
        XCTAssertEqual(official?["version"] as? String, SourceDiagnostics.sourceManifest["sourceVersion"])
        XCTAssertEqual(official?["sha256"] as? String, SourceDiagnostics.sourceHash)
        XCTAssertEqual(try String(contentsOf: sources.appendingPathComponent("hongguo.js"), encoding: .utf8), BuiltInHongguoJSContent)
        XCTAssertEqual(recorder.sourceRuntimeStatus, "运行 JS 与本包一致")
        XCTAssertTrue(recorder.report.contains(SourceDiagnostics.sourceHash))
        print("THL_SOURCE_IDENTITY staleCacheReplaced=true metadataFresh=true runtimeMatchesBundle=true source=\(SourceDiagnostics.sourceHash)")
    }

    func testOfficialSourceStillLoadsWhenSourceCacheCannotBeWritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("blocked cache directory".utf8).write(to: root.appendingPathComponent("sources"))
        let bridge = NativeBridge(baseDirectory: root, persistentDeviceSession: false)
        let identity = try await bridge.request(action: "jsSource.identity", payload: [:])
        XCTAssertEqual(identity["sha256"] as? String, SourceDiagnostics.sourceHash)
        XCTAssertEqual(identity["runtimeReady"] as? Bool, true)
    }

    func testSourceRuntimeReportDetectsMismatchedOrFailedContext() {
        let recorder = SourceDiagnostics()
        recorder.registerSourceRuntime(context: "播放", script: BuiltInHongguoJSContent, ready: true)
        XCTAssertEqual(recorder.sourceRuntimeStatus, "运行 JS 与本包一致")
        recorder.registerSourceRuntime(context: "下一集", script: "stale", ready: true)
        XCTAssertTrue(recorder.sourceRuntimeStatus.contains("异常"))
        recorder.registerSourceRuntime(context: "下一集", script: BuiltInHongguoJSContent, ready: false)
        XCTAssertTrue(recorder.sourceRuntimeStatus.contains("异常"))
        XCTAssertTrue(recorder.report.contains("加载失败"))
    }

    func testFavoritesAreVisibleAndPersistWithoutMetadataLoss() throws {
        let (defaults, name) = try storage()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LocalStore(defaults: defaults)
        let drama = Drama(id: "test_local_favorite", title: "本地收藏验证", episodes: 80, tags: ["合成数据"])
        let detail = DetailViewModel(drama: drama, store: store)
        detail.toggleFavorite()
        XCTAssertEqual(store.followState(for: drama.id), .wishlist)
        let library = LibraryViewModel(store: store)
        XCTAssertEqual(library.selectedFollowFilter, .none)
        XCTAssertEqual(library.followedList.map(\.id), [drama.id])
        store.setFollowState(drama: Drama(id: drama.id, title: "短剧"), state: .watching)
        let restored = LocalStore(defaults: defaults)
        XCTAssertEqual(restored.followState(for: drama.id), .watching)
        XCTAssertEqual(restored.followedDramas.first?.title, drama.title)
        XCTAssertEqual(restored.followedDramas.first?.episodes, 80)
        restored.setFollowState(drama: drama, state: .none)
        XCTAssertTrue(LocalStore(defaults: defaults).followedDramas.isEmpty)
        print("THL_TV_LOCAL favorites=true persistence=true defaultAll=true metadata=true remove=true")
    }

    func testHistoryRejectsInvalidProgressAndClearsOnlySelectedSource() throws {
        let (defaults, name) = try storage()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LocalStore(defaults: defaults)
        let drama = Drama(id: "test_local_history", title: "本地历史验证", episodes: 80)
        let other = Drama(id: "test_local_other", source: "synthetic", title: "合成隔离记录")
        store.setFollowState(drama: drama, state: .wishlist)
        store.recordWatch(drama: drama, episode: 2, position: 37.5, duration: 120)
        for value in [Double.nan, .infinity, -1] {
            store.recordWatch(drama: drama, episode: 1, position: value, duration: 120)
        }
        store.recordWatch(drama: drama, episode: 1, position: 0, duration: .infinity)
        store.recordWatch(drama: drama, episode: 0, position: 0, duration: 120)
        var restored = LocalStore(defaults: defaults)
        XCTAssertEqual(restored.getWatchEntry(dramaId: drama.id)?.episode, 2)
        XCTAssertEqual(restored.getWatchEntry(dramaId: drama.id)?.position, 37.5)
        store.recordWatch(drama: Drama(id: drama.id, title: "短剧"), episode: 2, position: 150, duration: 120)
        store.recordWatch(drama: other, episode: 1, position: 10, duration: 60)
        restored = LocalStore(defaults: defaults)
        XCTAssertEqual(restored.getWatchEntry(dramaId: drama.id)?.position, 120)
        XCTAssertEqual(restored.getWatchEntry(dramaId: drama.id)?.drama.title, drama.title)
        XCTAssertEqual(restored.history.count, 2)
        restored.clearHistory(for: "HONGGUO")
        let cleared = LocalStore(defaults: defaults)
        XCTAssertEqual(cleared.history.map(\.drama.id), [other.id])
        XCTAssertEqual(cleared.followState(for: drama.id), .wishlist)
        XCTAssertEqual(cleared.followedDramas.count, 1)
        print("THL_TV_LOCAL history=true invalidProgressRejected=true sourceIsolation=true favoritesRetained=true")
    }

    func testDanmakuPreferencePersistsAcrossPlayerInstances() throws {
        let (defaults, name) = try storage()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LocalStore(defaults: defaults)
        let drama = Drama(id: "test_local_danmaku", title: "弹幕偏好验证")
        let first = PlayerViewModel(drama: drama, allEpisodes: [], store: store)
        first.toggleDanmaku()
        XCTAssertFalse(first.danmakuEnabled)
        first.onDisappear()
        let restored = LocalStore(defaults: defaults)
        let second = PlayerViewModel(drama: drama, allEpisodes: [], store: restored)
        defer { second.onDisappear() }
        XCTAssertFalse(second.danmakuEnabled)
        second.toggleDanmaku()
        XCTAssertTrue(LocalStore(defaults: defaults).danmakuEnabled)
        print("THL_TV_LOCAL danmakuPreference=true reload=true")
    }
    func testInactivePlayerRestoresLatestHistoryAfterDetailPlayback() throws {
        let (defaults, name) = try storage()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LocalStore(defaults: defaults)
        let drama = Drama(id: "test_feed_resume_latest", title: "推荐历史恢复")
        let model = PlayerViewModel(drama: drama, allEpisodes: [], initialEpisodeIndex: 1, initialPosition: 10, store: store)
        store.recordWatch(drama: drama, episode: 4, position: 42, duration: 90)
        model.restoreSavedProgress()
        XCTAssertEqual(model.currentEpisodeIndex, 4)
        XCTAssertEqual(model.currentTime, 42)
        XCTAssertEqual(model.duration, 90)
        model.onDisappear()
        let restored = LocalStore(defaults: defaults).getWatchEntry(dramaId: drama.id)
        XCTAssertEqual(restored?.episode, 4)
        XCTAssertEqual(restored?.position, 42)
    }

    func testLiveSourceDiagnosticsContainsRegistrationAndSafeReport() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HONGGUO_LIVE"] == "1")
        XCTAssertEqual(ProcessInfo.processInfo.environment["DISABLE_REMOTE_IMAGES"], "1")
        let store = LocalStore.shared
        let history = store.history
        let favorites = store.followedDramas
        let follows = store.follows
        let recorder = SourceDiagnostics.shared
        recorder.clear()
        await SourceDiagnosticRunner.shared.run()
        XCTAssertTrue(SourceDiagnosticRunner.shared.result.contains("检测完成"))
        let registration = try XCTUnwrap(recorder.entries.first { $0.stage == "游客注册" })
        XCTAssertEqual(registration.host, "log.snssdk.com")
        XCTAssertEqual(registration.status, 200)
        XCTAssertFalse(registration.failed)
        XCTAssertTrue(recorder.entries.contains { $0.stage == "搜索" && $0.status == 200 })
        XCTAssertTrue(recorder.entries.contains { $0.stage == "搜索分页" })
        XCTAssertTrue(recorder.entries.contains { $0.stage == "详情" && $0.status == 200 })
        for value in [recorder.report, recorder.qrText] {
            XCTAssertFalse(value.contains("device_id="))
            XCTAssertFalse(value.contains("x-medusa"))
            XCTAssertFalse(value.contains("device_token"))
            XCTAssertFalse(value.contains("_rticket="))
        }
        XCTAssertLessThanOrEqual(recorder.qrText.utf8.count, 2300)
        XCTAssertEqual(store.history, history)
        XCTAssertEqual(store.followedDramas, favorites)
        XCTAssertEqual(store.follows, follows)
        print("THL_TV_DIAGNOSTICS_CAPTURE registration=true search=true pagination=true detail=true privateDataExcluded=true libraryUnchanged=true")
    }

    func testSourceDiagnosticsCategoryClassificationAndDetailedReport() async throws {
        // 1. 验证各种常见故障的分类精准度
        // DNS 解析错误
        let dnsErr = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: nil)
        let (dnsCat, dnsReason, dnsAdvice) = SourceDiagnostics.classify(error: dnsErr, httpStatus: nil, body: nil, isJS: false)
        XCTAssertEqual(dnsCat, .dnsError)
        XCTAssertTrue(dnsReason.contains("DNS 解析失败"))
        XCTAssertTrue(dnsAdvice.contains("DNS"))

        // 断网未连接
        let offlineErr = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        let (offCat, offReason, offAdvice) = SourceDiagnostics.classify(error: offlineErr, httpStatus: nil, body: nil, isJS: false)
        XCTAssertEqual(offCat, .networkOffline)
        XCTAssertTrue(offReason.contains("网络未连接"))
        XCTAssertTrue(offAdvice.contains("Wi-Fi"))

        // 网络超时
        let timeoutErr = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let (toCat, toReason, toAdvice) = SourceDiagnostics.classify(error: timeoutErr, httpStatus: nil, body: nil, isJS: false)
        XCTAssertEqual(toCat, .networkTimeout)
        XCTAssertTrue(toReason.contains("网络请求超时"))
        XCTAssertTrue(toAdvice.contains("超时") || toAdvice.contains("直连"))

        // TLS 证书错误
        let tlsErr = NSError(domain: NSURLErrorDomain, code: -1202, userInfo: nil)
        let (tlsCat, tlsReason, tlsAdvice) = SourceDiagnostics.classify(error: tlsErr, httpStatus: nil, body: nil, isJS: false)
        XCTAssertEqual(tlsCat, .tlsError)
        XCTAssertTrue(tlsReason.contains("证书错误") || tlsReason.contains("TLS"))
        XCTAssertTrue(tlsAdvice.contains("证书") || tlsAdvice.contains("系统日期"))

        // JS 引擎报错
        let jsErr = NSError(domain: "JavaScriptCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "ReferenceError: Can't find variable: spider"])
        let (jsCat, jsReason, jsAdvice) = SourceDiagnostics.classify(error: jsErr, httpStatus: nil, body: nil, isJS: true)
        XCTAssertEqual(jsCat, .jsError)
        XCTAssertTrue(jsReason.contains("JS 执行报错"))
        XCTAssertTrue(jsAdvice.contains("Spider 脚本") || jsAdvice.contains("JS"))

        // HTTP 403 / 429 业务拒绝
        let (http403Cat, http403Reason, http403Advice) = SourceDiagnostics.classify(error: nil, httpStatus: 403, body: nil, isJS: false)
        XCTAssertEqual(http403Cat, .businessRejected)
        XCTAssertTrue(http403Reason.contains("403"))
        XCTAssertTrue(http403Advice.contains("防封安全间隔") || http403Advice.contains("防盗链"))

        let (http429Cat, http429Reason, _) = SourceDiagnostics.classify(error: nil, httpStatus: 429, body: nil, isJS: false)
        XCTAssertEqual(http429Cat, .businessRejected)
        XCTAssertTrue(http429Reason.contains("429"))

        // 2. 验证详细诊断报告结构
        let recorder = SourceDiagnostics()
        recorder.clear()
        recorder.add(SourceDiagnosticEntry(
            context: "单元测试",
            stage: "DNS探测",
            host: "lf3-shortplay-tos.snssdk.com",
            status: 0,
            elapsedMs: 25,
            category: .dnsError,
            errorDetail: "DNS 解析失败 (-1003)",
            suggestion: "检查网络 DNS 配置"
        ))
        recorder.add(SourceDiagnosticEntry(
            context: "单元测试",
            stage: "JS语法检查",
            status: 0,
            elapsedMs: 12,
            category: .jsError,
            errorDetail: "JS 执行报错: SyntaxError",
            suggestion: "更新 Spider 脚本"
        ))

        recorder.add(SourceDiagnosticEntry(
            context: "单元测试",
            stage: "搜索",
            host: "reading.snssdk.com",
            url: "https://reading.snssdk.com/reading/bookapi/search/tab/v?query=test&tab_type=29",
            method: "GET",
            logId: "20261026210000010000000000000000",
            status: 200,
            businessCode: "",
            errorCode: "SEARCH_REJECTED",
            elapsedMs: 85,
            category: .businessRejected,
            errorDetail: "官方搜索未返回剧集分类",
            suggestion: "当前游客凭据可能已过期，系统已自动重置会话。",
            responseSnippet: "{\"code\":0,\"search_tabs\":[{\"tab_type\":11,\"title\":\"综合\"}]}",
            searchTabsSummary: "分类列表[1]: [11:综合(10条)] (缺少 29:剧集 分类)"
        ))

        let report = recorder.report
        XCTAssertTrue(report.contains("糖葫芦Haw (THLRedLook) 核心技术诊断报告"))
        XCTAssertTrue(report.contains("应用版本:"))
        XCTAssertTrue(report.contains("数据源名称: hongguo"))
        XCTAssertTrue(report.contains("【DNS解析错误】"))
        XCTAssertTrue(report.contains("【JS报错】"))
        XCTAssertTrue(report.contains("排查建议: 检查网络 DNS 配置"))
        XCTAssertTrue(report.contains("排查建议: 更新 Spider 脚本"))
        XCTAssertTrue(report.contains("请求接口: https://reading.snssdk.com/reading/bookapi/search/tab/v"))
        XCTAssertTrue(report.contains("字节 LogID: 20261026210000010000000000000000"))
        XCTAssertTrue(report.contains("搜索分类详情: 分类列表[1]: [11:综合(10条)] (缺少 29:剧集 分类)"))
        XCTAssertTrue(report.contains("响应结构摘要:"))

        // 验证沙盒日志文件自动写入
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let logFile = cacheDir.appendingPathComponent("diagnostics_latest.log")
            for _ in 0..<100 where !FileManager.default.fileExists(atPath: logFile.path) {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path), "诊断报告应自动写入沙盒文件")
        }

        let qr = recorder.qrText
        XCTAssertTrue(qr.contains("DNS解析错误"))
        XCTAssertTrue(qr.contains("JS报错"))
        print("THL_TV_DIAGNOSTICS_CLASSIFICATION_AND_REPORT dns=true offline=true timeout=true tls=true js=true http403=true http429=true report=true qr=true logTrace=true")
    }

    func testHongguoStripVipBadges() throws {
        // 1. 直接构造红果短剧
        let drama = Drama(
            id: "hongguo:789012",
            source: "hongguo",
            title: "全免费短剧测试",
            vip: true,
            tags: ["VIP", "逆袭", "付费短剧", "超前VIP", "都市", "付费"]
        )
        XCTAssertFalse(drama.isVIP, "红果短剧 isVIP 必须始终为 false")
        XCTAssertEqual(drama.vip, false, "红果短剧 vip 必须自动置为 false")
        XCTAssertEqual(drama.tags, ["逆袭", "都市"], "红果短剧 tags 必须过滤掉所有包含 vip 或 付费 的标签")

        // 2. JSON 解码红果短剧
        let jsonStr = """
        {
            "id": "hongguo:123456",
            "source": "hongguo",
            "title": "测试短剧",
            "vip": true,
            "tags": ["VIP专享", "甜宠", "付费短剧", "高甜", "超前付费"]
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Drama.self, from: data)
        XCTAssertFalse(decoded.isVIP)
        XCTAssertEqual(decoded.vip, false)
        XCTAssertEqual(decoded.tags, ["甜宠", "高甜"])

        // 3. merge 保持清洗
        let merged = drama.merge(with: decoded)
        XCTAssertFalse(merged.isVIP)
        XCTAssertEqual(merged.vip, false)
        XCTAssertFalse(merged.tags.contains(where: { $0.lowercased().contains("vip") || $0.contains("付费") }))

        // 4. Episode 红果源分集校验
        let ep = Episode(id: "hongguo:123456_1", title: "第 1 集", number: 1, vip: false)
        XCTAssertFalse(ep.vip)
        print("THL_TV_HONGGUO_NO_VIP_VERIFIED drama.isVIP=false tags_cleaned=true episodes.vip=false")
    }

}

@MainActor
private final class DiscoveryProvider: DramaSourceProviderProtocol {
    typealias Page = (items: [Drama], hasMore: Bool, page: Int)
    var blocked: String?
    var pending: CheckedContinuation<Page, Error>?
    var failNext = false
    var requests: [String] = []
    let categories = ["all", "playlet", "motion_comic", "ai_playlet"].map { CatalogCategory(id: "app:discover:" + $0, name: $0) }

    func loadCategories(source: String) async throws -> [CatalogCategory] { categories }
    func loadCatalog(source: String, category: String, page: Int, query: String, force: Bool) async throws -> Page {
        let key = "\(category)/\(page)"
        requests.append(key)
        if blocked == key {
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        if failNext {
            failNext = false
            throw SourceAPIError.sourceUnavailable("合成分页失败")
        }
        return response(category, page)
    }
    func response(_ category: String, _ page: Int) -> Page {
        ([Drama(id: "\(category)/\(page)", title: category, category: category)], true, page)
    }
    func loadSuggestions(query: String) async throws -> [String] { [] }
    func loadDetail(drama: Drama) async throws -> DramaDetail { throw SourceAPIError.coreUninitialized }
    func loadRankingBoards() async throws -> [RankingBoard] { [] }
    func loadRankings(board: String, page: Int) async throws -> [Drama] { [] }
    func loadRecommendations(category: String) async throws -> [Drama] { [] }
}

extension LocalLibraryTests {
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }

    func testDiscoveryInitialGenreLoadsOnlyRequestedCategory() async throws {
        let (defaults, name) = try storage()
        defer { defaults.removePersistentDomain(forName: name) }
        let provider = DiscoveryProvider()
        let store = LocalStore(defaults: defaults)
        store.currentSourceId = "hongguo"
        let model = HomeViewModel(repository: provider, store: store)
        await model.reloadAll(initialCategory: "app:discover:motion_comic")
        XCTAssertEqual(model.selectedCategory.id, "app:discover:motion_comic")
        XCTAssertEqual(provider.requests, ["app:discover:motion_comic/1"])
        XCTAssertEqual(model.items.map(\.id), ["app:discover:motion_comic/1"])
        print("THL_DISCOVERY_MODEL initialCategory=true requestedGenreOnly=true")
    }

    func testDiscoverySwitchRejectsLatePaginationAndRestartsCursor() async throws {
        let (defaults, name) = try storage()
        defer { defaults.removePersistentDomain(forName: name) }
        let provider = DiscoveryProvider()
        let store = LocalStore(defaults: defaults)
        store.currentSourceId = "hongguo"
        let model = HomeViewModel(repository: provider, store: store)
        await model.reloadAll()
        XCTAssertEqual(model.categories.count, 4)
        XCTAssertEqual(model.selectedCategory.id, "app:discover:all")
        provider.blocked = "app:discover:all/2"
        let more = Task { await model.loadNextPage() }
        await eventually { provider.pending != nil }
        model.selectCategory(provider.categories[1], immediate: true)
        await eventually { model.items.first?.id == "app:discover:playlet/1" }
        provider.pending?.resume(returning: provider.response("app:discover:all", 2))
        provider.pending = nil
        await more.value
        XCTAssertEqual(model.items.map(\.id), ["app:discover:playlet/1"])
        XCTAssertFalse(model.isLoadingMore)
        provider.blocked = nil
        model.selectCategory(provider.categories[0], immediate: true)
        await eventually { model.items.first?.id == "app:discover:all/1" }
        await model.loadNextPage()
        XCTAssertEqual(model.items.map(\.id), ["app:discover:all/1", "app:discover:all/2"])
        print("THL_DISCOVERY_MODEL stalePaginationIgnored=true cursorRestarted=true")
    }

    func testDiscoveryRapidSwitchAndFailedPageRetry() async throws {
        let (defaults, name) = try storage()
        defer { defaults.removePersistentDomain(forName: name) }
        let provider = DiscoveryProvider()
        let store = LocalStore(defaults: defaults)
        store.currentSourceId = "hongguo"
        let model = HomeViewModel(repository: provider, store: store)
        await model.reloadAll()
        provider.blocked = "app:discover:playlet/1"
        model.selectCategory(provider.categories[1], immediate: true)
        await eventually { provider.pending != nil }
        model.selectCategory(provider.categories[2], immediate: true)
        await eventually { model.items.first?.id == "app:discover:motion_comic/1" }
        provider.pending?.resume(returning: provider.response("app:discover:playlet", 1))
        provider.pending = nil
        await Task.yield()
        XCTAssertEqual(model.items.map(\.id), ["app:discover:motion_comic/1"])
        XCTAssertFalse(model.isLoading)
        provider.failNext = true
        await model.loadNextPage()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.items.count, 1)
        let count = provider.requests.count
        await model.loadNextPage()
        XCTAssertEqual(provider.requests.count, count)
        await model.retry()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.items.map(\.id), ["app:discover:motion_comic/1", "app:discover:motion_comic/2"])
        XCTAssertEqual(provider.requests.suffix(2), ["app:discover:motion_comic/2", "app:discover:motion_comic/2"])
        print("THL_DISCOVERY_MODEL rapidSwitch=true staleFirstPageIgnored=true failedPageRetry=true")
    }
}

@MainActor
final class VideoFeedTests: XCTestCase {
    private func item(_ id: String) -> VideoFeedItem {
        VideoFeedItem(drama: Drama(id: id, title: id), episode: 1, position: 0)
    }

    func testFeedRetainsServerOrderDeduplicatesAndLoadsNext() async {
        var requested: [Int] = []
        let model = VideoFeedViewModel(preloadEnabled: false) { page, _ in
            requested.append(page)
            return VideoFeedPage(items: page == 1 ? [self.item("a"), self.item("b"), self.item("c"), self.item("d")] : [self.item("d"), self.item("e")], page: page, hasMore: page == 1)
        }
        await model.start()
        XCTAssertEqual(model.current?.id, "a")
        await model.next()
        await model.loadMore()
        XCTAssertEqual(model.items.map(\.id), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(requested, [1, 2])
        for _ in 0..<6 { await model.next() }
        XCTAssertEqual(model.current?.id, "e")
        XCTAssertFalse(model.canGoNext)
        model.previous()
        XCTAssertEqual(model.current?.id, "d")
    }

    func testRetryReusesFailedPageAndRefreshChangesScope() async {
        var scopes: [String] = []
        var fail = true
        let model = VideoFeedViewModel(preloadEnabled: false) { page, session in
            scopes.append(session)
            if fail { throw NSError(domain: "fixture", code: 1) }
            return VideoFeedPage(items: [self.item("exact:7688558312157088793")], page: page, hasMore: false)
        }
        await model.start()
        XCTAssertNotNil(model.errorMessage)
        fail = false
        await model.retry()
        XCTAssertEqual(model.page, 1)
        XCTAssertEqual(model.current?.id, "exact:7688558312157088793")
        XCTAssertEqual(scopes[0], scopes[1])
        await model.refresh()
        XCTAssertNotEqual(scopes[1], scopes[2])
    }

    func testCursorExpiryRequiresFreshSessionAndRejectsLateResponse() async {
        var fail = true
        let model = VideoFeedViewModel(preloadEnabled: false) { page, _ in
            if fail { throw NSError(domain: "fixture", code: 1, userInfo: ["sourceErrorCode": "CURSOR_EXPIRED"]) }
            return VideoFeedPage(items: [self.item("fresh")], page: page, hasMore: false)
        }
        await model.start()
        XCTAssertTrue(model.needsRefresh)
        fail = false
        await model.retry()
        XCTAssertFalse(model.needsRefresh)
        XCTAssertEqual(model.current?.id, "fresh")
        var attempt = 0
        let racing = VideoFeedViewModel(preloadEnabled: false) { page, _ in
            attempt += 1
            let captured = attempt
            if captured == 1 { try? await Task.sleep(nanoseconds: 150_000_000) }
            return VideoFeedPage(items: [self.item(captured == 1 ? "stale" : "new")], page: page, hasMore: false)
        }
        let old = Task { await racing.start() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await racing.refresh()
        await old.value
        XCTAssertEqual(racing.items.map(\.id), ["new"])
    }
    func testFailedPaginationKeepsCurrentAndCanAdvanceAfterRetry() async {
        var pageTwoAttempts = 0
        let model = VideoFeedViewModel(preloadEnabled: false) { page, _ in
            if page == 1 { return VideoFeedPage(items: [self.item("a"), self.item("b"), self.item("c"), self.item("d")], page: 1, hasMore: true) }
            pageTwoAttempts += 1
            if pageTwoAttempts == 1 { throw NSError(domain: "network-fixture", code: -1001) }
            return VideoFeedPage(items: [self.item("e")], page: page, hasMore: false)
        }
        await model.start()
        await model.loadMore()
        XCTAssertEqual(model.current?.id, "a")
        XCTAssertNotNil(model.errorMessage)
        for _ in 0..<4 { await model.next() }
        XCTAssertEqual(model.current?.id, "e")
        XCTAssertEqual(pageTwoAttempts, 2)
    }

    func testEmptyPagesHaveBoundedRetryAndConcurrentNextDoesNotSkip() async {
        var requests = 0
        let empty = VideoFeedViewModel(preloadEnabled: false) { page, _ in
            requests += 1
            return VideoFeedPage(items: [], page: page, hasMore: true)
        }
        await empty.start()
        XCTAssertEqual(requests, 3)
        XCTAssertNotNil(empty.errorMessage)
        let model = VideoFeedViewModel(preloadEnabled: false) { page, _ in
            if page == 1 { return VideoFeedPage(items: [self.item("a")], page: 1, hasMore: true) }
            try? await Task.sleep(nanoseconds: 100_000_000)
            return VideoFeedPage(items: [self.item("b"), self.item("c")], page: page, hasMore: false)
        }
        await model.start()
        async let first: Void = model.next()
        async let second: Void = model.next()
        _ = await (first, second)
        XCTAssertEqual(model.current?.id, "b")
    }

    func testReenteringFeedKeepsCurrentDramaAndSession() async {
        var requests = 0
        let model = VideoFeedViewModel(preloadEnabled: false) { page, _ in
            requests += 1
            return VideoFeedPage(items: (1...10).map { self.item("drama-\($0)") }, page: page, hasMore: false)
        }
        await model.start()
        await model.next()
        await model.next()
        XCTAssertEqual(model.current?.id, "drama-3")
        let ids = model.items.map(\.id)
        await model.start()
        XCTAssertEqual(model.current?.id, "drama-3")
        XCTAssertEqual(model.items.map(\.id), ids)
        XCTAssertEqual(requests, 1)
    }

    func testRankingsSelectBoardSmoothTransitionDoesNotClearItemsInstantly() async {
        let viewModel = RankingsViewModel()
        let board1 = RankingBoard(id: "board_1", name: "热播榜", description: "热播短剧")
        let board2 = RankingBoard(id: "board_2", name: "好评榜", description: "好评短剧")
        viewModel.boards = [board1, board2]
        viewModel.selectedBoard = board1
        let drama1 = Drama(id: "drama_1", title: "测试短剧1")
        viewModel.items = [drama1]

        // 切换到 board2 时，旧数据 items 不应瞬间被粗暴清空成 []
        viewModel.selectBoard(board2)
        XCTAssertEqual(viewModel.selectedBoard?.id, "board2".isEmpty ? "" : "board_2")
        XCTAssertFalse(viewModel.items.isEmpty, "切换榜单时必须保留旧 items 进行平滑过渡，杜绝视图瞬时坍塌导致焦点丢失")
        XCTAssertEqual(viewModel.items.first?.id, "drama_1")
    }

}
