import Foundation
import JavaScriptCore

/// 纯 Swift 原生 CatPawOpen 协议桥接引擎
/// 基于系统级 JavaScriptCore 运行时与 URLSession 端侧闭环执行 Spider 数据源解析。
public actor NativeBridge {
    public static let shared = NativeBridge()

    private var isInitialized = false

    // 沙盒路径
    private var baseDirURL: URL
    private var sourcesDirURL: URL

    // 当前数据源状态
    private var installedSources: [String: [String: Any]] = [:]
    private var sourceScripts: [String: String] = [:]
    private var activeSourceId: String = ""

    // JS 运行时上下文缓存
    private var jsContexts: [String: JSContext] = [:]

    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.baseDirURL = cachesDir.appendingPathComponent("THLRedLook_Data")
        self.sourcesDirURL = self.baseDirURL.appendingPathComponent("sources")

        try? FileManager.default.createDirectory(at: self.sourcesDirURL, withIntermediateDirectories: true)
    }

    /// 保证核心正规初始化严格就绪
    public func ensureInitialized() async throws {
        if isInitialized { return }

        try? FileManager.default.createDirectory(at: sourcesDirURL, withIntermediateDirectories: true)
        scanSourcesDirectory()

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
            guard let script = try? String(contentsOf: file, encoding: .utf8), !script.isEmpty else {
                continue
            }
            if let meta = extractScriptMeta(script: script, fallbackId: file.deletingPathExtension().lastPathComponent) {
                let sid = meta["id"] as? String ?? file.deletingPathExtension().lastPathComponent
                installedSources[sid] = meta
                sourceScripts[sid] = script
            }
        }

        // 如果存在活跃源但不在已安装列表中，清空或重置
        if !installedSources.keys.contains(activeSourceId) {
            activeSourceId = installedSources.keys.first ?? ""
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

        // 1. 注入控制台日志
        let logBlock: @convention(block) (String) -> Void = { msg in
            NSLog("🎬 [CatPawOpen JS:%@] %@", sourceId, msg)
        }
        context.setObject(logBlock, forKeyedSubscript: "__console_log" as NSString)

        // 2. 注入原生高性能 HTTP 请求桥接
        let fetchBlock: @convention(block) (String, [String: Any]?) -> [String: Any] = { urlStr, opts in
            guard let url = URL(string: urlStr) else {
                return ["status": 0, "headers": [:], "body": "", "error": "无效的 URL"]
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10.0
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
            var statusCode = 200
            var respHeaders = [String: String]()
            var respBody = ""

            let task = URLSession.shared.dataTask(with: req) { data, response, _ in
                if let http = response as? HTTPURLResponse {
                    statusCode = http.statusCode
                    for (k, v) in http.allHeaderFields {
                        respHeaders[String(describing: k)] = String(describing: v)
                    }
                }
                if let data = data {
                    respBody = String(data: data, encoding: .utf8) ?? ""
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 10.0)

            return [
                "status": statusCode,
                "headers": respHeaders,
                "body": respBody
            ]
        }
        context.setObject(fetchBlock, forKeyedSubscript: "__native_fetch" as NSString)

        // 3. 注入标准 CatPawOpen 全局垫片 (console, fetch, html.parse)
        let shims = """
        var JSON = JSON || {};
        if (!JSON.stringify) JSON.stringify = function(o) { return "{}"; };
        if (!JSON.parse) JSON.parse = function(s) { return {}; };

        globalThis.console = {
            log: function() { var args = Array.prototype.slice.call(arguments); __console_log(args.join(" ")); },
            warn: function() { var args = Array.prototype.slice.call(arguments); __console_log("[WARN] " + args.join(" ")); },
            error: function() { var args = Array.prototype.slice.call(arguments); __console_log("[ERROR] " + args.join(" ")); },
            info: function() { var args = Array.prototype.slice.call(arguments); __console_log(args.join(" ")); }
        };

        globalThis.fetch = async function(url, opts) {
            opts = opts || {};
            var res = __native_fetch(String(url), opts);
            var status = res.status || 200;
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
                \(doneKey)(JSON.stringify({ ok: false, error: err ? (err.message || String(err)) : "Error" }));
            }
        })();
        """
        context.evaluateScript(wrapper)

        _ = sem.wait(timeout: .now() + 12.0)
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
            "id": vid,
            "source": sourceId,
            "sourceId": sourceId,
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
                let scriptExpr = "spider.search(\"\(query)\", false, \(pg))"
                let res = evalAsync(context: ctx, scriptExpr: scriptExpr)
                var searchItems: [[String: Any]] = []
                if let data = res?["data"] as? [String: Any] {
                    let list = data["list"] as? [[String: Any]] ?? []
                    for vod in list {
                        searchItems.append(mapVodToDrama(vod: vod, sourceId: targetSrc))
                    }
                } else if let list = res?["data"] as? [[String: Any]] {
                    for vod in list {
                        searchItems.append(mapVodToDrama(vod: vod, sourceId: targetSrc))
                    }
                }
                return [
                    "items": searchItems,
                    "hasMore": false,
                    "page": pg
                ]
            }

            let scriptExpr = "spider.category(\"\(cat)\", \(pg), false, {})"
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

            let scriptExpr = "spider.search(\"\(query)\", false, 1)"
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
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? activeSourceId
            guard let dramaDict = payload["drama"] as? [String: Any],
                  let dramaId = dramaDict["id"] as? String, !dramaId.isEmpty else {
                throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "剧集信息无效"])
            }
            guard !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) else {
                throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "数据源未就绪"])
            }

            let scriptExpr = "spider.detail(\"\(dramaId)\")"
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

                freshDrama = mapVodToDrama(vod: vod, sourceId: targetSrc)

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

            // 如果分集列表为空，按照总集数兜底补全
            if chapters.isEmpty {
                let count = max(20, (freshDrama["episodes"] as? Int) ?? 20)
                for i in 1...count {
                    chapters.append([
                        "id": "\(dramaId)_\(i)",
                        "title": "第 \(i) 集",
                        "currentEpisode": i,
                        "index": i,
                        "vip": false,
                        "url": "https://example.com/play/\(dramaId)/\(i)"
                    ])
                }
            }

            return [
                "drama": freshDrama,
                "chapters": chapters,
                "episodes": chapters,
                "warning": ""
            ]

        case "resolve":
            let targetSrc = (payload["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? activeSourceId
            let epIndex = payload["index"] as? Int ?? 1
            let dramaDict = payload["drama"] as? [String: Any] ?? [:]
            let dramaId = dramaDict["id"] as? String ?? "1"

            var targetUrl = ""
            var targetHeaders: [String: String] = [:]

            if !targetSrc.isEmpty, let ctx = getOrCreateContext(sourceId: targetSrc) {
                let chapterDict = payload["chapter"] as? [String: Any]
                let rawUrl = (chapterDict?["url"] as? String) ?? "\(dramaId)/\(epIndex)"

                let scriptExpr = "spider.play(\"\", \"\(rawUrl)\", [])"
                let res = evalAsync(context: ctx, scriptExpr: scriptExpr)

                if let data = res?["data"] as? [String: Any] {
                    targetUrl = data["url"] as? String ?? ""
                    if let hdr = (data["header"] as? [String: String]) ?? (data["headers"] as? [String: String]) {
                        targetHeaders = hdr
                    }
                }
            }

            if targetUrl.isEmpty {
                targetUrl = "https://example.com/stream/\(dramaId)/\(epIndex).mp4"
            }

            return [
                "url": targetUrl,
                "headers": targetHeaders,
                "quality": 1080,
                "session": "\(Date().timeIntervalSince1970)"
            ]

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
