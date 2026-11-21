import Foundation
import JavaScriptCore

final class JSDramaParserService {
    private let diagnostics: SourceDiagnostics
    private let diagnosticContext: String
    private let timeProvider: @Sendable () -> TimeInterval
    private let deviceDefaults: UserDefaults
    private let persistentDeviceSession: Bool

    init(
        diagnostics: SourceDiagnostics = .shared,
        diagnosticContext: String = "日常使用",
        timeProvider: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
        deviceDefaults: UserDefaults = .standard,
        persistentDeviceSession: Bool = true
    ) {
        self.diagnostics = diagnostics
        self.diagnosticContext = diagnosticContext
        self.timeProvider = timeProvider
        self.deviceDefaults = deviceDefaults
        self.persistentDeviceSession = persistentDeviceSession
    }

    func spiderExpression(_ method: String, _ arguments: [Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: arguments, options: [.fragmentsAllowed])
        return "spider.\(method).apply(spider, \(String(decoding: data, as: UTF8.self)))"
    }

    func mapVodToDrama(vod: [String: Any], sourceId: String) -> [String: Any] {
        let vid = vod["vod_id"] as? String ?? "\(vod["id"] ?? UUID().uuidString)"
        let title = (vod["vod_name"] as? String) ?? (vod["title"] as? String) ?? "短剧 \(vid)"
        var cover = (vod["vod_pic"] as? String) ?? (vod["cover"] as? String) ?? (vod["cover_url"] as? String) ?? (vod["series_cover"] as? String) ?? ""
        cover = cover.trimmingCharacters(in: .whitespacesAndNewlines)
        if cover.hasPrefix("//") { cover = "https:" + cover }
        let desc = (vod["vod_content"] as? String) ?? (vod["desc"] as? String) ?? ""
        let remark = (vod["vod_remarks"] as? String) ?? (vod["remarks"] as? String) ?? ""
        let year = (vod["vod_year"] as? String) ?? ""

        var epCount = 0
        if let match = remark.range(of: "(\\d+)", options: .regularExpression) {
            epCount = Int(remark[match]) ?? 0
        }

        let isHongguo = sourceId.isEmpty || sourceId == "hongguo" || vid.hasPrefix("hongguo:")
        var rawTags: [String] = []
        if let tagList = vod["tags"] as? [String] {
            rawTags = tagList
        } else if let tagStr = (vod["vod_tag"] as? String) ?? (vod["tags"] as? String) {
            rawTags = tagStr.components(separatedBy: CharacterSet(charactersIn: "·,，/ ")).filter { !$0.isEmpty }
        }
        let cleanTags = rawTags.filter { t in
            let lower = t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !lower.contains("vip") && !lower.contains("付费")
        }

        return [
            "id": vid.hasPrefix("\(sourceId):") ? vid : "\(sourceId):\(vid)",
            "source": sourceId,
            "sourceId": vid.hasPrefix("\(sourceId):") ? String(vid.dropFirst(sourceId.count + 1)) : vid,
            "title": title,
            "description": desc,
            "cover": cover,
            "episodes": vod["vod_episodes"] as? Int ?? epCount,
            "category": vod["vod_category"] as? String ?? "短剧",
            "heat": vod["vod_heat"] as? String ?? "",
            "views": vod["vod_views"] as? String ?? "",
            "onlineDate": year,
            "tags": isHongguo ? cleanTags : rawTags,
            "releaseStatus": vod["vod_release_status"] as? String ?? remark,
            "vip": isHongguo ? false : (vod["vip"] as? Bool ?? false)
        ]
    }

    func playbackFailure(
        code: String,
        message: String,
        episode: Int,
        httpTrace: HttpTraceHolder,
        successfulPlaybackResolves: Int,
        lastSuccessfulPlaybackAt: TimeInterval?
    ) -> NSError {
        let trace = httpTrace.snapshot
        let upstream = ["EMPTY_RESPONSE", "RESPONSE_NOT_UTF8"].contains(code) ? diagnostics.entries.last {
            $0.context == diagnosticContext && $0.errorCode == code && $0.stage == "播放解析"
        } : nil
        let category: DiagnosticCategory
        let description: String
        if code.hasPrefix("LOCAL_PROFILE_") {
            category = .configuration
            description = code == "LOCAL_PROFILE_UNAVAILABLE" ? "本机签名缓存暂不可访问，请稍后重试" : "数据源签名配置不可用，请更新数据源后重试"
        } else if code == "MEDIA_URL_EXPIRED" {
            category = .invalidResponse
            description = "本集媒体地址已经过期，请重新获取"
        } else if code.hasPrefix("MEDIA_HTTP_") {
            category = .httpError
            description = "本集媒体节点拒绝当前地址或暂不可用"
        } else if code == "HTTP_429" {
            category = .httpError
            description = "官方播放接口请求过于频繁，请稍后再试"
        } else if code.hasPrefix("HTTP_") {
            category = .httpError
            description = "官方播放接口请求失败"
        } else if code.hasPrefix("DNS") { category = .dnsError; description = "播放接口域名解析失败" }
        else if code.hasPrefix("TIMEOUT") || code == "ETIMEDOUT" { category = .networkTimeout; description = "播放接口请求超时" }
        else if ["BUSINESS_REJECTED", "SECURITY_BLOCKED"].contains(code) { category = .businessRejected; description = "官方播放接口暂时拒绝当前请求" }
        else if code == "EMPTY_RESPONSE" { category = .invalidResponse; description = "官方播放接口连接成功，但没有返回播放数据" }
        else if code == "RESPONSE_NOT_UTF8" { category = .invalidResponse; description = "官方播放接口返回了无法解码的数据" }
        else { category = .invalidResponse; description = "官方暂未返回可用的当前分集播放流" }
        let detail = SourceDiagnostics.redact(message.isEmpty ? description : message)
        let created = httpTrace.guestSnapshot.createdAt
        let age = created > 0 ? String(max(0, Int(timeProvider() - created))) + "秒" : "未记录"
        let lastSuccess = lastSuccessfulPlaybackAt.map { String(max(0, Int(timeProvider() - $0))) + "秒前" } ?? "本次运行尚未成功"
        let sessionStatus = "游客会话创建距今：\(age)；本桥接成功取流：\(successfulPlaybackResolves)次；最近成功：\(lastSuccess)"
        let defaultAdvice = ["EMPTY_RESPONSE", "RESPONSE_NOT_UTF8"].contains(code)
            ? "请在同一设备用原网络和手机热点作对照，注明实际地区及代理或分流设置，并导出报告；仅凭该响应无法确认地区限制。"
            : "请保留当前剧集与集数，并在设置的数据源诊断中扫码导出报告。"
        let advice = code.hasPrefix("LOCAL_PROFILE_") ? description : ((upstream?.suggestion.isEmpty == false) ? upstream?.suggestion : defaultAdvice)!
        diagnostics.add(SourceDiagnosticEntry(context: diagnosticContext, stage: "播放取流 第\(episode)集", host: upstream?.host ?? URL(string: trace.url)?.host ?? "", url: upstream?.url ?? trace.url, method: upstream?.method ?? trace.method, logId: upstream?.logId ?? trace.logId, status: upstream?.status ?? trace.status, errorCode: code, category: category, errorDetail: detail, suggestion: advice, responseSnippet: upstream?.responseSnippet ?? trace.snippet, sessionStatus: sessionStatus, bodyBytes: upstream?.bodyBytes, contentType: upstream?.contentType ?? "", contentEncoding: upstream?.contentEncoding ?? "", declaredBodyBytes: upstream?.declaredBodyBytes))
        return NSError(domain: "CatPawOpen.Playback", code: -2, userInfo: [NSLocalizedDescriptionKey: detail + "（" + code + "）", "diagnosticCode": code, "diagnosticCategory": category.rawValue, "diagnosticAdvice": advice, "diagnosticSession": sessionStatus])
    }

    func parseCategories(ctx: JSContext, targetSrc: String, evalAsync: (JSContext, String) async -> [String: Any]?) async throws -> [String: Any] {
        let res = await evalAsync(ctx, targetSrc == "hongguo" ? "spider.home(true)" : "spider.home()")
        guard res?["ok"] as? Bool == true else {
            throw SourceAPIError.sourceUnavailable(res?["error"] as? String ?? "分类请求失败，请重试")
        }
        var items: [[String: Any]] = targetSrc == "hongguo" ? [] : [["id": "", "name": "全部"]]

        if let data = res?["data"] as? [String: Any],
           let classes = (data["class"] as? [[String: Any]]) ?? (data["classes"] as? [[String: Any]]) {
            for c in classes {
                let tid = c["type_id"] as? String ?? ""
                let tname = c["type_name"] as? String ?? tid
                if !tid.isEmpty { items.append(["id": tid, "name": tname]) }
            }
        }
        guard !items.isEmpty else { throw SourceAPIError.parseError("未返回找剧分类") }
        return ["items": items]
    }

    func parseCatalog(
        ctx: JSContext,
        targetSrc: String,
        payload: [String: Any],
        httpTrace: HttpTraceHolder,
        evalAsync: (JSContext, String) async -> [String: Any]?
    ) async throws -> [String: Any] {
        let query = (payload["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cat = payload["category"] as? String ?? ""
        let pg = payload["page"] as? Int ?? 1

        if !query.isEmpty {
            let scriptExpr = try spiderExpression("search", [query, false, pg])
            let evaluated = await evalAsync(ctx, scriptExpr)
            guard let res = evaluated, res["ok"] as? Bool == true else {
                let errMsg = evaluated?["error"] as? String ?? "JS 执行无响应或超时"
                let rawCat = evaluated?["category"] as? String ?? ""
                let rawCode = evaluated?["code"] as? String ?? ""
                let errCat: DiagnosticCategory
                if rawCode.hasPrefix("LOCAL_PROFILE_") {
                    errCat = .configuration
                } else if let parsedCat = DiagnosticCategory(rawValue: rawCat), rawCat != "js_error" {
                    errCat = parsedCat
                } else if errMsg.contains("网络") || errMsg.contains("DNS") {
                    errCat = .dnsError
                } else if ["SEARCH_TAB_MISSING", "INVALID_SEARCH_CURSOR", "INVALID_RESPONSE"].contains(rawCode) {
                    errCat = .invalidResponse
                } else if rawCode == "SEARCH_REJECTED" || rawCode == "BUSINESS_REJECTED" || rawCode == "GUEST_REGISTRATION_FAILED" || errMsg.contains("官方搜索") || errMsg.contains("官方会话") {
                    errCat = .businessRejected
                    if persistentDeviceSession { deviceDefaults.set("", forKey: "thl_tv_hongguo_device_session") }
                    ctx.evaluateScript("delete globalThis.__hongguoCachedDevice; if (typeof Ae !== 'undefined') Ae = null;")
                } else {
                    errCat = .jsError
                }
                let errDetail = "搜索执行失败: \(errMsg)"
                let advice = SourceDiagnostics.advice(SourceDiagnosticEntry(context: diagnosticContext, stage: "搜索执行", errorCode: rawCode, category: errCat, errorDetail: errDetail))
                let trace = httpTrace.snapshot
                let hasCached = persistentDeviceSession && !(deviceDefaults.string(forKey: "thl_tv_hongguo_device_session") ?? "").isEmpty
                let sessionStatus = hasCached ? "使用本地缓存设备凭据" : "全新游客会话"
                diagnostics.add(SourceDiagnosticEntry(
                    context: diagnosticContext, stage: "搜索执行", host: URL(string: trace.url)?.host ?? "reading.snssdk.com",
                    url: trace.url, method: trace.method, logId: trace.logId, status: trace.status,
                    errorCode: rawCode.isEmpty ? errCat.tag : rawCode, category: errCat, errorDetail: errMsg,
                    suggestion: advice, responseSnippet: trace.snippet, searchTabsSummary: trace.tabsSummary, sessionStatus: sessionStatus
                ))
                throw NSError(domain: "CatPawOpen", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: errMsg,
                    "diagnosticCode": rawCode,
                    "diagnosticAdvice": advice
                ])
            }
            var searchItems: [[String: Any]] = []
            var searchHasMore = false
            if let data = res["data"] as? [String: Any] {
                let pageCount = (data["pagecount"] as? Int) ?? (data["pageCount"] as? Int) ?? pg
                searchHasMore = pg < pageCount
                let list = data["list"] as? [[String: Any]] ?? []
                for vod in list { searchItems.append(mapVodToDrama(vod: vod, sourceId: targetSrc)) }
            } else if let list = res["data"] as? [[String: Any]] {
                for vod in list { searchItems.append(mapVodToDrama(vod: vod, sourceId: targetSrc)) }
            }
            return ["items": searchItems, "hasMore": searchHasMore, "page": pg]
        }

        let scriptExpr = try spiderExpression("category", [cat, pg, false, ["initialBatch": 12]])
        let res = await evalAsync(ctx, scriptExpr)
        guard res?["ok"] as? Bool == true else {
            throw SourceAPIError.sourceUnavailable(res?["error"] as? String ?? "发现数据请求失败，请重试")
        }

        var dramas: [[String: Any]] = []
        var hasMore = false
        if let data = res?["data"] as? [String: Any] {
            let list = data["list"] as? [[String: Any]] ?? []
            for vod in list { dramas.append(mapVodToDrama(vod: vod, sourceId: targetSrc)) }
            let pageCount = (data["pagecount"] as? Int) ?? (data["pageCount"] as? Int) ?? 1
            hasMore = data["hasMore"] as? Bool ?? (pg < pageCount)
        }
        return ["items": dramas, "hasMore": hasMore, "page": pg]
    }

    func parseDetail(
        ctx: JSContext,
        targetSrc: String,
        dramaDict: [String: Any],
        dramaId: String,
        evalAsync: (JSContext, String) async -> [String: Any]?
    ) async throws -> [String: Any] {
        let scriptExpr = try spiderExpression("detail", [dramaId])
        let evaluated = await evalAsync(ctx, scriptExpr)
        guard let res = evaluated, res["ok"] as? Bool == true else {
            let errMsg = evaluated?["error"] as? String ?? "详情解析无响应或异常"
            let errCat = DiagnosticCategory(rawValue: evaluated?["category"] as? String ?? "") ?? (errMsg.contains("网络") ? .dnsError : .jsError)
            let advice = SourceDiagnostics.advice(SourceDiagnosticEntry(context: diagnosticContext, stage: "详情解析", category: errCat, errorDetail: errMsg))
            diagnostics.add(SourceDiagnosticEntry(context: diagnosticContext, stage: "详情解析", errorCode: errCat.tag, category: errCat, errorDetail: errMsg, suggestion: advice))
            throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "【\(errCat.tag)】\(errMsg)"])
        }

        var freshDrama = dramaDict
        var chapters: [[String: Any]] = []

        if let data = res["data"] as? [String: Any] {
            let vod: [String: Any]
            if let list = data["list"] as? [[String: Any]], let first = list.first {
                vod = first
            } else if let v = data["vod"] as? [String: Any] {
                vod = v
            } else {
                vod = data
            }

            let mapped = vod["vod_id"] != nil || vod["id"] != nil ? mapVodToDrama(vod: vod, sourceId: targetSrc) : [:]
            for (k, v) in mapped {
                if let str = v as? String, !str.isEmpty { freshDrama[k] = str }
                else if let num = v as? Int, num > 0 { freshDrama[k] = num }
                else if let b = v as? Bool { freshDrama[k] = b }
                else if let arr = v as? [String] { freshDrama[k] = arr }
                else if freshDrama[k] == nil { freshDrama[k] = v }
            }

            let isHongguo = targetSrc.isEmpty || targetSrc == "hongguo" || (freshDrama["id"] as? String ?? "").hasPrefix("hongguo:")
            if isHongguo {
                freshDrama["vip"] = false
                if let currentTags = freshDrama["tags"] as? [String] {
                    freshDrama["tags"] = currentTags.filter { t in
                        let lower = t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        return !lower.contains("vip") && !lower.contains("付费")
                    }
                }
            }

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
        return ["drama": freshDrama, "chapters": chapters, "episodes": chapters, "warning": ""]
    }
}
