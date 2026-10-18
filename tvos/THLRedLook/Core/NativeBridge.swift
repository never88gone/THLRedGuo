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

    // 沙盒路径
    private var baseDirURL: URL
    private var sourcesDirURL: URL

    // 当前数据源状态
    private var installedSources: [String: [String: Any]] = [:]
    private var sourceScripts: [String: String] = [:]
    private var activeSourceId: String = ""

    // JS 运行时上下文缓存
    private var jsContexts: [String: JSContext] = [:]

    init(baseDirectory: URL? = nil, httpSession: URLSession = .shared, diagnostics: SourceDiagnostics = .shared, diagnosticContext: String = "日常使用") {
        self.httpSession = httpSession
        self.diagnostics = diagnostics
        self.diagnosticContext = diagnosticContext
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.baseDirURL = baseDirectory ?? cachesDir.appendingPathComponent("THLRedLook_Data")
        self.sourcesDirURL = self.baseDirURL.appendingPathComponent("sources")

        try? FileManager.default.createDirectory(at: self.sourcesDirURL, withIntermediateDirectories: true)
    }

    /// 保证核心正规初始化严格就绪
    public func ensureInitialized() async throws {
        if isInitialized { return }

        try? FileManager.default.createDirectory(at: sourcesDirURL, withIntermediateDirectories: true)

        let hongguoFile = sourcesDirURL.appendingPathComponent("hongguo.js")
        let needsUpdate: Bool
        if let currentScript = try? String(contentsOf: hongguoFile, encoding: .utf8) {
            needsUpdate = currentScript != BuiltInHongguoJSContent
        } else {
            needsUpdate = true
        }
        if needsUpdate {
            try? BuiltInHongguoJSContent.write(to: hongguoFile, atomically: true, encoding: .utf8)
            NSLog("🎬 [NativeBridge] 已自动同步并更新最新内置官方数据源到沙盒: %@", hongguoFile.path)
        }

        scanSourcesDirectory()

        if activeSourceId.isEmpty || activeSourceId == "hongguo" || !installedSources.keys.contains(activeSourceId) {
            activeSourceId = installedSources.keys.contains("hongguo") ? "hongguo" : (installedSources.keys.first ?? "")
        }

        isInitialized = true
        NSLog("🎬 [NativeBridge] CatPawOpen Swift 原生核心初始化成功，已装载 %ld 个插件，当前激活源: '%@'", installedSources.count, activeSourceId)
    }

    /// 扫描沙盒 sources 目录中的所有 JS Spider 脚本
    private func scanSourcesDirectory() {
        installedSources.removeAll()
        sourceScripts.removeAll()
        jsContexts.removeAll()

        guard let files = try? FileManager.default.contentsOfDirectory(at: sourcesDirURL, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where file.pathExtension.lowercased() == "js" {
            guard var script = try? String(contentsOf: file, encoding: .utf8), !script.isEmpty else {
                continue
            }
            if let meta = extractScriptMeta(script: script, fallbackId: file.deletingPathExtension().lastPathComponent) {
                let sid = meta["id"] as? String ?? file.deletingPathExtension().lastPathComponent
                if sid == "hongguo" && script != BuiltInHongguoJSContent {
                    script = BuiltInHongguoJSContent
                    try? BuiltInHongguoJSContent.write(to: file, atomically: true, encoding: .utf8)
                    NSLog("🎬 [NativeBridge] 扫描时已将旧版沙盒数据源自动热升级为最新内置官方源")
                }
                installedSources[sid] = meta
                sourceScripts[sid] = script
            }
        }

        // 如果存在活跃源但不在已安装列表中，清空或重置
        if !installedSources.keys.contains(activeSourceId) {
            activeSourceId = installedSources.keys.contains("hongguo") ? "hongguo" : (installedSources.keys.first ?? "")
        }
    }

    /// 解析 Spider 脚本中的元数据 (meta)
    private func extractScriptMeta(script: String, fallbackId: String) -> [String: Any]? {
        let ctx = JSContext()!
        ctx.evaluateScript("var meta = {}; var spider = { meta: {} };")
        ctx.evaluateScript(script)

        let metaVal = ctx.evaluateScript("typeof spider !== 'undefined' && spider.meta ? spider.meta : (typeof meta !== 'undefined' ? meta : null);")
        if let dict = metaVal?.toDictionary() as? [String: Any], let id = dict["id"] as? String, !id.isEmpty {
            return dict
        }

        // 正则兜底解析
        if let match = script.range(of: "id\\s*:\\s*[\"']([^\"']+)[\"']", options: .regularExpression) {
            let idSubstring = script[match]
            let id = idSubstring.components(separatedBy: CharacterSet(charactersIn: "\"'"))[1]
            let nameMatch = script.range(of: "name\\s*:\\s*[\"']([^\"']+)[\"']", options: .regularExpression)
            let name = nameMatch != nil ? script[nameMatch!].components(separatedBy: CharacterSet(charactersIn: "\"'"))[1] : id
            return [
                "id": id,
                "name": name,
                "version": "1.0.0",
                "description": "自定义 JS 插件"
            ]
        }

        return [
            "id": fallbackId,
            "name": fallbackId,
            "version": "1.0.0",
            "description": "本地 JS 插件"
        ]
    }

    /// 获取或构建指定数据源的 CatPawOpen JS 运行时上下文
    private func getOrCreateContext(sourceId: String) -> JSContext? {
        if let existing = jsContexts[sourceId] {
            return existing
        }

        guard let script = sourceScripts[sourceId] else {
            return nil
        }

        guard let context = JSContext() else {
            return nil
        }

        let entropy = (0..<64).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        context.evaluateScript("globalThis.__hongguoEntropy = '\(entropy)';")

        // 1. 注入控制台日志
        let logBlock: @convention(block) (String) -> Void = { msg in
            NSLog("🎬 [CatPawOpen JS:%@] %@", sourceId, msg)
        }
        context.setObject(logBlock, forKeyedSubscript: "__console_log" as NSString)

        // 2. 注入原生高性能 HTTP 请求桥接
        let session = httpSession
        let recorder = diagnostics
        let diagnosticContext = diagnosticContext
        let fetchBlock: @convention(block) (String, [String: Any]?) -> [String: Any] = { urlStr, opts in
            guard let url = URL(string: urlStr) else {
                return ["status": 0, "headers": [:], "body": "", "error": "无效的 URL"]
            }
            var req = URLRequest(url: url)
            let timeout = min(12.0, max(0.001, (opts?["timeoutMs"] as? Double ?? 10000) / 1000))
            req.timeoutInterval = timeout
            let method = (opts?["method"] as? String ?? "GET").uppercased()
            req.httpMethod = method
            if let headers = opts?["headers"] as? [String: Any] {
                for (k, v) in headers {
                    req.setValue(String(describing: v), forHTTPHeaderField: k)
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
            recorder.record(url: url, context: diagnosticContext, elapsedMs: Int((ProcessInfo.processInfo.systemUptime - started) * 1000), status: response.status, body: response.body, errorCode: response.error)
            return ["status": response.status, "headers": response.headers, "body": response.body]

        }
        context.setObject(fetchBlock, forKeyedSubscript: "__native_fetch" as NSString)

        // 3. 注入标准 CatPawOpen 全局垫片 (console, fetch, html.parse)
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
            return {
                status: status,
                ok: status >= 200 && status < 300,
                headers: respHeaders,
                body: respBody,
                text: async function() { return respBody; },
                json: async function() {
                    try { return JSON.parse(respBody || "{}"); } catch(e) { return {}; }
                }
            };
        };

        var html = (function() {
            function cleanText(t) { return (t || "").replace(/<[^>]+>/g, "").trim(); }
            function parseAttrs(str) {
                var attrs = {};
                if (!str) return attrs;
                var re = /([a-zA-Z0-9_\\-:]+)(?:\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>`]+)))?/g;
                var match;
                while ((match = re.exec(str)) !== null) {
                    var key = match[1].toLowerCase();
                    var val = match[2] !== undefined ? match[2] : (match[3] !== undefined ? match[3] : (match[4] !== undefined ? match[4] : ""));
                    attrs[key] = val;
                }
                return attrs;
            }
            function Node(tag, attrs, content) {
                this.tag = (tag || "").toLowerCase();
                this.attrs = attrs || {};
                this.content = content || "";
            }
            Node.prototype.text = function() { return cleanText(this.content); };
            Node.prototype.attr = function(n) { return this.attrs[n.toLowerCase()] || ""; };

            return {
                parse: function(str) {
                    str = str || "";
                    return {
                        find: function(sel) {
                            var nodes = [];
                            var re = /<([a-zA-Z0-9]+)([^>]*)>([\\s\\S]*?)<\\/\\1>/gi;
                            var m;
                            while ((m = re.exec(str)) !== null) {
                                var tag = m[1];
                                var attrStr = m[2];
                                var inner = m[3];
                                var attrs = parseAttrs(attrStr);
                                nodes.push(new Node(tag, attrs, inner));
                            }
                            return {
                                length: nodes.length,
                                eq: function(i) { return nodes[i] || new Node("", {}, ""); },
                                text: function() { return nodes.map(function(n) { return n.text(); }).join(" "); },
                                attr: function(n) { return nodes.length > 0 ? nodes[0].attr(n) : ""; }
                            };
                        }
                    };
                }
            };
        })();
        """
        context.evaluateScript(shims)

        // 4. 执行 Spider 脚本代码
        context.evaluateScript(script)
        context.evaluateScript("if (typeof spider !== 'undefined' && typeof spider.init === 'function') { spider.init({}); }")

        jsContexts[sourceId] = context
        return context
    }

    private func spiderExpression(_ method: String, _ arguments: [Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: arguments, options: [.fragmentsAllowed])
        return "spider.\(method).apply(spider, \(String(decoding: data, as: UTF8.self)))"
    }

    /// 在 JS 运行时中异步评估 Promise 并等待结果
    private func evalAsync(context: JSContext, scriptExpr: String) -> [String: Any]? {
        let sem = DispatchSemaphore(value: 0)
        var resultData: [String: Any]? = nil

        let doneKey = "__done_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let onDone: @convention(block) (String) -> Void = { jsonStr in
            if let data = jsonStr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                resultData = obj
            }
            sem.signal()
        }
        context.setObject(onDone, forKeyedSubscript: doneKey as NSString)

        let wrapper = """
        (async function() {
            try {
                var res = await (\(scriptExpr));
                \(doneKey)(JSON.stringify({ ok: true, data: res }));
            } catch (err) {
                \(doneKey)(JSON.stringify({ ok: false, error: err ? (err.message || String(err)) : "Error", code: err && err.code ? String(err.code) : "JS_EXECUTION" }));
            }
        })();
        """
        context.evaluateScript(wrapper)

        _ = sem.wait(timeout: .now() + 60.0)
        context.setObject(nil, forKeyedSubscript: doneKey as NSString)

        return resultData
    }

    /// 将 vod_* 数据结构转换为应用统一的 Drama 字典
    private func mapVodToDrama(vod: [String: Any], sourceId: String) -> [String: Any] {
        let vid = vod["vod_id"] as? String ?? "\(vod["id"] ?? UUID().uuidString)"
        let title = (vod["vod_name"] as? String) ?? (vod["title"] as? String) ?? "短剧 \(vid)"
        var cover = (vod["vod_pic"] as? String) ?? (vod["cover"] as? String) ?? (vod["cover_url"] as? String) ?? (vod["series_cover"] as? String) ?? ""
        cover = cover.trimmingCharacters(in: .whitespacesAndNewlines)
        if cover.hasPrefix("//") {
            cover = "https:" + cover
        }
        let desc = (vod["vod_content"] as? String) ?? (vod["desc"] as? String) ?? ""
        let remark = (vod["vod_remarks"] as? String) ?? (vod["remarks"] as? String) ?? ""
        let year = (vod["vod_year"] as? String) ?? "2024"

        var epCount = 0
        if let match = remark.range(of: "(\\d+)", options: .regularExpression) {
            epCount = Int(remark[match]) ?? 0
        }

        return [
            "id": vid.hasPrefix("\(sourceId):") ? vid : "\(sourceId):\(vid)",
            "source": sourceId,
            "sourceId": vid.hasPrefix("\(sourceId):") ? String(vid.dropFirst(sourceId.count + 1)) : vid,
            "title": title,
            "description": desc,
            "cover": cover,
            "episodes": epCount,
            "category": "short_play",
            "heat": remark.isEmpty ? "热播" : remark,
            "views": "100万+",
            "onlineDate": year,
            "tags": ["爽剧", "热门"],
            "releaseStatus": remark
        ]
    }

    /// 处理所有业务操作 Action 请求
    public func request(action: String, payload: [String: Any]) async throws -> [String: Any] {
        if action != "initialize" {
            try await ensureInitialized()
        }

        switch action {
        case "initialize":
            try await ensureInitialized()
            return [
                "ok": true,
                "data": [
                    "version": "1.0.0",
                    "standalone": true,
                    "allSources": true
                ]
            ]

        case "jsSource.list":
            return [
                "items": Array(installedSources.values),
                "active": activeSourceId
            ]

        case "jsSource.setActive":
            let source = payload["source"] as? String ?? ""
            if installedSources.keys.contains(source) {
                activeSourceId = source
                return ["ok": true, "active": activeSourceId]
            }
            return ["ok": false, "active": activeSourceId]

        case "jsSource.getActive":
            return [
                "active": activeSourceId,
                "meta": installedSources[activeSourceId] ?? [:]
            ]

        case "jsSource.saveAndLoad":
            let script = payload["script"] as? String ?? ""
            let fileName = payload["fileName"] as? String ?? "custom.js"
            let autoSelect = (payload["autoSelect"] as? Bool) ?? true
            guard !script.isEmpty else {
                throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "脚本内容为空"])
            }
            let targetFile = sourcesDirURL.appendingPathComponent(fileName)
            try script.write(to: targetFile, atomically: true, encoding: .utf8)
            scanSourcesDirectory()
            let fileId = fileName.replacingOccurrences(of: ".js", with: "")
            if let targetMeta = installedSources.values.first(where: {
                let sid = ($0["id"] as? String) ?? ""
                return sid == "hongguo" || sid == fileId
            }) {
                let targetId = targetMeta["id"] as? String ?? activeSourceId
                if autoSelect || targetId == "hongguo" || activeSourceId.isEmpty {
                    activeSourceId = targetId
                }
            } else if autoSelect, let meta = installedSources[fileId] {
                activeSourceId = fileId
            }
            return ["ok": true, "active": activeSourceId]

        case "jsSource.scan":
            scanSourcesDirectory()
            return ["ok": true, "count": installedSources.count]

        case "jsSource.remove":
            let sourceId = payload["source"] as? String ?? ""
            if !sourceId.isEmpty {
                let candidate1 = sourcesDirURL.appendingPathComponent("\(sourceId).js")
                try? FileManager.default.removeItem(at: candidate1)
                scanSourcesDirectory()
                return ["ok": true]
            }
            return ["ok": false]

        case "categories":
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? activeSourceId
            guard !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                return ["items": [["id": "", "name": "全部"]]]
            }

            let res = evalAsync(context: ctx, scriptExpr: "spider.home()")
            var items: [[String: Any]] = [["id": "", "name": "全部"]]

            if let data = res?["data"] as? [String: Any],
               let classes = (data["class"] as? [[String: Any]]) ?? (data["classes"] as? [[String: Any]]) {
                for c in classes {
                    let tid = c["type_id"] as? String ?? ""
                    let tname = c["type_name"] as? String ?? tid
                    if !tid.isEmpty {
                        items.append(["id": tid, "name": tname])
                    }
                }
            }
            return ["items": items]

        case "catalog":
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? activeSourceId
            guard !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                return ["items": [], "hasMore": false, "page": 1]
            }
            let query = (payload["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cat = payload["category"] as? String ?? ""
            let pg = payload["page"] as? Int ?? 1

            if !query.isEmpty {
                let scriptExpr = try spiderExpression("search", [query, false, pg])
                let evaluated = evalAsync(context: ctx, scriptExpr: scriptExpr)
                guard let res = evaluated, res["ok"] as? Bool == true else {
                    let candidate = SourceDiagnostics.safeCode(evaluated?["code"])
                    let code = candidate.isEmpty ? "JS_TIMEOUT" : candidate
                    diagnostics.add(SourceDiagnosticEntry(context: diagnosticContext, stage: "搜索执行", errorCode: code))
                    throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "官方搜索失败（\(code)），请到设置的数据源诊断查看记录"])
                }
                var searchItems: [[String: Any]] = []
                var searchHasMore = false
                if let data = res["data"] as? [String: Any] {
                    let pageCount = (data["pagecount"] as? Int) ?? (data["pageCount"] as? Int) ?? pg
                    searchHasMore = pg < pageCount
                    let list = data["list"] as? [[String: Any]] ?? []
                    for vod in list {
                        searchItems.append(mapVodToDrama(vod: vod, sourceId: targetSrc))
                    }
                } else if let list = res["data"] as? [[String: Any]] {
                    for vod in list {
                        searchItems.append(mapVodToDrama(vod: vod, sourceId: targetSrc))
                    }
                }
                return [
                    "items": searchItems,
                    "hasMore": searchHasMore,
                    "page": pg
                ]
            }

            let scriptExpr = try spiderExpression("category", [cat, pg, false, [:]])
            let res = evalAsync(context: ctx, scriptExpr: scriptExpr)

            var dramas: [[String: Any]] = []
            var hasMore = false

            if let data = res?["data"] as? [String: Any] {
                let list = data["list"] as? [[String: Any]] ?? []
                for vod in list {
                    dramas.append(mapVodToDrama(vod: vod, sourceId: targetSrc))
                }
                let pageCount = (data["pagecount"] as? Int) ?? (data["pageCount"] as? Int) ?? 1
                hasMore = pg < pageCount
            }
            return [
                "items": dramas,
                "hasMore": hasMore,
                "page": pg
            ]

        case "search":
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? activeSourceId
            let query = payload["query"] as? String ?? ""
            guard !targetSrc.isEmpty, !query.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                return ["items": []]
            }

            let scriptExpr = try spiderExpression("search", [query, false, 1])
            let res = evalAsync(context: ctx, scriptExpr: scriptExpr)

            var dramas: [[String: Any]] = []
            if let data = res?["data"] as? [String: Any] {
                let list = data["list"] as? [[String: Any]] ?? []
                for vod in list {
                    dramas.append(mapVodToDrama(vod: vod, sourceId: targetSrc))
                }
            } else if let list = res?["data"] as? [[String: Any]] {
                for vod in list {
                    dramas.append(mapVodToDrama(vod: vod, sourceId: targetSrc))
                }
            }
            return ["items": dramas]

        case "detail":
            guard let dramaDict = payload["drama"] as? [String: Any],
                  let dramaId = dramaDict["id"] as? String, !dramaId.isEmpty else {
                throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "剧集信息无效"])
            }
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (dramaDict["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? activeSourceId
            guard !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "数据源未就绪"])
            }

            let scriptExpr = try spiderExpression("detail", [dramaId])
            let res = evalAsync(context: ctx, scriptExpr: scriptExpr)

            var freshDrama = dramaDict
            var chapters: [[String: Any]] = []

            if let data = res?["data"] as? [String: Any] {
                let vod: [String: Any]
                if let list = data["list"] as? [[String: Any]], let first = list.first {
                    vod = first
                } else if let v = data["vod"] as? [String: Any] {
                    vod = v
                } else {
                    vod = data
                }

                let mapped = vod["vod_id"] != nil || vod["id"] != nil
                    ? mapVodToDrama(vod: vod, sourceId: targetSrc) : [:]
                for (k, v) in mapped {
                    if let str = v as? String, !str.isEmpty {
                        freshDrama[k] = str
                    } else if let num = v as? Int, num > 0 {
                        freshDrama[k] = num
                    } else if freshDrama[k] == nil {
                        freshDrama[k] = v
                    }
                }

                // 解析 CatPawOpen 规范标准选集串: vod_play_url ("第1集$url1#第2集$url2" 或带线路 "线路$$$第1集$url1#...")
                if let playUrls = vod["vod_play_url"] as? String, !playUrls.isEmpty {
                    let routes = playUrls.components(separatedBy: "$$$")
                    let mainRoute = routes.last ?? playUrls
                    let eps = mainRoute.components(separatedBy: "#")

                    for (idx, epStr) in eps.enumerated() {
                        let parts = epStr.components(separatedBy: "$")
                        let epTitle = parts.first?.isEmpty == false ? parts.first! : "第 \(idx + 1) 集"
                        let epUrl = parts.count > 1 ? parts[1] : ""
                        chapters.append([
                            "id": "\(dramaId)_\(idx + 1)",
                            "title": epTitle,
                            "currentEpisode": idx + 1,
                            "index": idx + 1,
                            "vip": false,
                            "url": epUrl
                        ])
                    }
                }
            }

            return [
                "drama": freshDrama,
                "chapters": chapters,
                "episodes": chapters,
                "warning": ""
            ]

        case "resolve":
            let dramaDict = payload["drama"] as? [String: Any] ?? [:]
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (dramaDict["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? activeSourceId
            let epIndex = payload["index"] as? Int ?? 1
            let dramaId = dramaDict["id"] as? String ?? "1"

            var targetUrl = ""
            var targetHeaders: [String: String] = [:]
            var contentKey = ""
            var expiresAt: Int64 = 0
            var mediaBytes: Int64 = 0
            var danmakuId = ""
            var reportedQuality = 0
            var reportedQualities: [Int] = []

            if !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) {
                let chapterDict = payload["chapter"] as? [String: Any]
                let rawUrl = (chapterDict?["url"] as? String) ?? "\(dramaId)/\(epIndex)"

                let flags: [[String: Any]] = [[
                    "quality": payload["quality"] as? Int ?? 0,
                    "avoidUrl": payload["avoidUrl"] as? String ?? ""
                ]]
                let scriptExpr = try spiderExpression("play", ["", rawUrl, flags])
                let res = evalAsync(context: ctx, scriptExpr: scriptExpr)

                if let data = res?["data"] as? [String: Any] {
                    targetUrl = data["url"] as? String ?? ""
                    danmakuId = data["danmakuId"] as? String ?? ""
                    contentKey = data["decryptionKey"] as? String ?? ""
                    expiresAt = (data["expiresAt"] as? NSNumber)?.int64Value ?? 0
                    mediaBytes = (data["mediaBytes"] as? NSNumber)?.int64Value ?? 0
                    reportedQuality = data["quality"] as? Int ?? 0
                    reportedQualities = data["qualities"] as? [Int] ?? []
                    if let hdr = (data["header"] as? [String: String]) ?? (data["headers"] as? [String: String]) {
                        targetHeaders = hdr
                    }
                }
            }

            if targetUrl.isEmpty || targetUrl.contains("example.com") {
                throw NSError(domain: "CatPawOpen", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法从数据源获取当前分集的真实播放流，请重试"])
            }

            if !contentKey.isEmpty && contentKey.range(of: "^[0-9a-fA-F]{32}$", options: .regularExpression) == nil {
                throw NSError(domain: "CatPawOpen", code: -3, userInfo: [NSLocalizedDescriptionKey: "站源内容密钥无效"])
            }
            var detectedQuality = reportedQuality
            if targetUrl.contains("4k") || targetUrl.contains("2160p") {
                detectedQuality = 2160
            } else if targetUrl.contains("1080p") {
                detectedQuality = 1080
            } else if targetUrl.contains("720p") {
                detectedQuality = 720
            } else if targetUrl.contains("480p") {
                detectedQuality = 480
            } else if targetUrl.contains("360p") {
                detectedQuality = 360
            }

            let effectiveQuality = detectedQuality
            return [
                "url": targetUrl,
                "headers": targetHeaders,
                "decryptionKey": contentKey,
                "expiresAt": expiresAt,
                "danmakuId": danmakuId,
                "mediaBytes": mediaBytes,
                "quality": effectiveQuality,
                "qualities": reportedQualities.isEmpty ? (detectedQuality > 0 ? [detectedQuality] : []) : reportedQualities,
                "session": "\(Date().timeIntervalSince1970)"
            ]

        case "danmaku":
            let id = payload["episodeId"] as? String ?? ""
            guard id.hasPrefix("hongguo:"), let context = getOrCreateContext(sourceId: "hongguo") else {
                throw NSError(domain: "THLRedLook.Danmaku", code: -1, userInfo: [NSLocalizedDescriptionKey: "本集暂不支持弹幕"])
            }
            let expression = try spiderExpression("danmaku", [id, payload["startMs"] as? Int64 ?? 0, payload["durationMs"] as? Int64 ?? 0])
            guard let response = evalAsync(context: context, scriptExpr: expression), response["ok"] as? Bool == true,
                  let result = response["data"] as? [String: Any], result["items"] is [[String: Any]] else {
                throw NSError(domain: "THLRedLook.Danmaku", code: -2, userInfo: [NSLocalizedDescriptionKey: "官方弹幕暂不可用"])
            }
            return result

        case "rankingBoards":
            let src = activeSourceId.isEmpty ? "hongguo" : activeSourceId
            return [
                "items": [
                    [
                        "id": "\(src)-hot",
                        "name": "总热播榜",
                        "category": "hot",
                        "source": src,
                        "description": "实时综合热度排行榜"
                    ],
                    [
                        "id": "\(src)-real",
                        "name": "真人剧榜",
                        "category": "real",
                        "source": src,
                        "description": "高口碑真人短剧热门排行"
                    ],
                    [
                        "id": "\(src)-comic",
                        "name": "漫剧榜",
                        "category": "comic",
                        "source": src,
                        "description": "精彩动态漫剧精选排行"
                    ],
                    [
                        "id": "\(src)-ai",
                        "name": "AI剧榜",
                        "category": "ai",
                        "source": src,
                        "description": "前沿生成式 AI 剧情剧集排行"
                    ]
                ]
            ]

        case "rankings":
            let src = activeSourceId.isEmpty ? "hongguo" : activeSourceId
            let boardId = ((payload["board"] as? String) ?? "\(src)-hot").lowercased()
            let catTarget: String
            let pageNum: Int
            if boardId.contains("comic") {
                catTarget = "comic-drama"
                pageNum = 1
            } else if boardId.contains("ai") {
                catTarget = "ai-drama"
                pageNum = 1
            } else if boardId.contains("real") {
                catTarget = "real-drama"
                pageNum = 1
            } else {
                // 总热播榜：综合拉取
                catTarget = "real-drama"
                pageNum = 2
            }
            let catReq: [String: Any] = ["source": src, "category": catTarget, "page": pageNum]
            let catRes = try await self.request(action: "catalog", payload: catReq)
            var items = catRes["items"] as? [[String: Any]] ?? []
            if items.isEmpty && pageNum > 1 {
                let fallbackRes = try await self.request(action: "catalog", payload: ["source": src, "category": catTarget, "page": 1])
                items = fallbackRes["items"] as? [[String: Any]] ?? []
            }

            var rankItems: [[String: Any]] = []
            for (idx, drama) in items.prefix(20).enumerated() {
                rankItems.append([
                    "rank": idx + 1,
                    "drama": drama,
                    "metric": "\(max(1, 999 - idx * 28))万热度"
                ])
            }
            return ["items": rankItems]

        case "recommendations":
            let src = activeSourceId.isEmpty ? "hongguo" : activeSourceId
            let rawCat = (payload["category"] as? String) ?? "real-drama"
            let catTarget: String
            switch rawCat {
            case "漫剧", "comic-drama", "comic_series":
                catTarget = "comic-drama"
            case "AI 剧", "AI剧", "ai-drama", "ai_series":
                catTarget = "ai-drama"
            default:
                catTarget = "real-drama"
            }
            let catReq: [String: Any] = ["source": src, "category": catTarget, "page": 1]
            let catRes = try await self.request(action: "catalog", payload: catReq)
            let items = catRes["items"] as? [[String: Any]] ?? []
            return ["items": items]

        case "suggestions":
            return ["items": []]

        default:
            return ["ok": true]
        }
    }
}

private final class NativeHTTPResult: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 0
    private var headers: [String: String] = [:]
    private var body = ""
    private var error = ""
    func complete(data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let response = response as? HTTPURLResponse {
            for (key, value) in response.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
        }
        if let data { body = String(data: data, encoding: .utf8) ?? "" }
        self.error = SourceDiagnostics.networkCode(error)
    }
    func snapshot(timedOut: Bool) -> (status: Int, headers: [String: String], body: String, error: String) {
        lock.lock()
        defer { lock.unlock() }
        return timedOut ? (0, [:], "", "TIMEOUT:-1001") : (status, headers, body, error)
    }
}
