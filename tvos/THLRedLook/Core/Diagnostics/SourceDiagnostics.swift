import Combine
import CryptoKit
import Foundation

public final class SourceDiagnostics: ObservableObject {
    public static let shared = SourceDiagnostics()
    public let objectWillChange = ObservableObjectPublisher()
    private let lock = NSLock()
    private var records: [SourceDiagnosticEntry] = []
    private var sourceRuntimes: [String: (hash: String, ready: Bool, importedVersion: String?)] = [:]
    private var networkResult: NetworkEgressResult?
    @MainActor private var networkTask: Task<Void, Never>?

    public init() {}

    public func registerSourceRuntime(context: String, script: String, ready: Bool, importedVersion: String? = nil) {
        let hash = Self.fingerprint(script)
        lock.lock()
        sourceRuntimes[context] = (hash, ready, importedVersion)
        lock.unlock()
        NSLog("[Source] app=%@ context=%@ sha256=%@ ready=%d bundleMatch=%d", Self.version, context, hash, ready ? 1 : 0, hash == Self.sourceHash ? 1 : 0)
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    public static func fingerprint(_ script: String) -> String {
        SHA256.hash(data: Data(script.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static var sourceManifest: [String: String] {
        guard let url = Bundle.main.url(forResource: "hongguo-source", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return value
    }

    public static var sourceRevision: String {
        "应用提交 " + String((sourceManifest["appCommit"] ?? "未记录").prefix(7)) + " · JS " + String(sourceHash.prefix(12)) + " · 源提交 " + (sourceManifest["sourceCommit"] ?? "未记录")
    }

    public static var sourceBundleStatus: String {
        sourceManifest["sha256"] == sourceHash ? "本包 JS 校验通过" : "本包 JS 版本信息缺失或校验异常"
    }

    public var sourceRuntimeLines: [String] {
        lock.lock()
        let values = sourceRuntimes
        lock.unlock()
        return values.keys.sorted().map { key in
            let value = values[key]!
            return key + " · SHA256 " + value.hash + " · " + (value.ready ? "已加载" : "加载失败") +
                (value.importedVersion.map { " · 导入版本 " + Self.redact(String($0.prefix(128))) } ?? "")
        }
    }

    public var sourceRuntimeStatus: String {
        lock.lock()
        let values = Array(sourceRuntimes.values)
        lock.unlock()
        if values.isEmpty { return "运行 JS 尚未加载" }
        guard values.allSatisfy({ $0.ready && ($0.hash == Self.sourceHash || $0.importedVersion != nil) }) else {
            return "运行 JS 加载或版本校验异常，请导出诊断"
        }
        return values.contains { $0.importedVersion != nil } ? "已加载导入的更新版 JS" : "运行 JS 与本包一致"
    }

    public var networkEgress: NetworkEgressResult? {
        lock.lock()
        defer { lock.unlock() }
        return networkResult
    }

    private func saveNetworkEgress(_ value: NetworkEgressResult) {
        lock.lock()
        networkResult = value
        lock.unlock()
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    @MainActor public func refreshNetworkEgress(force: Bool = false, using lookup: NetworkEgressLookup? = nil) async {
        if let networkTask { await networkTask.value; return }
        if !force, let value = networkEgress, Date().timeIntervalSince(value.at) < (value.ip.isEmpty ? 30 : 300) { return }
        let task = Task { self.saveNetworkEgress(await (lookup ?? NetworkEgressLookup()).lookup()) }
        networkTask = task
        await task.value
        networkTask = nil
    }

    public var entries: [SourceDiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    public func add(_ entry: SourceDiagnosticEntry) {
        lock.lock()
        records.append(entry)
        if records.count > 60 { records.removeFirst(records.count - 60) }
        lock.unlock()
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    public func clear() {
        lock.lock()
        records.removeAll()
        lock.unlock()
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    public static func safeCode(_ value: Any?) -> String {
        guard let value else { return "" }
        let code = String(describing: value)
        return code.range(of: "^-?[A-Za-z0-9_.:-]{1,64}$", options: .regularExpression) != nil
            && code.range(of: "\\d{10,}", options: .regularExpression) == nil ? code : ""
    }

    public static func stage(for url: URL) -> String? {
        let host = url.host ?? ""
        if host == "log.snssdk.com"
            && url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "service/2/device_register"
        {
            return "游客注册"
        }
        if host == "reading.snssdk.com" && url.path == "/reading/bookapi/search/tab/v" { return "搜索" }
        if host == "reading.snssdk.com" {
            switch url.path {
            case "/reading/bookapi/search/cue/v": return "猜你想搜"
            case "/reading/bookapi/search/suggest/v": return "搜索联想"
            case "/reading/bookapi/plan/v": return "榜单"
            case "/reading/bookapi/bookmall/tab/v": return "推荐"
            case "/reading/bookapi/bookmall/cell/change/v": return "列表分页"
            default: break
            }
        }
        if host.hasSuffix(".fqnovel.com") || host == "reading.snssdk.com" {
            if url.path.contains("/video_detail/") { return "详情" }
            if url.path.contains("/video_model/") || url.path.contains("/multi_video_model/") { return "播放解析" }
            if url.path.hasPrefix("/novel/commentapi/comment/list/") { return "弹幕" }
        }
        if host.contains("lf3-shortplay-tos.snssdk.com") { return "CDN网络连通" }
        return nil
    }

    /// 智能分析网络或脚本错误，准确归类具体原因并给出排查建议
    public static func classify(error: Error?, httpStatus: Int?, body: String?, isJS: Bool = false) -> (category: DiagnosticCategory, reason: String, suggestion: String) {
        if isJS {
            let desc = error?.localizedDescription ?? "JS 运行时执行异常"
            return (
                .jsError,
                "JS 执行报错: \(desc)",
                "数据源 Spider 脚本语法异常或调用了未支持的 API，请检查 JS 文件或更新至最新数据源规范。"
            )
        }

        if let error = error {
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain {
                switch nsErr.code {
                case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                    return (
                        .dnsError,
                        "DNS 解析失败 (\(nsErr.code)): 无法找到目标主机 IP 地址",
                        "电视网络未能解析域名，请检查当前网络的 DNS 与路由器屏蔽规则，并用手机热点作对照。"
                    )
                case NSURLErrorNotConnectedToInternet:
                    return (
                        .networkOffline,
                        "网络未连接 (\(nsErr.code)): 设备未连接到互联网",
                        "请检查 Apple TV 的 Wi-Fi 或有线网络连接，确保路由器能正常访问外网。"
                    )
                case NSURLErrorTimedOut:
                    return (
                        .networkTimeout,
                        "网络请求超时 (\(nsErr.code)): 等待服务器响应超时",
                        "服务器或 CDN 节点响应缓慢，建议切换网络代理模式为「直连高速」或更换手机热点测试。"
                    )
                case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                    return (
                        .connectionRefused,
                        "连接失败 (\(nsErr.code)): 无法建立 TCP 连接或连接意外中断",
                        "目标服务器端口无法连接或受到防火墙阻拦，请检查局域网网关或旁路代理服务。"
                    )
                case -1206 ... -1200:
                    return (
                        .tlsError,
                        "TLS/SSL 证书错误 (\(nsErr.code)): 安全传输握手失败",
                        "无法建立安全 HTTPS 连接，请核对 Apple TV 的系统日期与时间是否准确，或关闭网络中间人代理。"
                    )
                default:
                    return (
                        .unknown,
                        "网络传输错误 (\(nsErr.code)): \(nsErr.localizedDescription)",
                        "请尝试重启网络或切换网络环境后重试。"
                    )
                }
            } else {
                let desc = error.localizedDescription
                if desc.contains("ReferenceError") || desc.contains("TypeError") || desc.contains("SyntaxError") || desc.contains("JavaScript") {
                    return (
                        .jsError,
                        "JS 异常: \(desc)",
                        "脚本内部发生异常，请检查数据源脚本逻辑。"
                    )
                }
            }
        }

        if let status = httpStatus, status > 0 && status != 200 {
            switch status {
            case 403:
                return (
                    .businessRejected,
                    "HTTP 403: 访问被拒绝，触发防盗链或 IP 限制",
                    "平台拒绝了当前设备的请求，建议稍后重试，或在设置中调高「请求防封安全间隔」（如 500ms）。"
                )
            case 429:
                return (
                    .businessRejected,
                    "HTTP 429: 请求过于频繁，触发服务商限流",
                    "短时间内请求过多触发平台频控，请等待 1-2 分钟，或在设置中降低并发度（建议 2-3 线程）。"
                )
            case 500, 502, 503, 504:
                return (
                    .httpError,
                    "HTTP \(status): 服务端或网关故障",
                    "影视源官方服务器或 CDN 节点临时维护中，建议稍后重试。"
                )
            default:
                return (
                    .httpError,
                    "HTTP \(status) 异常状态响应",
                    "服务器返回了非预期的状态码，请检查网络配置或数据源。"
                )
            }
        }

        if let body = body, !body.isEmpty {
            if body.utf8.count <= 2 * 1024 * 1024, let data = body.data(using: .utf8),
               let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let code = Self.safeCode(parsed["code"] ?? parsed["Code"] ?? parsed["status_code"])
                if !code.isEmpty && code != "0" {
                    return (
                        .businessRejected,
                        "业务拦截 (代码 \(code))",
                        "接口返回业务受限代码，请稍后重试并导出诊断；仅凭业务码不能确认游客会话过期。"
                    )
                }
            }
        }

        return (.unknown, "未知异常", "请查看技术报告中的详细堆栈并向技术支持反馈。")
    }

    public static func networkCode(_ error: Error?) -> String {
        guard let error else { return "" }
        let networkError = error as NSError
        guard networkError.domain == NSURLErrorDomain else { return "NETWORK_ERROR" }
        let category: String
        switch networkError.code {
        case NSURLErrorTimedOut: category = "TIMEOUT"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: category = "DNS"
        case NSURLErrorNotConnectedToInternet: category = "OFFLINE"
        case NSURLErrorCancelled: category = "CANCELLED"
        case -1206 ... -1200: category = "TLS"
        default: category = "NETWORK"
        }
        return "\(category)_\(networkError.code)"
    }

    public func recordNetwork(
        context: String,
        stage: String,
        url: URL,
        method: String,
        headers: [String: String],
        body: String,
        status: Int,
        elapsedMs: Int,
        logId: String = "",
        errorCode: String = "",
        error: Error? = nil,
        bodyBytes: Int? = nil
    ) {
        let snippet = Self.responseSummary(body)
        let responseSnippet = snippet.isEmpty ? "" : snippet

        var entry = SourceDiagnosticEntry(
            context: context,
            stage: stage,
            host: url.host ?? "",
            url: Self.desensitizeUrl(url.absoluteString),
            method: method,
            logId: logId,
            status: status,
            businessCode: "",
            errorCode: Self.safeCode(errorCode),
            elapsedMs: elapsedMs,
            responseSnippet: responseSnippet,
            bodyBytes: bodyBytes ?? body.utf8.count,
            contentType: Self.responseContentType(headers["content-type"] ?? ""),
            contentEncoding: Self.responseEncoding(headers["content-encoding"] ?? ""),
            declaredBodyBytes: Int(headers["content-length"] ?? "").flatMap { $0 >= 0 ? $0 : nil }
        )

        // 智能分类与失败原因分析
        let classified = Self.classify(error: error, httpStatus: status, body: body)
        if error != nil || status != 200 || !errorCode.isEmpty {
            entry.category = classified.category
            entry.errorDetail = classified.reason
            entry.suggestion = classified.suggestion
            if entry.errorCode.isEmpty {
                entry.errorCode = classified.category.tag
            }
        }

        if entry.errorCode == "RESPONSE_NOT_UTF8" {
            entry.category = .invalidResponse
            entry.errorDetail = "收到 \(entry.bodyBytes ?? 0) 字节正文，但无法按 UTF-8 解码"
            entry.suggestion = ""
            entry.suggestion = Self.advice(entry)
        }

        if entry.errorCode.isEmpty && status == 200 {
            if body.utf8.count <= 2 * 1024 * 1024, let data = body.data(using: .utf8),
                let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            {
                entry.businessCode = Self.safeCode(parsed["code"] ?? parsed["Code"] ?? parsed["status_code"])
                if !entry.businessCode.isEmpty && entry.businessCode != "0" {
                    entry.category = .businessRejected
                    entry.errorCode = "BUSINESS_REJECTED"
                    entry.errorDetail = "平台业务拦截 (代码 \(entry.businessCode))"
                    entry.suggestion = "接口返回业务受限代码，请稍后重试或重新检测；仅凭业务码不能确认游客会话过期。"
                } else if stage == "游客注册" {
                    let valid = [parsed["device_id_str"], parsed["install_id_str"]].allSatisfy { value in
                        guard let string = value as? String else { return false }
                        return string.range(of: "^\\d{10,24}$", options: .regularExpression) != nil
                    }
                    if !valid {
                        entry.category = .invalidResponse
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
                                entry.category = .invalidResponse
                                entry.errorCode = "SEARCH_TAB_MISSING"
                                entry.errorDetail = "官方搜索未提供短剧分类，返回的分类中也没有短剧数据"
                            }
                        }
                    } else {
                        entry.category = .invalidResponse
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
                    entry.suggestion = Self.advice(entry)
                } else if trimmedBody.contains("<html") || trimmedBody.contains("<!doctype") {
                    entry.errorDetail = "接口返回了 HTML 网页而非 JSON 数据"
                    entry.suggestion = "可能遭遇防爬验证码或网关拦截，请检查网络代理环境。"
                } else {
                    entry.errorDetail = "响应体解析 JSON 失败或数据格式不符合预期"
                    entry.suggestion = "服务端返回了非标准数据，请查看报文详情进行排查。"
                }
            }
        }

        add(entry)
    }

    static func responseContentType(_ raw: String) -> String {
        let value = raw.split(separator: ";", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return value.count <= 100 && value.range(of: "^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$", options: .regularExpression) != nil ? value : ""
    }

    static func responseEncoding(_ raw: String) -> String {
        let values = raw.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !values.isEmpty && values.count <= 4 && values.allSatisfy { ["gzip", "deflate", "br", "identity", "zstd"].contains($0) } ? values.joined(separator: ", ") : ""
    }

    public static func desensitizeUrl(_ raw: String) -> String {
        SourceDiagnosticsExporter.desensitizeUrl(raw)
    }

    public static func responseSummary(_ body: String) -> String {
        SourceDiagnosticsExporter.responseSummary(body)
    }

    public static func redact(_ raw: String) -> String {
        SourceDiagnosticsExporter.redact(raw)
    }

    public static func advice(_ entry: SourceDiagnosticEntry) -> String {
        SourceDiagnosticsExporter.advice(entry)
    }

    public static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "1.0.0")+\(info["CFBundleVersion"] as? String ?? "1")"
    }

    public static var sourceHash: String {
        fingerprint(BuiltInHongguoJSContent)
    }

    public func record(
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
    ) {
        if let entry = SourceDiagnosticsExporter.recordEntry(
            url: url,
            context: context,
            elapsedMs: elapsedMs,
            status: status,
            body: body,
            method: method,
            headers: headers,
            bodyBytes: bodyBytes,
            errorCode: errorCode,
            error: error
        ) {
            add(entry)
        }
    }

    public var report: String {
        SourceDiagnosticsExporter.generateReport(
            version: Self.version,
            sourceHash: Self.sourceHash,
            sourceRevision: Self.sourceRevision,
            runtimeStatus: self.sourceRuntimeStatus,
            runtimeLines: self.sourceRuntimeLines,
            networkEgress: self.networkEgress,
            entries: self.entries
        )
    }

    public var qrText: String {
        SourceDiagnosticsExporter.qrText(entries: entries, version: Self.version, sourceHash: Self.sourceHash, egressIp: self.networkEgress?.ip)
    }
}

