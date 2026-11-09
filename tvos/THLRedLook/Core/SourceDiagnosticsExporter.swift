import Foundation

// MARK: - 诊断数据导出与脱敏服务类

public final class SourceDiagnosticsExporter {
    public static func desensitizeUrl(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return "[无效地址]" }
        let visible = Set(["tab_type", "offset", "count", "is_first_enter_search", "search_source", "use_correct", "use_lynx", "version_code", "language"])
        components.user = nil
        components.password = nil
        components.fragment = nil
        components.queryItems = components.queryItems?.map { item in
            URLQueryItem(name: item.name, value: visible.contains(item.name.lowercased()) ? item.value : "[已隐藏]")
        }
        return components.string ?? "[无效地址]"
    }

    public static func responseSummary(_ body: String) -> String {
        guard !body.isEmpty else { return "" }
        guard body.utf8.count <= 12 * 1024 * 1024,
              let data = body.data(using: .utf8),
              let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return "非 JSON 响应，\(body.utf8.count) 字节"
        }
        var summary: [String: Any] = ["bytes": body.utf8.count, "keys": Array(value.keys.filter { $0.range(of: "token|cookie|authorization|password|device_id|install_id|openudid|cdid", options: [.regularExpression, .caseInsensitive]) == nil }.sorted().prefix(40))]
        summary["code"] = safeCode(value["code"] ?? value["Code"] ?? value["status_code"])
        if let tabs = value["search_tabs"] as? [[String: Any]] {
            summary["search_tabs"] = tabs.map { tab -> [String: Any] in
                let rows = tab["data"] as? [[String: Any]] ?? []
                return ["tab_type": tab["tab_type"] as? Int ?? -1,
                        "title": String((tab["title"] as? String ?? "").prefix(30)),
                        "rows": rows.count, "videos": rows.reduce(0) { $0 + (($1["video_data"] as? [Any])?.count ?? 0) },
                        "has_more": tab["has_more"] as? Bool ?? false,
                        "next_offset": tab["next_offset"] as? Int ?? 0]
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "响应摘要不可用" }
        return String(text.prefix(2000))
    }

    public static func redact(_ raw: String) -> String {
        var value = raw
        if let pattern = try? NSRegularExpression(pattern: #"(?im)(\b(?:Cookie|Set-Cookie|Authorization|Proxy-Authorization)\s*[:=]\s*)[^\r\n]+"#) {
            value = pattern.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "$1[已隐藏]")
        }
        if let pattern = try? NSRegularExpression(pattern: #"https?://[^\s<>\"']+"#) {
            for match in pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let range = Range(match.range, in: value) else { continue }
                value.replaceSubrange(range, with: desensitizeUrl(String(value[range])))
            }
        }
        if let pattern = try? NSRegularExpression(pattern: #"(?i)(\"?(?:configuration|common_key|sign_key|mLicensetStr|x[-_](?:gorgon|helios|medusa|argus|ladon)|device_id(?:_str)?|install_id(?:_str)?|iid|openudid|cdid|cookie|authorization|access_token|refresh_token|device_token|session_id|token|password|query|keyword|search_word)\"?\s*[:=]\s*)(\"[^\"]*\"|[^\s,;]+)"#) {
            value = pattern.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "$1[已隐藏]")
        }
        return value
    }

    public static func safeCode(_ raw: Any?) -> String {
        guard let raw else { return "" }
        let text = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "<null>" else { return "" }
        if text.range(of: "^[0-9A-Za-z._:-]{1,40}$", options: .regularExpression) != nil {
            return text
        }
        return "ERROR"
    }

    public static func classify(error: Error?, httpStatus: Int, body: String = "") -> (category: DiagnosticCategory, reason: String) {
        if let nsError = error as NSError? {
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                    return (.dnsError, "无法解析域名 (DNS 错误)")
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                    return (.networkOffline, "设备未连接到互联网或网络中断")
                case NSURLErrorTimedOut:
                    return (.networkTimeout, "网络请求超时 (12秒)")
                case NSURLErrorCannotConnectToHost:
                    return (.connectionRefused, "服务器拒绝连接或端口未开放")
                case NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateUntrusted,
                     NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
                     NSURLErrorClientCertificateRejected, NSURLErrorSecureConnectionFailed:
                    return (.tlsError, "SSL/TLS 安全证书验证失败")
                default:
                    return (.httpError, "网络层异常: \(nsError.localizedDescription)")
                }
            }
        }

        if httpStatus >= 400 {
            return (.httpError, "HTTP 服务端返回错误状态码: \(httpStatus)")
        }

        if !body.isEmpty {
            if body.contains("verify_code") || body.contains("captcha") || body.contains("security_check") {
                return (.businessRejected, "触发官方平台安全验证/风控拦截")
            }
            if body.contains("404 Not Found") || body.contains("502 Bad Gateway") {
                return (.httpError, "服务端代理异常报文")
            }
        }

        return (.unknown, error?.localizedDescription ?? "未知链路异常")
    }

    public static func advice(_ entry: SourceDiagnosticEntry) -> String {
        if !entry.suggestion.isEmpty { return entry.suggestion }
        if entry.errorCode.hasPrefix("LOCAL_PROFILE_") {
            return entry.errorCode == "LOCAL_PROFILE_UNAVAILABLE" ? "本机签名缓存暂不可访问，请稍后重试。" : "请更新 JS 数据源后重试，持续失败时导出诊断报告。"
        }
        if entry.errorCode.hasPrefix("DNS") || entry.category == .dnsError {
            return "检查网络 DNS 配置"
        }
        if entry.errorCode.hasPrefix("TIMEOUT") || entry.category == .networkTimeout {
            return "网络请求超时，建议切换网络代理模式或改用手机热点后重新检测。"
        }
        if entry.errorCode.hasPrefix("TLS") || entry.category == .tlsError {
            return "安全连接失败，请检查 Apple TV 设备系统时间是否准确，或关闭中间人抓包。"
        }
        if ["HTTP_403", "HTTP_429", "BUSINESS_REJECTED"].contains(entry.errorCode) || entry.category == .businessRejected {
            return "服务端拒绝或频控，建议调高请求安全间隔（如 500ms）后稍后再试。"
        }
        if entry.errorCode == "SEARCH_TAB_MISSING" {
            return "官方连接成功但没有提供短剧分类，请导出日志并对照不同网络；不能据此确认地区限制。"
        }
        if ["EMPTY_RESPONSE", "RESPONSE_NOT_UTF8"].contains(entry.errorCode) {
            return "请在同一设备用原网络和手机热点作对照，注明实际地区及代理或分流设置，并导出报告；仅凭该响应无法确认地区限制。"
        }
        if entry.category == .jsError {
            return "更新 Spider 脚本"
        }
        return "请结合诊断报告中的详细失败原因与错误码进行排查。"
    }

    public static func generateReport(
        version: String,
        sourceHash: String,
        sourceRevision: String,
        runtimeStatus: String,
        runtimeLines: [String] = [],
        networkEgress: NetworkEgressResult?,
        entries: [SourceDiagnosticEntry]
    ) -> String {
        var lines: [String] = []
        lines.append("==================================================")
        lines.append("        糖葫芦Haw (THLRedLook) 核心技术诊断报告      ")
        lines.append("==================================================")
        lines.append("【基础环境】")
        lines.append("· 应用版本: \(version)")
        lines.append("· 操作系统: tvOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("· 数据源名称: hongguo (官方内置规范源)")
        lines.append("· 源指纹 SHA256: \(sourceHash)")
        lines.append("· 数据源版本: \(sourceRevision)")
        lines.append("· 签名方式: JS 内置签名 v04.10.03")
        lines.append("· 运行源状态: \(runtimeStatus)")
        lines.append(contentsOf: runtimeLines.map { "  - " + $0 })
        lines.append("· 系统地区: \(Locale.current.identifier) · 时区: \(TimeZone.current.identifier)")
        if let networkEgress { lines.append(contentsOf: networkEgress.reportLines) }
        else { lines.append("· 出口 IP: 尚未检测，请打开数据源诊断或点击开始检测") }
        lines.append("· 诊断时间: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        let failureList = entries.filter(\.failed)
        lines.append("【诊断总结与故障分析】")
        if failureList.isEmpty {
            lines.append("· 总体评估: \(entries.isEmpty ? "尚未检测" : "记录内未发现失败；请结合已执行阶段判断")")
        } else {
            lines.append("· 总体评估: 异常 (共检测出 \(failureList.count) 项链路失败)")
            var categoryStats: [DiagnosticCategory: Int] = [:]
            for f in failureList {
                categoryStats[f.category, default: 0] += 1
            }
            for (cat, cnt) in categoryStats {
                lines.append("  - 【\(cat.tag)】: 发现 \(cnt) 次 (\(cat.name))")
            }
        }
        lines.append("")

        lines.append("【链路逐步排查记录 (最近 \(entries.count) 条)】")
        if entries.isEmpty {
            lines.append("（暂无检测记录，请先在面板点击「开始检测」）")
        } else {
            for (index, entry) in entries.enumerated() {
                lines.append("--------------------------------------------------")
                lines.append("[\(index + 1)] 阶段: \(entry.stage) | 上下文: \(entry.context)")
                lines.append("    时间: \(ISO8601DateFormatter().string(from: entry.at))")
                lines.append("    状态: \(entry.failed ? "❌ 失败" : "✅ 成功") | 耗时: \(entry.elapsedMs)ms")
                if !entry.host.isEmpty { lines.append("    目标主机: \(entry.host)") }
                if !entry.url.isEmpty { lines.append("    请求接口: \(entry.url)") }
                if !entry.method.isEmpty { lines.append("    请求方法: \(entry.method)") }
                if entry.status > 0 { lines.append("    HTTP状态: \(entry.status)") }
                if let bytes = entry.bodyBytes { lines.append("    接收正文字节数: \(bytes)") }
                if !entry.contentType.isEmpty { lines.append("    Content-Type: \(entry.contentType)") }
                if !entry.contentEncoding.isEmpty { lines.append("    Content-Encoding: \(entry.contentEncoding)") }
                if let bytes = entry.declaredBodyBytes { lines.append("    Content-Length: \(bytes)") }
                if !entry.businessCode.isEmpty { lines.append("    业务状态: \(entry.businessCode)") }
                if !entry.logId.isEmpty { lines.append("    字节 LogID: \(entry.logId)") }
                if !entry.sessionStatus.isEmpty { lines.append("    会话状态: \(entry.sessionStatus)") }
                if !entry.searchTabsSummary.isEmpty { lines.append("    搜索分类详情: \(entry.searchTabsSummary)") }
                if entry.category != .unknown { lines.append("    故障分类: 【\(entry.category.tag)】\(entry.category.name)") }
                if !entry.errorCode.isEmpty && entry.errorCode != entry.category.tag { lines.append("    特征代码: \(entry.errorCode)") }
                if !entry.errorDetail.isEmpty { lines.append("    失败原因: \(entry.errorDetail)") }
                if !entry.suggestion.isEmpty { lines.append("    排查建议: \(entry.suggestion)") }
                if !entry.responseSnippet.isEmpty {
                    lines.append("    响应结构摘要: \(entry.responseSnippet.replacingOccurrences(of: "\n", with: " "))")
                }
            }
        }
        lines.append("==================================================")
        lines.append("说明：报告在设备本地生成，请求凭据和搜索词已隐藏，响应仅保留结构摘要。")
        let full = redact(lines.joined(separator: "\n"))
        saveReportToSandbox(full)
        return full
    }

    private static func saveReportToSandbox(_ content: String) {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let logFile = cacheDir.appendingPathComponent("diagnostics_latest.log")
        try? content.write(to: logFile, atomically: true, encoding: .utf8)
    }

    public static func qrText(entries: [SourceDiagnosticEntry], version: String, sourceHash: String, egressIp: String? = nil) -> String {
        let failures = entries.filter(\.failed)
        if failures.isEmpty {
            return "THL:OK version=\(version) sha256=\(sourceHash.prefix(8)) egress=\(egressIp ?? "none")"
        }
        let categories = Set(failures.map { $0.category.tag }).sorted().joined(separator: ",")
        return "THL:FAIL version=\(version) categories=\(categories) count=\(failures.count) egress=\(egressIp ?? "none")"
    }

    public static func recordEntry(
        url: URL,
        context: String,
        elapsedMs: Int,
        status: Int,
        body: String,
        method: String = "GET",
        headers: [String: String] = [:],
        bodyBytes: Int? = nil,
        errorCode: String = "",
        error: Error? = nil
    ) -> SourceDiagnosticEntry? {
        guard let stage = SourceDiagnostics.stage(for: url) else { return nil }

        let headers = headers.reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
        let logId = headers["x-tt-logid"] ?? headers["x-tt-traceid"] ?? headers["x-ss-req-ticket"] ?? ""
        let responseSnippet = responseSummary(body)

        var entry = SourceDiagnosticEntry(
            context: context,
            stage: stage,
            host: url.host ?? "",
            url: desensitizeUrl(url.absoluteString),
            method: method,
            logId: logId,
            status: status,
            businessCode: "",
            errorCode: safeCode(errorCode),
            elapsedMs: elapsedMs,
            responseSnippet: responseSnippet,
            bodyBytes: bodyBytes ?? body.utf8.count,
            contentType: SourceDiagnostics.responseContentType(headers["content-type"] ?? ""),
            contentEncoding: SourceDiagnostics.responseEncoding(headers["content-encoding"] ?? ""),
            declaredBodyBytes: Int(headers["content-length"] ?? "").flatMap { $0 >= 0 ? $0 : nil }
        )

        let classified = SourceDiagnostics.classify(error: error, httpStatus: status, body: body)
        if error != nil || status != 200 || !errorCode.isEmpty {
            entry.category = classified.category
            entry.errorDetail = classified.reason
            entry.suggestion = classified.suggestion
            if entry.errorCode.isEmpty {
                entry.errorCode = classified.category.tag
            }
        }

        if entry.errorCode == "RESPONSE_NOT_UTF8" {
            entry.category = DiagnosticCategory.invalidResponse
            entry.errorDetail = "收到 \(entry.bodyBytes ?? 0) 字节正文，但无法按 UTF-8 解码"
            entry.suggestion = advice(entry)
        }

        if entry.errorCode.isEmpty && status == 200 {
            if body.utf8.count <= 2 * 1024 * 1024, let data = body.data(using: .utf8),
                let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            {
                entry.businessCode = safeCode(parsed["code"] ?? parsed["Code"] ?? parsed["status_code"])
                if !entry.businessCode.isEmpty && entry.businessCode != "0" {
                    entry.category = DiagnosticCategory.businessRejected
                    entry.errorCode = "BUSINESS_REJECTED"
                    entry.errorDetail = "平台业务拦截 (代码 \(entry.businessCode))"
                    entry.suggestion = "接口返回业务受限代码，请稍后重试或重新检测；仅凭业务码不能确认游客会话过期。"
                } else if stage == "游客注册" {
                    let valid = [parsed["device_id_str"], parsed["install_id_str"]].allSatisfy { value in
                        guard let string = value as? String else { return false }
                        return string.range(of: "^\\d{10,24}$", options: .regularExpression) != nil
                    }
                    if !valid {
                        entry.category = DiagnosticCategory.invalidResponse
                        entry.errorCode = "GUEST_REGISTRATION_FAILED"
                        entry.errorDetail = "游客注册响应缺少有效 device_id 或 install_id"
                        entry.suggestion = "注册接口响应异常，可能遭遇设备级频控。"
                    }
                } else if stage == "搜索" {
                    if let tabs = parsed["search_tabs"] as? [[String: Any]] {
                        let tabDescs = tabs.map { tab -> String in
                            let tType = tab["tab_type"] as? Int ?? -1
                            let title = tab["title"] as? String ?? ""
                            let tabName = tab["tab_name"] as? String ?? ""
                            let label = title.isEmpty ? tabName : title
                            let dataCount = (tab["data"] as? [Any])?.count ?? 0
                            return "\(tType):\(label)(\(dataCount)条)"
                        }
                        let hasDrama = tabs.contains { tab in
                            let t = tab["tab_type"] as? Int ?? -1
                            let title = tab["title"] as? String ?? ""
                            return t == 29 || title.contains("剧")
                        }
                        entry.searchTabsSummary = "分类列表[\(tabs.count)]: [" + tabDescs.joined(separator: ", ") + "]"
                        if !hasDrama {
                            entry.searchTabsSummary += " (缺少 29:剧集 分类)"
                            let videoCount = tabs.reduce(0) { total, tab in
                                total + ((tab["data"] as? [[String: Any]]) ?? []).reduce(0) { $0 + (($1["video_data"] as? [Any])?.count ?? 0) }
                            }
                            entry.suggestion = "HTTP 与业务码正常，但缺少短剧分类。请扫码导出报告，对比同一设备不同网络的结果；仅凭此响应无法确定是否存在地区限制。"
                            if videoCount == 0 {
                                entry.category = DiagnosticCategory.invalidResponse
                                entry.errorCode = "SEARCH_TAB_MISSING"
                                entry.errorDetail = "官方搜索未提供短剧分类，返回的分类中也没有短剧数据"
                            }
                        }
                    } else {
                        entry.category = DiagnosticCategory.invalidResponse
                        entry.errorCode = "INVALID_RESPONSE"
                        entry.errorDetail = "搜索响应数据缺失 search_tabs 列表"
                        entry.suggestion = "接口返回了非标准短剧结构，可能需要更新 Spider 脚本。"
                    }
                }
            } else {
                entry.category = .invalidResponse
                entry.errorCode = "INVALID_RESPONSE"
                let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmedBody.isEmpty {
                    entry.errorCode = "EMPTY_RESPONSE"
                    entry.errorDetail = "响应体为空"
                    entry.suggestion = advice(entry)
                } else if trimmedBody.contains("<html") || trimmedBody.contains("<!doctype") {
                    entry.errorDetail = "接口返回了 HTML 网页而非 JSON 数据"
                    entry.suggestion = "可能遭遇防爬验证码或网关拦截，请检查网络代理环境。"
                } else {
                    entry.errorDetail = "响应体解析 JSON 失败或数据格式不符合预期"
                    entry.suggestion = "服务端返回了非标准数据，请查看报文详情进行排查。"
                }
            }
        }
        return entry
    }

    public static func qrText(entries: [SourceDiagnosticEntry], version: String, sourceHash: String) -> String {
        var recent = Array(entries.suffix(8))
        while true {
            let payload: [String: Any] = [
                "app": "THL",
                "version": version,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "source": "hongguo",
                "sha256": String(sourceHash.prefix(16)),
                "at": ISO8601DateFormatter().string(from: Date()),
                "recent": recent.map { entry -> [String: Any] in
                    var dict: [String: Any] = [
                        "stage": entry.stage,
                        "status": entry.status,
                        "fail": entry.failed,
                        "cat": entry.category.tag,
                        "ms": entry.elapsedMs
                    ]
                    if !entry.errorDetail.isEmpty { dict["reason"] = entry.errorDetail }
                    return dict
                },
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                return ""
            }
            if data.count <= 2200 || recent.isEmpty { return String(decoding: data, as: UTF8.self) }
            recent.removeFirst()
        }
    }

}
