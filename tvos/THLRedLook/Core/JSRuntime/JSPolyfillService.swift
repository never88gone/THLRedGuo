import Foundation
import JavaScriptCore

final class JSPolyfillService {
    private let httpSession: URLSession
    private let diagnostics: SourceDiagnostics
    private let diagnosticContext: String
    private let persistentDeviceSession: Bool
    private let deviceDefaults: UserDefaults
    private let timeProvider: @Sendable () -> TimeInterval
    private let accountSnapshot: @Sendable () -> (record: HongguoAccountRecord?, revision: UInt64)
    private let playbackProfileLoader: @Sendable () throws -> HongguoApkProfile?
    private(set) var localPlaybackProfileUnavailable = false

    init(
        httpSession: URLSession,
        diagnostics: SourceDiagnostics = .shared,
        diagnosticContext: String = "日常使用",
        persistentDeviceSession: Bool = true,
        deviceDefaults: UserDefaults = .standard,
        timeProvider: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
        playbackProfileLoader: @escaping @Sendable () throws -> HongguoApkProfile? = { try HongguoPlaybackProfileVault.load() },
        accountSnapshot: @escaping @Sendable () -> (record: HongguoAccountRecord?, revision: UInt64) = { HongguoAccountVault.shared.snapshot }
    ) {
        self.httpSession = httpSession
        self.diagnostics = diagnostics
        self.diagnosticContext = diagnosticContext
        self.persistentDeviceSession = persistentDeviceSession
        self.deviceDefaults = deviceDefaults
        self.timeProvider = timeProvider
        self.playbackProfileLoader = playbackProfileLoader
        self.accountSnapshot = accountSnapshot
    }

    func setupContext(
        context: JSContext,
        sourceId: String,
        script: String,
        httpTrace: HttpTraceHolder
    ) {
        let entropy = (0..<64).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        context.evaluateScript("globalThis.__hongguoEntropy = '\(entropy)';")

        // 1. 注入控制台日志
        let logBlock: @convention(block) (String) -> Void = { msg in
            NSLog("🎬 [CatPawOpen JS:%@] %@", sourceId, msg)
        }
        context.setObject(logBlock, forKeyedSubscript: "__console_log" as NSString)

        // 1.5 注入设备认证持久化
        httpTrace.recordGuest(json: "", createdAt: 0)
        let currentTime = timeProvider
        let persistentSession = persistentDeviceSession
        let defaults = deviceDefaults
        let saveDeviceBlock: @convention(block) (String) -> Void = { json in
            guard persistentSession, !json.isEmpty else { return }
            defaults.set(json, forKey: "thl_tv_hongguo_device_session")
            let created = currentTime()
            defaults.set(created, forKey: "thl_tv_hongguo_guest_created_at")
            httpTrace.recordGuest(json: json, createdAt: created)
        }
        context.setObject(saveDeviceBlock, forKeyedSubscript: "__native_save_device" as NSString)

        let account = accountSnapshot().record
        let accountDevice = (script == BuiltInHongguoJSContent && account?.hasSession == true ? account?.device : nil).flatMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(decoding: $0, as: UTF8.self) }
        if let cachedDevice = accountDevice ?? (persistentDeviceSession ? defaults.string(forKey: "thl_tv_hongguo_device_session") : nil), SavedGuestSession.valid(cachedDevice) {
            httpTrace.recordGuest(json: cachedDevice, createdAt: defaults.double(forKey: "thl_tv_hongguo_guest_created_at"))
            context.evaluateScript("""
            try {
                var raw = \(cachedDevice.debugDescription);
                globalThis.__hongguoCachedDevice = typeof raw === 'string' ? JSON.parse(raw) : raw;
            } catch(_) {}
            """)
        }

        // 2. 注入原生 HTTP 请求桥接
        let trustedAccountSource = script == BuiltInHongguoJSContent
        let expectedAccountRevision = accountSnapshot().revision
        let accountActive: @convention(block) () -> Bool = { [weak self] in
            guard let self else { return false }
            return trustedAccountSource && self.accountSnapshot().record?.hasSession == true
        }
        context.setObject(accountActive, forKeyedSubscript: "__native_account_active" as NSString)
        context.evaluateScript("Object.defineProperty(globalThis, '__hongguoAccountActive', {get: function(){return !!__native_account_active();}});")

        let session = httpSession
        let recorder = diagnostics
        let diagCtx = diagnosticContext
        let fetchBlock: @convention(block) (String, [String: Any]?) -> [String: Any] = { [weak self] urlStr, opts in
            guard let self, let url = URL(string: urlStr) else {
                return [
                    "status": 0, "headers": [:], "body": "", "error": "INVALID_URL",
                    "errorDetail": "无效目标地址: \(urlStr)", "category": DiagnosticCategory.unknown.rawValue
                ]
            }
            if Task.isCancelled {
                return ["status": 0, "headers": [:], "body": "", "error": "CANCELLED", "category": "cancelled"]
            }
            var req = URLRequest(url: url)
            let timeout = min(12.0, max(0.001, (opts?["timeoutMs"] as? Double ?? 10000) / 1000))
            req.timeoutInterval = timeout
            let method = (opts?["method"] as? String ?? "GET").uppercased()
            req.httpMethod = method
            req.httpShouldHandleCookies = false
            if let headers = opts?["headers"] as? [String: Any] {
                for (k, v) in headers {
                    req.setValue(String(describing: v), forHTTPHeaderField: k)
                }
            }
            let accountBusiness = HongguoAccountVault.businessURL(url)
            if accountBusiness {
                let acc = self.accountSnapshot()
                guard expectedAccountRevision == acc.revision else {
                    return ["status": 0, "headers": [:], "body": "", "error": "CANCELLED"]
                }
                if acc.record?.hasSession == true {
                    guard trustedAccountSource else {
                        return ["status": 0, "headers": [:], "body": "", "error": "ACCOUNT_SOURCE_UNTRUSTED"]
                    }
                    let cookie = HongguoAccountVault.shared.header(for: url, record: acc.record)
                    guard !cookie.isEmpty else { return ["status": 0, "headers": [:], "body": "", "error": "ACCOUNT_EXPIRED"] }
                    req.setValue(cookie, forHTTPHeaderField: "Cookie")
                }
            }
            if let body = opts?["body"] as? String {
                req.httpBody = body.data(using: .utf8)
            }

            let semaphore = DispatchSemaphore(value: 0)
            let started = ProcessInfo.processInfo.systemUptime
            let result = NativeHTTPResult()
            let task = session.dataTask(with: req) { data, response, error in
                result.complete(data: data, response: response, error: error)
                semaphore.signal()
            }
            task.resume()
            let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
            if timedOut { task.cancel() }
            let response = result.snapshot(timedOut: timedOut)
            if accountBusiness && expectedAccountRevision != self.accountSnapshot().revision {
                return ["status": 0, "headers": [:], "body": "", "error": "CANCELLED"]
            }

            var tabsDesc = ""
            var snippet = ""
            if !response.body.isEmpty {
                let trimmed = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
                snippet = SourceDiagnostics.responseSummary(trimmed)
                if url.path.contains("/search/tab/v"),
                   let data = response.body.data(using: .utf8),
                   let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   let tabs = parsed["search_tabs"] as? [[String: Any]] {
                    let descs = tabs.map { "\($0["tab_type"] ?? -1):\($0["title"] ?? $0["tab_name"] ?? "")((\(($0["data"] as? [Any])?.count ?? 0)条)" }
                    tabsDesc = "tabs[\(tabs.count)]: [" + descs.joined(separator: ", ") + "]"
                }
            }

            let logId = response.headers["x-tt-logid"] ?? response.headers["x-tt-traceid"] ?? response.headers["x-ss-req-ticket"] ?? ""
            httpTrace.record(
                url: SourceDiagnostics.desensitizeUrl(url.absoluteString),
                method: method,
                status: response.status,
                logId: logId,
                snippet: snippet,
                tabsSummary: tabsDesc
            )

            recorder.record(
                url: url,
                context: diagCtx,
                elapsedMs: Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
                status: response.status,
                body: response.body,
                method: method,
                headers: response.headers,
                bodyBytes: response.bodyBytes,
                errorCode: response.error,
                error: response.rawError
            )
            return [
                "status": response.status,
                "headers": response.headers,
                "body": response.body,
                "error": response.error,
                "errorDetail": response.errorDetail,
                "category": response.category.rawValue
            ]
        }
        context.setObject(fetchBlock, forKeyedSubscript: "__native_fetch" as NSString)

        // 3. 注入标准 CatPawOpen 全局垫片
        injectShims(into: context)
    }

    func refreshSigningCache(_ context: JSContext) {
        localPlaybackProfileUnavailable = false
        guard context.evaluateScript("globalThis.__hongguoHasBuiltInSigning === true")?.toBool() != true else { return }
        do {
            if let profile = try playbackProfileLoader() {
                context.setObject(["configuration": profile.configuration, "sdkVersion": profile.sdkVersion] as NSDictionary,
                                  forKeyedSubscript: "__hongguoPendingLocalProfile" as NSString)
                context.evaluateScript("""
                try { globalThis.__hongguoUseLocalApkProfile(globalThis.__hongguoPendingLocalProfile); }
                catch (_) { globalThis.__hongguoProfileErrorCode = 'LOCAL_PROFILE_INVALID'; }
                delete globalThis.__hongguoPendingLocalProfile;
                """)
            }
        } catch HongguoProfileStorageError.invalidProfile {
            context.evaluateScript("globalThis.__hongguoProfileErrorCode = 'LOCAL_PROFILE_INVALID';")
        } catch {
            localPlaybackProfileUnavailable = true
            context.evaluateScript("globalThis.__hongguoProfileErrorCode = 'LOCAL_PROFILE_UNAVAILABLE';")
        }
    }

    @discardableResult
    func synchronizeGuestSession(_ context: JSContext, sourceId: String, httpTrace: HttpTraceHolder) -> Bool {
        if accountSnapshot().record?.device != nil { return false }
        guard persistentDeviceSession, sourceId == "hongguo",
              let latest = deviceDefaults.string(forKey: "thl_tv_hongguo_device_session"),
              SavedGuestSession.valid(latest) else { return false }
        let created = deviceDefaults.double(forKey: "thl_tv_hongguo_guest_created_at")
        let current = httpTrace.guestSnapshot
        let currentCreated = current.createdAt
        if latest == current.json {
            if created > currentCreated { httpTrace.recordGuest(json: latest, createdAt: created) }
            return false
        }
        guard created <= 0 || currentCreated <= 0 || created >= currentCreated else { return false }
        let applied = context.evaluateScript("""
        (function() {
            if (typeof HongguoApp === 'undefined' || typeof HongguoApp.resetGuestSession !== 'function') return false;
            HongguoApp.resetGuestSession();
            globalThis.__hongguoCachedDevice = JSON.parse(\(latest.debugDescription));
            return true;
        })()
        """)?.toBool() == true
        guard applied else { return false }
        httpTrace.recordGuest(json: latest, createdAt: created)
        diagnostics.add(SourceDiagnosticEntry(context: diagnosticContext, stage: "游客会话同步", sessionStatus: "请求前载入其他运行环境更新的游客会话，保留搜索和详情缓存"))
        return true
    }

    private func injectShims(into context: JSContext) {
        let shims = """
        var JSON = JSON || {};
        if (!JSON.stringify) JSON.stringify = function(o) { return "{}"; };
        if (!JSON.parse) JSON.parse = function(s) { return {}; };
        (function() {
          var nativeParse = JSON.parse;
          JSON.parse = function(text, reviver) {
            if (typeof text === 'string' && /\\d{15,}/.test(text)) {
              var output = '';
              var copied = 0;
              var quoted = false;
              var escaped = false;
              var numberCharacters = '0123456789.eE+-';
              for (var index = 0; index < text.length; index++) {
                var character = text[index];
                if (quoted) {
                  if (escaped) escaped = false;
                  else if (character === '\\\\') escaped = true;
                  else if (character === '"') quoted = false;
                  continue;
                }
                if (character === '"') {
                  quoted = true;
                  continue;
                }
                if (character !== '-' && (character < '0' || character > '9')) continue;
                var start = index;
                while (index < text.length && numberCharacters.indexOf(text[index]) >= 0) index++;
                var token = text.slice(start, index);
                if (/^-?[1-9]\\d{14,}$/.test(token)) {
                  output += text.slice(copied, start) + '"' + token + '"';
                  copied = index;
                }
                index--;
              }
              if (copied > 0) text = output + text.slice(copied);
            }
            return nativeParse(text, reviver);
          };
        })();

        globalThis.console = {
            log: function() { var args = Array.prototype.slice.call(arguments); __console_log(args.join(" ")); },
            warn: function() { var args = Array.prototype.slice.call(arguments); __console_log("[WARN] " + args.join(" ")); },
            error: function() { var args = Array.prototype.slice.call(arguments); __console_log("[ERROR] " + args.join(" ")); },
            info: function() { var args = Array.prototype.slice.call(arguments); __console_log(args.join(" ")); }
        };

        globalThis.fetch = async function(url, opts) {
            opts = opts || {};
            var res = __native_fetch(String(url), opts);
            var status = typeof res.status === "number" ? res.status : 0;
            var respBody = res.body || "";
            var respHeaders = res.headers || {};
            if ((status === 0 || res.error === "RESPONSE_NOT_UTF8") && (res.error || res.errorDetail)) {
                var netErr = new Error("网络请求失败: " + (res.errorDetail || res.error || "未知网络错误"));
                netErr.code = res.error || "HTTP_0";
                netErr.category = res.category || "network_timeout";
                netErr.isNetworkError = true;
                throw netErr;
            }
            return {
                status: status,
                ok: status >= 200 && status < 300,
                headers: respHeaders,
                body: respBody,
                text: async function() { return respBody; },
                json: async function() {
                    try {
                        return JSON.parse(respBody || "{}");
                    } catch(e) {
                        var jsonErr = new Error("响应数据不是合法 JSON: " + (respBody.slice(0, 100) || "空响应"));
                        jsonErr.category = "invalid_resp";
                        throw jsonErr;
                    }
                }
            };
        };
        """
        context.evaluateScript(shims)
    }
}
