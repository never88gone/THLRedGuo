import Foundation
import JavaScriptCore

/// 纯 Swift 原生 CatPawOpen 协议桥接引擎
/// 基于系统级 JavaScriptCore 运行时与 URLSession 端侧闭环执行 Spider 数据源解析。
public actor NativeBridge {
    public static let shared = NativeBridge()

    private var isInitialized = false
    private let httpSession: URLSession
    private let diagnostics: SourceDiagnostics
    private let diagnosticContext: String
    private let persistentDeviceSession: Bool
    private let deviceDefaults: UserDefaults
    private let accountSnapshot: @Sendable () -> (record: HongguoAccountRecord?, revision: UInt64)
    private let httpTrace = HttpTraceHolder()
    private var successfulPlaybackResolves = 0
    private var lastSuccessfulPlaybackAt: TimeInterval?
    private let timeProvider: @Sendable () -> TimeInterval
    private let playbackProfileRevision: @Sendable () -> UInt64
    private var loadedPlaybackProfileRevision: UInt64?

    // 功能子系统协调服务组件（面向对象组合拆分，杜绝扩展）
    private let sourceRegistry: JSSourceRegistry
    private let polyfillService: JSPolyfillService
    private let dramaParser: JSDramaParserService

    // JS 运行时上下文缓存
    private var jsContexts: [String: JSContext] = [:]
    private var accountRevision: UInt64 = 0
    private let executionQueue = DispatchQueue(label: "com.never88gone.redlook.bridge.worker", qos: .userInitiated)

    public func applyLocalPlaybackProfileChange() {
        jsContexts.removeValue(forKey: "hongguo")
        successfulPlaybackResolves = 0
        lastSuccessfulPlaybackAt = nil
    }

    init(
        baseDirectory: URL? = nil,
        httpSession: URLSession? = nil,
        diagnostics: SourceDiagnostics = .shared,
        diagnosticContext: String = "日常使用",
        persistentDeviceSession: Bool = true,
        deviceDefaults: UserDefaults = .standard,
        timeProvider: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
        playbackProfileLoader: @escaping @Sendable () throws -> HongguoApkProfile? = { try HongguoPlaybackProfileVault.load() },
        playbackProfileRevision: @escaping @Sendable () -> UInt64 = { HongguoPlaybackProfileVault.revision },
        accountSnapshot: @escaping @Sendable () -> (record: HongguoAccountRecord?, revision: UInt64) = { HongguoAccountVault.shared.snapshot }
    ) {
        if let httpSession {
            self.httpSession = httpSession
        } else {
            let config = URLSessionConfiguration.default
            config.httpMaximumConnectionsPerHost = 10
            config.timeoutIntervalForRequest = 10.0
            config.timeoutIntervalForResource = 15.0
            config.requestCachePolicy = .useProtocolCachePolicy
            config.httpShouldUsePipelining = true
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
            self.httpSession = URLSession(configuration: config, delegate: HongguoBusinessRedirectDelegate(), delegateQueue: nil)
        }
        self.diagnostics = diagnostics
        self.diagnosticContext = diagnosticContext
        self.persistentDeviceSession = persistentDeviceSession
        self.deviceDefaults = deviceDefaults
        self.accountSnapshot = accountSnapshot
        self.timeProvider = timeProvider
        self.playbackProfileRevision = playbackProfileRevision

        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let baseDir = baseDirectory ?? cachesDir.appendingPathComponent("THLRedLook_Data")
        self.sourceRegistry = JSSourceRegistry(sourcesDirURL: baseDir.appendingPathComponent("sources"))
        self.polyfillService = JSPolyfillService(httpSession: self.httpSession, diagnostics: diagnostics, diagnosticContext: diagnosticContext, persistentDeviceSession: persistentDeviceSession, deviceDefaults: deviceDefaults, timeProvider: timeProvider, playbackProfileLoader: playbackProfileLoader, accountSnapshot: accountSnapshot)
        self.dramaParser = JSDramaParserService(diagnostics: diagnostics, diagnosticContext: diagnosticContext, timeProvider: timeProvider, deviceDefaults: deviceDefaults, persistentDeviceSession: persistentDeviceSession)
    }

    /// 保证核心正规初始化严格就绪
    public func ensureInitialized() async throws {
        if isInitialized { return }
        sourceRegistry.ensureInitialized()
        isInitialized = true
        NSLog("[Source] app=%@ %@ %@", SourceDiagnostics.version, SourceDiagnostics.sourceRevision, SourceDiagnostics.sourceBundleStatus)
        NSLog("🎬 [NativeBridge] CatPawOpen Swift 原生核心初始化成功，已装载 %ld 个插件，当前激活源: '%@'", sourceRegistry.installedSources.count, sourceRegistry.activeSourceId)
    }

    /// 获取或构建指定数据源的 CatPawOpen JS 运行时上下文
    public func accountRequest(_ action: String, payload: [String: String] = [:]) async throws -> [String: Any] {
        sourceRegistry.setScript(sourceId: "__official_account", script: BuiltInHongguoJSContent)
        guard let context = getOrCreateContext(sourceId: "__official_account") else { throw HongguoAccountError.invalid }
        let expression = try dramaParser.spiderExpression("accountRequest", [action, payload])
        guard let response = await evalAsync(context: context, scriptExpr: expression) else { throw HongguoAccountError.invalid }
        guard response["ok"] as? Bool == true, let result = response["data"] as? [String: Any] else {
            let detail = response["error"] as? String ?? ""
            let code = detail.contains("buildAccountRequest") ? "ACCOUNT_BUILDER_UNAVAILABLE" :
                detail.contains("__hongguoLocalSign") ? "ACCOUNT_SIGNER_UNAVAILABLE" :
                detail.contains("LOCAL_PROFILE_REQUIRED") ? "LOCAL_PROFILE_REQUIRED" :
                SourceDiagnostics.safeCode(response["code"])
            throw HongguoAccountError.preparation(code.isEmpty ? "JS_EXECUTION" : code)
        }
        return result
    }

    public func accountParse(_ action: String, body: String) throws -> [String: Any] {
        sourceRegistry.setScript(sourceId: "__official_account", script: BuiltInHongguoJSContent)
        guard let context = getOrCreateContext(sourceId: "__official_account") else { throw HongguoAccountError.invalid }
        let expression = try dramaParser.spiderExpression("accountParse", [action, body])
        context.exception = nil
        let result = context.evaluateScript(expression)
        if context.exception?.toString()?.contains("ACCOUNT_CHALLENGE_REQUIRED") == true || context.exception?.toString()?.contains("ACCOUNT_SECONDARY_VERIFICATION_REQUIRED") == true { throw HongguoAccountError.challenge }
        if let message = context.exception?.toString(), let range = message.range(of: "ACCOUNT_BUSINESS_-?[0-9]{1,9}", options: .regularExpression),
           let code = Int(message[range].dropFirst("ACCOUNT_BUSINESS_".count)) {
            if action == "creatorFollow" && code == 103012 { throw HongguoAccountError.followSecurity }
            throw HongguoAccountError.business(code)
        }
        guard let result, context.exception == nil,
              let data = result.toDictionary() as? [String: Any] else {
            throw ["socialDetail", "creatorList", "likeUpdate", "creatorFollow"].contains(action) ? HongguoAccountError.interactionInvalid : HongguoAccountError.invalid
        }
        if data["verification"] != nil { throw HongguoAccountError.challenge }
        return data
    }

    private func getOrCreateContext(sourceId: String) -> JSContext? {
        let revision = accountSnapshot().revision
        if revision != accountRevision { jsContexts.removeAll(); accountRevision = revision }

        if sourceId == "hongguo", jsContexts[sourceId]?.evaluateScript("globalThis.__hongguoHasBuiltInSigning === true")?.toBool() != true {
            let profileRev = playbackProfileRevision()
            if loadedPlaybackProfileRevision != profileRev {
                applyLocalPlaybackProfileChange()
                loadedPlaybackProfileRevision = profileRev
            }
        }
        if let existing = jsContexts[sourceId] {
            if sourceId == "hongguo", polyfillService.localPlaybackProfileUnavailable,
               sourceRegistry.getScript(sourceId: sourceId) == BuiltInHongguoJSContent {
                polyfillService.refreshSigningCache(existing)
            }
            if polyfillService.synchronizeGuestSession(existing, sourceId: sourceId, httpTrace: httpTrace) {
                successfulPlaybackResolves = 0
                lastSuccessfulPlaybackAt = nil
            }
            return existing
        }

        guard let script = sourceRegistry.getScript(sourceId: sourceId) else { return nil }

        if sourceId == "hongguo" {
            successfulPlaybackResolves = 0
            lastSuccessfulPlaybackAt = nil
        }
        guard let context = JSContext() else { return nil }

        polyfillService.setupContext(context: context, sourceId: sourceId, script: script, httpTrace: httpTrace)
        context.evaluateScript(script)

        if sourceId == "hongguo", script == BuiltInHongguoJSContent, context.exception == nil {
            polyfillService.refreshSigningCache(context)
        }
        if sourceId == "hongguo" {
            let ready = context.exception == nil && context.evaluateScript("typeof spider !== 'undefined' && typeof spider.play === 'function'")?.toBool() == true
            diagnostics.registerSourceRuntime(context: diagnosticContext, script: script, ready: ready,
                                              importedVersion: script != BuiltInHongguoJSContent ? sourceRegistry.installedSources[sourceId]?["version"] as? String : nil)
        }
        context.evaluateScript("if (typeof spider !== 'undefined' && typeof spider.init === 'function') { spider.init({}); }")

        jsContexts[sourceId] = context
        return context
    }

    /// 在 JS 运行时中异步评估 Promise 并等待结果
    func evalAsync(context: JSContext, scriptExpr: String) async -> [String: Any]? {
        let expectedAccountRevision = accountSnapshot().revision
        let doneKey = "__done_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let snapshotGetter = self.accountSnapshot

        return await withCheckedContinuation { continuation in
            let isResumed = NSLock()
            var resumed = false
            func safeResume(_ value: [String: Any]?) {
                isResumed.lock()
                defer { isResumed.unlock() }
                guard !resumed else { return }
                resumed = true
                context.setObject(nil, forKeyedSubscript: doneKey as NSString)
                if expectedAccountRevision != snapshotGetter().revision {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: value)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 15.0) {
                safeResume(["ok": false, "error": "JS 执行无响应或超时", "code": "TIMEOUT"])
            }

            executionQueue.async {
                let onDone: @convention(block) (String) -> Void = { jsonStr in
                    var resultData: [String: Any]? = nil
                    if let data = jsonStr.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        resultData = obj
                    }
                    safeResume(resultData)
                }
                context.setObject(onDone, forKeyedSubscript: doneKey as NSString)

                let wrapper = """
                globalThis.__hongguoCancelled = false;
                (async function() {
                    try {
                        var res = await (\(scriptExpr));
                        \(doneKey)(JSON.stringify({ ok: true, data: res }));
                    } catch (err) {
                        var errMsg = err ? (err.message || String(err)) : "未知错误";
                        var errStack = err && err.stack ? String(err.stack) : "";
                        var errCat = err && err.category ? String(err.category) : "js_error";
                        var errCode = err && err.code ? String(err.code) : "JS_EXECUTION";
                        \(doneKey)(JSON.stringify({
                            ok: false,
                            error: errMsg,
                            stack: errStack,
                            category: errCat,
                            code: errCode
                        }));
                    } finally {
                        globalThis.__hongguoCancelled = false;
                    }
                })();
                """
                context.evaluateScript(wrapper)
            }
        }
    }

    /// 处理所有业务操作 Action 请求
    public func request(action: String, payload: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        if action != "initialize" {
            try await ensureInitialized()
        }

        switch action {
        case "initialize":
            try await ensureInitialized()
            return ["ok": true, "data": ["version": "1.0.0", "standalone": true, "allSources": true]]

        case "jsSource.identity":
            let script = sourceRegistry.getScript(sourceId: "hongguo") ?? ""
            let ready = getOrCreateContext(sourceId: "hongguo") != nil
            return [
                "id": "hongguo", "sha256": SourceDiagnostics.fingerprint(script),
                "bundleSha256": SourceDiagnostics.sourceHash, "runtimeReady": ready,
                "sourceCommit": sourceRegistry.installedSources["hongguo"]?["sourceCommit"] as? String ?? "",
                "version": sourceRegistry.installedSources["hongguo"]?["version"] as? String ?? "",
                "origin": script == BuiltInHongguoJSContent ? "bundled" : "imported"
            ]

        case "jsSource.list":
            return ["items": Array(sourceRegistry.installedSources.values), "active": sourceRegistry.activeSourceId]

        case "jsSource.setActive":
            let source = payload["source"] as? String ?? ""
            let ok = sourceRegistry.setActiveSourceId(source)
            return ["ok": ok, "active": sourceRegistry.activeSourceId]

        case "jsSource.getActive":
            return ["active": sourceRegistry.activeSourceId, "meta": sourceRegistry.installedSources[sourceRegistry.activeSourceId] ?? [:]]

        case "jsSource.saveAndLoad":
            let script = payload["script"] as? String ?? ""
            let fileName = payload["fileName"] as? String ?? "custom.js"
            let autoSelect = (payload["autoSelect"] as? Bool) ?? true
            let active = try sourceRegistry.saveAndLoad(script: script, fileName: fileName, autoSelect: autoSelect)
            return ["ok": true, "active": active]

        case "jsSource.scan":
            sourceRegistry.scanSourcesDirectory()
            return ["ok": true, "count": sourceRegistry.installedSources.count]

        case "jsSource.remove":
            let sourceId = payload["source"] as? String ?? ""
            let result = sourceRegistry.removeSource(sourceId: sourceId)
            jsContexts.removeValue(forKey: sourceId)
            return ["ok": true, "removed": result.removed, "active": result.active]

        case "jsSource.clearAll":
            jsContexts.removeAll()
            let active = sourceRegistry.clearAll()
            return ["ok": true, "active": active]

        case "jsSource.resetOfficial":
            deviceDefaults.set("", forKey: "thl_tv_hongguo_device_session")
            httpSession.configuration.urlCache?.removeAllCachedResponses()
            URLCache.shared.removeAllCachedResponses()
            jsContexts.removeAll()
            let active = sourceRegistry.resetOfficial()
            return ["ok": true, "active": active]

        case "categories":
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? sourceRegistry.activeSourceId
            guard !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                return ["items": [["id": "", "name": "全部"]]]
            }
            return try await dramaParser.parseCategories(ctx: ctx, targetSrc: targetSrc) { [weak self] c, expr in
                guard let self else { return nil }
                return await self.evalAsync(context: c, scriptExpr: expr)
            }

        case "catalog":
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? sourceRegistry.activeSourceId
            guard !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                return ["items": [], "hasMore": false, "page": 1]
            }
            return try await dramaParser.parseCatalog(ctx: ctx, targetSrc: targetSrc, payload: payload, httpTrace: httpTrace) { [weak self] c, expr in
                guard let self else { return nil }
                return await self.evalAsync(context: c, scriptExpr: expr)
            }

        case "search":
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? sourceRegistry.activeSourceId
            let query = payload["query"] as? String ?? ""
            guard !targetSrc.isEmpty, !query.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                return ["items": []]
            }
            let scriptExpr = try dramaParser.spiderExpression("search", [query, false, 1])
            let res = await evalAsync(context: ctx, scriptExpr: scriptExpr)
            var dramas: [[String: Any]] = []
            let list = (res?["data"] as? [String: Any])?["list"] as? [[String: Any]] ?? (res?["data"] as? [[String: Any]]) ?? []
            for vod in list { dramas.append(dramaParser.mapVodToDrama(vod: vod, sourceId: targetSrc)) }
            return ["items": dramas]

        case "detail":
            guard let dramaDict = payload["drama"] as? [String: Any],
                  let dramaId = dramaDict["id"] as? String, !dramaId.isEmpty else {
                throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "剧集信息无效"])
            }
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (dramaDict["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? sourceRegistry.activeSourceId
            guard !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "数据源未就绪"])
            }
            return try await dramaParser.parseDetail(ctx: ctx, targetSrc: targetSrc, dramaDict: dramaDict, dramaId: dramaId) { [weak self] c, expr in
                guard let self else { return nil }
                return await self.evalAsync(context: c, scriptExpr: expr)
            }

        case "resolve":
            let dramaDict = payload["drama"] as? [String: Any] ?? [:]
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (dramaDict["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? sourceRegistry.activeSourceId
            let epIndex = payload["index"] as? Int ?? 1
            let dramaId = dramaDict["id"] as? String ?? "1"
            guard !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                throw dramaParser.playbackFailure(code: "SOURCE_UNAVAILABLE", message: "播放数据源尚未就绪", episode: epIndex, httpTrace: httpTrace, successfulPlaybackResolves: successfulPlaybackResolves, lastSuccessfulPlaybackAt: lastSuccessfulPlaybackAt)
            }
            let chapterDict = payload["chapter"] as? [String: Any]
            let rawUrl = (chapterDict?["url"] as? String) ?? "\(dramaId)/\(epIndex)"
            let flags: [[String: Any]] = [[
                "quality": payload["quality"] as? Int ?? 0,
                "seriesId": dramaDict["sourceId"] as? String ?? dramaId.components(separatedBy: ":").last ?? "",
                "avoidUrl": payload["avoidUrl"] as? String ?? ""
            ]]
            let started = timeProvider()
            let scriptExpr = try dramaParser.spiderExpression("play", ["", rawUrl, flags])
            let res = await evalAsync(context: ctx, scriptExpr: scriptExpr)
            try Task.checkCancellation()
            let data = res?["data"] as? [String: Any]
            guard res?["ok"] as? Bool == true, let data, let url = data["url"] as? String, !url.isEmpty, !url.contains("example.com") else {
                let code = SourceDiagnostics.safeCode(res?["code"] ?? data?["error"])
                if code == "CANCELLED" { throw CancellationError() }
                if let retried = try await tryGuestSyncRetry(targetSrc: targetSrc, code: code, payload: payload, started: started) {
                    return retried
                }
                throw dramaParser.playbackFailure(code: code.isEmpty ? "NO_STREAM_URL" : code, message: res?["error"] as? String ?? "", episode: epIndex, httpTrace: httpTrace, successfulPlaybackResolves: successfulPlaybackResolves, lastSuccessfulPlaybackAt: lastSuccessfulPlaybackAt)
            }
            successfulPlaybackResolves += 1
            lastSuccessfulPlaybackAt = timeProvider()
            let targetHeaders = (data["header"] as? [String: String]) ?? (data["headers"] as? [String: String]) ?? [:]
            let contentKey = data["decryptionKey"] as? String ?? ""
            var detectedQuality = data["quality"] as? Int ?? 0
            if url.contains("4k") || url.contains("2160p") { detectedQuality = 2160 }
            else if url.contains("1080p") { detectedQuality = 1080 }
            else if url.contains("720p") { detectedQuality = 720 }
            else if url.contains("480p") { detectedQuality = 480 }

            let reportedQualities = data["qualities"] as? [Int] ?? []
            return [
                "url": url,
                "headers": targetHeaders,
                "decryptionKey": contentKey,
                "expiresAt": (data["expiresAt"] as? NSNumber)?.int64Value ?? 0,
                "danmakuId": data["danmakuId"] as? String ?? "",
                "mediaBytes": (data["mediaBytes"] as? NSNumber)?.int64Value ?? 0,
                "quality": detectedQuality,
                "qualities": reportedQualities.isEmpty ? (detectedQuality > 0 ? [detectedQuality] : []) : reportedQualities,
                "session": "\(Date().timeIntervalSince1970)"
            ]

        case "danmaku":
            let id = payload["episodeId"] as? String ?? ""
            guard id.hasPrefix("hongguo:"), let context = getOrCreateContext(sourceId: "hongguo") else {
                throw NSError(domain: "THLRedLook.Danmaku", code: -1, userInfo: [NSLocalizedDescriptionKey: "本集暂不支持弹幕"])
            }
            let expression = try dramaParser.spiderExpression("danmaku", [id, payload["startMs"] as? Int64 ?? 0, payload["durationMs"] as? Int64 ?? 0])
            guard let response = await evalAsync(context: context, scriptExpr: expression), response["ok"] as? Bool == true,
                  let result = response["data"] as? [String: Any], result["items"] is [[String: Any]] else {
                throw NSError(domain: "THLRedLook.Danmaku", code: -2, userInfo: [NSLocalizedDescriptionKey: "官方弹幕暂不可用"])
            }
            return result

        case "rankingBoards", "rankings", "recommendations", "suggestions", "seriesSeasons", "feed":
            let source = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (sourceRegistry.activeSourceId.isEmpty ? "hongguo" : sourceRegistry.activeSourceId)
            guard let context = getOrCreateContext(sourceId: source) else {
                throw NSError(domain: "THLRedLook.Source", code: -1, userInfo: [NSLocalizedDescriptionKey: "数据源不可用"])
            }
            let page = max(1, payload["page"] as? Int ?? 1)
            let arguments: [Any]
            switch action {
            case "rankings": arguments = [payload["board"] as? String ?? "", page]
            case "recommendations": arguments = [payload["category"] as? String ?? "real-drama", page]
            case "suggestions": arguments = [payload["query"] as? String ?? ""]
            case "seriesSeasons": arguments = [payload["id"] as? String ?? ""]
            case "feed": arguments = [page, payload["session"] as? String ?? ""]
            default: arguments = []
            }
            let expression = try dramaParser.spiderExpression(action, arguments)
            let evaluated = await evalAsync(context: context, scriptExpr: expression)
            guard evaluated?["ok"] as? Bool == true, let result = evaluated?["data"] as? [String: Any] else {
                let message = evaluated?["error"] as? String ?? "官方列表响应超时，请重试"
                let code = SourceDiagnostics.safeCode(evaluated?["code"])
                diagnostics.add(SourceDiagnosticEntry(context: diagnosticContext, stage: action == "feed" ? "首页推荐执行" : action == "suggestions" ? "搜索建议执行" : "发现列表执行", errorCode: code.isEmpty ? "JS_EXECUTION" : code))
                throw NSError(domain: "THLRedLook.Source", code: -2, userInfo: [NSLocalizedDescriptionKey: message, "sourceErrorCode": code])
            }
            if action == "rankingBoards" || action == "suggestions" { return result }
            let rows = result["list"] as? [[String: Any]] ?? []
            let items: [[String: Any]] = rows.map { vod in
                let drama = dramaParser.mapVodToDrama(vod: vod, sourceId: source)
                if action == "rankings" {
                    return ["rank": vod["vod_rank"] as? Int ?? 0, "drama": drama, "metric": vod["vod_metric"] as? String ?? ""]
                }
                if action == "seriesSeasons" {
                    return ["drama": drama, "season": vod["season"] as? Int ?? 0,
                            "playable": vod["playable"] as? Bool ?? false, "status": vod["status"] as? String ?? ""]
                }
                if action == "feed" {
                    return ["drama": drama, "episode": max(1, vod["vod_start_episode"] as? Int ?? 1),
                            "position": max(0, vod["vod_start_position"] as? Double ?? 0)]
                }
                return drama
            }
            return [
                "items": items, "page": result["page"] as? Int ?? page,
                "hasMore": result["hasMore"] as? Bool ?? false,
                "updatedText": result["updatedText"] as? String ?? ""
            ]

        default:
            return ["ok": true]
        }
    }

    private func tryGuestSyncRetry(targetSrc: String, code: String, payload: [String: Any], started: TimeInterval) async throws -> [String: Any]? {
        guard targetSrc == "hongguo", persistentDeviceSession, code == "EMPTY_RESPONSE",
              payload["guestSynchronizationAttempted"] as? Bool != true, !httpTrace.guestSnapshot.json.isEmpty else { return nil }
        let startDate = Date(timeIntervalSince1970: started)
        let failures = diagnostics.entries.filter { $0.context == diagnosticContext && $0.stage == "播放解析" && $0.at >= startDate }
        guard failures.count == 4 else { return nil }
        let allEmpty = failures.allSatisfy { $0.status == 200 && $0.bodyBytes == 0 && $0.errorCode == "EMPTY_RESPONSE" }
        guard allEmpty, let latest = deviceDefaults.string(forKey: "thl_tv_hongguo_device_session") else { return nil }
        guard SavedGuestSession.valid(latest), latest != httpTrace.guestSnapshot.json else { return nil }
        let latestCreated = deviceDefaults.double(forKey: "thl_tv_hongguo_guest_created_at")
        let guestCreated = httpTrace.guestSnapshot.createdAt
        guard latestCreated <= 0 || guestCreated <= 0 || latestCreated >= guestCreated else { return nil }
        diagnostics.add(SourceDiagnosticEntry(context: diagnosticContext, stage: "游客会话同步", sessionStatus: "已载入其他请求更新的游客会话"))
        var retry = payload
        retry["guestSynchronizationAttempted"] = true
        return try await request(action: "resolve", payload: retry)
    }
}
