import Combine
import CryptoKit
import Foundation

/// 诊断故障分类枚举
public enum DiagnosticCategory: String, CaseIterable, Codable {
    case jsError = "js_error"                 // JS 脚本运行时错误或语法异常
    case dnsError = "dns_error"               // DNS 域名解析失败
    case networkOffline = "network_offline"   // 设备未连接互联网
    case networkTimeout = "network_timeout"   // 网络请求超时
    case connectionRefused = "conn_refused"   // 连接被拒绝或端口不通
    case tlsError = "tls_error"               // TLS/SSL 证书校验异常
    case httpError = "http_error"             // HTTP 服务端返回非 2xx 异常
    case businessRejected = "business_reject" // 平台服务端业务拦截/频控
    case invalidResponse = "invalid_resp"     // 返回数据结构不符合规范
    case unknown = "unknown"                  // 其他未知异常

    public var name: String {
        switch self {
        case .jsError: return "JS脚本错误"
        case .dnsError: return "DNS域名解析错误"
        case .networkOffline: return "网络未连接"
        case .networkTimeout: return "网络请求超时"
        case .connectionRefused: return "连接被拒绝"
        case .tlsError: return "SSL证书安全错误"
        case .httpError: return "HTTP服务端异常"
        case .businessRejected: return "业务风控拦截"
        case .invalidResponse: return "响应数据格式异常"
        case .unknown: return "未归类异常"
        }
    }

    public var tag: String {
        switch self {
        case .jsError: return "JS报错"
        case .dnsError: return "DNS解析错误"
        case .networkOffline: return "网络未连接"
        case .networkTimeout: return "网络超时"
        case .connectionRefused: return "连接拒绝"
        case .tlsError: return "证书错误"
        case .httpError: return "HTTP异常"
        case .businessRejected: return "风控拦截"
        case .invalidResponse: return "数据异常"
        case .unknown: return "检测失败"
        }
    }
}

public struct SourceDiagnosticEntry: Identifiable {
    public let id = UUID()
    public let at = Date()
    public let context: String
    public let stage: String
    public var host = ""
    public var status = 0
    public var businessCode = ""
    public var errorCode = ""
    public var elapsedMs = 0
    public var count: Int?
    public var category: DiagnosticCategory = .unknown
    public var errorDetail: String = ""
    public var suggestion: String = ""

    public var failed: Bool {
        !errorCode.isEmpty || category != .unknown && category != .invalidResponse
    }

    public var text: String {
        var parts = [ISO8601DateFormatter().string(from: at), "[\(context)] \(stage)"]
        if category != .unknown { parts.append("【\(category.tag)】") }
        if !host.isEmpty { parts.append(host) }
        if status > 0 { parts.append("HTTP \(status)") }
        if !businessCode.isEmpty { parts.append("业务码 \(businessCode)") }
        if !errorCode.isEmpty && errorCode != category.tag { parts.append(errorCode) }
        if elapsedMs > 0 { parts.append("\(elapsedMs)ms") }
        if let count { parts.append("\(count) 条结果") }
        if !errorDetail.isEmpty { parts.append("原因: \(errorDetail)") }
        return parts.joined(separator: " · ")
    }

    public init(
        context: String,
        stage: String,
        host: String = "",
        status: Int = 0,
        businessCode: String = "",
        errorCode: String = "",
        elapsedMs: Int = 0,
        count: Int? = nil,
        category: DiagnosticCategory = .unknown,
        errorDetail: String = "",
        suggestion: String = ""
    ) {
        self.context = context
        self.stage = stage
        self.host = host
        self.status = status
        self.businessCode = businessCode
        self.errorCode = errorCode
        self.elapsedMs = elapsedMs
        self.count = count
        self.category = category
        self.errorDetail = errorDetail
        self.suggestion = suggestion
    }
}

public final class SourceDiagnostics: ObservableObject {
    public static let shared = SourceDiagnostics()
    public let objectWillChange = ObservableObjectPublisher()
    private let lock = NSLock()
    private var records: [SourceDiagnosticEntry] = []

    public init() {}

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
                        "电视网络未能正确解析域名，请检查 Apple TV 网络设置中的 DNS（推荐设为 223.5.5.5 或 119.29.29.29）或关闭路由器广告屏蔽。"
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
                    let msg = parsed["message"] as? String ?? parsed["msg"] as? String ?? "平台业务拒绝"
                    return (
                        .businessRejected,
                        "业务拦截 (代码 \(code)): \(msg)",
                        "接口返回业务受限代码，当前游客凭据可能已过期，系统已自动重置会话。"
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
        default: category = "CONNECTION"
        }
        return "\(category):\(networkError.code)"
    }

    public func record(url: URL, context: String, elapsedMs: Int, status: Int, body: String, errorCode: String = "", error: Error? = nil) {
        guard let stage = Self.stage(for: url) else { return }
        var entry = SourceDiagnosticEntry(
            context: context,
            stage: stage,
            host: url.host ?? "",
            status: status,
            businessCode: "",
            errorCode: Self.safeCode(errorCode),
            elapsedMs: elapsedMs
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

        if entry.errorCode.isEmpty && status == 200 {
            if body.utf8.count <= 2 * 1024 * 1024, let data = body.data(using: .utf8),
                let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            {
                entry.businessCode = Self.safeCode(parsed["code"] ?? parsed["Code"] ?? parsed["status_code"])
                if !entry.businessCode.isEmpty && entry.businessCode != "0" {
                    entry.category = .businessRejected
                    entry.errorCode = "BUSINESS_REJECTED"
                    entry.errorDetail = "平台业务拦截 (代码 \(entry.businessCode))"
                    entry.suggestion = "当前游客会话受限，请稍后重试或重新检测。"
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
                } else if stage == "搜索" && !(parsed["search_tabs"] is [Any]) {
                    entry.category = .invalidResponse
                    entry.errorCode = "INVALID_RESPONSE"
                    entry.errorDetail = "搜索响应数据缺失 search_tabs 列表"
                    entry.suggestion = "接口返回了非标准短剧结构，可能需要更新 Spider 脚本。"
                }
            } else {
                entry.category = .invalidResponse
                entry.errorCode = "INVALID_RESPONSE"
                entry.errorDetail = "响应体解析 JSON 失败或数据体积超限"
                entry.suggestion = "目标接口返回非 JSON 内容，请检查是否被网页验证码拦截。"
            }
        }

        add(entry)
    }

    public static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "1.0.0")+\(info["CFBundleVersion"] as? String ?? "1")"
    }

    public static var sourceHash: String {
        SHA256.hash(data: Data(BuiltInHongguoJSContent.trimmingCharacters(in: .whitespacesAndNewlines).utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    public static func advice(_ entry: SourceDiagnosticEntry) -> String {
        if !entry.suggestion.isEmpty { return entry.suggestion }
        if entry.errorCode.hasPrefix("DNS") || entry.category == .dnsError {
            return "请检查网络 DNS 配置或路由器广告屏蔽规则，推荐将 DNS 修改为 223.5.5.5。"
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
        if entry.category == .jsError {
            return "JS 脚本执行报错，请更新至最新数据源规范脚本。"
        }
        return "请结合诊断报告中的详细失败原因与错误码进行排查。"
    }

    /// 生成完整的结构化技术诊断报告
    public var report: String {
        var lines: [String] = []
        lines.append("==================================================")
        lines.append("        糖葫芦Haw (THLRedLook) 核心技术诊断报告      ")
        lines.append("==================================================")
        lines.append("【基础环境】")
        lines.append("· 应用版本: \(Self.version)")
        lines.append("· 操作系统: tvOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("· 数据源名称: hongguo (官方内置规范源)")
        lines.append("· 源指纹 SHA256: \(Self.sourceHash)")
        lines.append("· 诊断时间: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        let failureList = entries.filter(\.failed)
        lines.append("【诊断总结与故障分析】")
        if failureList.isEmpty {
            lines.append("· 总体评估: 优秀 (全链路探测未发现异常，网络与脚本运行畅通)")
        } else {
            lines.append("· 总体评估: 异常 (共检测出 \(failureList.count) 项链路失败)")
            // 按错误类别统计归类
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
                lines.append("    状态: \(entry.failed ? "❌ 失败" : "✅ 成功") | 耗时: \(entry.elapsedMs)ms")
                if !entry.host.isEmpty { lines.append("    目标主机: \(entry.host)") }
                if entry.status > 0 { lines.append("    HTTP状态: \(entry.status)") }
                if entry.category != .unknown { lines.append("    故障分类: 【\(entry.category.tag)】\(entry.category.name)") }
                if !entry.errorDetail.isEmpty { lines.append("    失败原因: \(entry.errorDetail)") }
                if !entry.suggestion.isEmpty { lines.append("    排查建议: \(entry.suggestion)") }
            }
        }
        lines.append("==================================================")
        lines.append("声明：本报告为本地端侧闭环生成，绝不含鉴权Token、Cookie或敏感隐私数据。")
        return lines.joined(separator: "\n")
    }

    public var qrText: String {
        var recent = Array(entries.suffix(8))
        while true {
            let payload: [String: Any] = [
                "app": "THL",
                "version": Self.version,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "source": "hongguo",
                "sha256": String(Self.sourceHash.prefix(16)),
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

@MainActor
public final class SourceDiagnosticRunner: ObservableObject {
    public static let shared = SourceDiagnosticRunner()
    @Published public private(set) var running = false
    @Published public private(set) var result = "尚未检测"

    public func run() async {
        guard !running else { return }
        running = true
        result = "正在检查：网络与DNS、JS脚本引擎、游客注册、短剧搜索、选集详情…"
        let recorder = SourceDiagnostics.shared
        let context = "主动检测 " + ISO8601DateFormatter().string(from: Date())
        defer { running = false }

        let bridge = NativeBridge(diagnostics: recorder, diagnosticContext: context)
        var stage = "搜索第一页"
        do {
            let first = try await bridge.request(
                action: "catalog",
                payload: ["source": "hongguo", "query": "短剧", "page": 1]
            )
            let items = first["items"] as? [[String: Any]] ?? []
            recorder.add(SourceDiagnosticEntry(
                context: context,
                stage: stage,
                count: items.count
            ))

            let more = first["hasMore"] as? Bool == true
            if more {
                stage = "搜索分页"
                let next = try await bridge.request(
                    action: "catalog",
                    payload: ["source": "hongguo", "query": "短剧", "page": 2]
                )
                recorder.add(SourceDiagnosticEntry(
                    context: context,
                    stage: stage,
                    count: (next["items"] as? [Any])?.count ?? 0
                ))
            }

            if let drama = items.first {
                stage = "详情解析"
                let detail = try await bridge.request(action: "detail", payload: ["drama": drama])
                guard let chapters = detail["chapters"] as? [Any], !chapters.isEmpty else {
                    let err = NSError(domain: "SourceDiagnostic", code: 2, userInfo: [NSLocalizedDescriptionKey: "详情接口未返回剧集章节列表"])
                    throw err
                }
            }

            result = "检测完成：DNS网络、JS引擎、游客注册、搜索\(more ? "、分页" : "")\(items.isEmpty ? "（空结果）" : "、详情解析")全部通过"
        } catch {
            let nsErr = error as NSError
            let errorMsg = error.localizedDescription
            let cat: DiagnosticCategory
            let reason: String
            let advice: String
            if let rawCat = nsErr.userInfo["diagnosticCategory"] as? String,
               let parsedCat = DiagnosticCategory(rawValue: rawCat) {
                cat = parsedCat
                reason = errorMsg
                advice = (nsErr.userInfo["diagnosticAdvice"] as? String)
                    ?? SourceDiagnostics.advice(SourceDiagnosticEntry(context: context, stage: stage, category: cat, errorDetail: reason))
            } else {
                let isJS = errorMsg.contains("SyntaxError") || errorMsg.contains("ReferenceError") || errorMsg.contains("TypeError")
                let classified = SourceDiagnostics.classify(error: error, httpStatus: nil, body: nil, isJS: isJS)
                cat = classified.category
                reason = classified.reason
                advice = classified.suggestion
            }
            recorder.add(SourceDiagnosticEntry(
                context: context,
                stage: stage,
                errorCode: (nsErr.userInfo["diagnosticCode"] as? String) ?? cat.tag,
                category: cat,
                errorDetail: reason,
                suggestion: advice
            ))
            result = "检测失败：【\(cat.tag)】\(stage) - \(reason)"
        }
    }
}
