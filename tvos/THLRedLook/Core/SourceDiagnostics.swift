import Combine
import CryptoKit
import Foundation

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
    public var failed: Bool { !errorCode.isEmpty }
    public var text: String {
        var parts = [ISO8601DateFormatter().string(from: at), "[\(context)] \(stage)"]
        if !host.isEmpty { parts.append(host) }
        if status > 0 { parts.append("HTTP \(status)") }
        if !businessCode.isEmpty { parts.append("业务码 \(businessCode)") }
        if !errorCode.isEmpty { parts.append(errorCode) }
        if elapsedMs > 0 { parts.append("\(elapsedMs)ms") }
        if let count { parts.append("\(count) 条结果") }
        return parts.joined(separator: " · ")
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
        if host.hasSuffix(".fqnovel.com") || host == "reading.snssdk.com" {
            if url.path.contains("/video_detail/") { return "详情" }
            if url.path.contains("/video_model/") || url.path.contains("/multi_video_model/") { return "播放解析" }
            if url.path.hasPrefix("/novel/commentapi/comment/list/") { return "弹幕" }
        }
        return nil
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
    public func record(url: URL, context: String, elapsedMs: Int, status: Int, body: String, errorCode: String = "") {
        guard let stage = Self.stage(for: url) else { return }
        var entry = SourceDiagnosticEntry(
            context: context, stage: stage, host: url.host ?? "", status: status, errorCode: Self.safeCode(errorCode),
            elapsedMs: elapsedMs)
        if entry.errorCode.isEmpty && status != 200 { entry.errorCode = "HTTP_\(status)" }
        if entry.errorCode.isEmpty {
            if body.utf8.count <= 2 * 1024 * 1024, let data = body.data(using: .utf8),
                let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            {
                entry.businessCode = Self.safeCode(parsed["code"] ?? parsed["Code"] ?? parsed["status_code"])
                if !entry.businessCode.isEmpty && entry.businessCode != "0" {
                    entry.errorCode = "BUSINESS_REJECTED"
                } else if stage == "游客注册" {
                    let valid = [parsed["device_id_str"], parsed["install_id_str"]].allSatisfy { value in
                        guard let string = value as? String else { return false }
                        return string.range(of: "^\\d{10,24}$", options: .regularExpression) != nil
                    }
                    if !valid { entry.errorCode = "GUEST_REGISTRATION_FAILED" }
                } else if stage == "搜索" && !(parsed["search_tabs"] is [Any]) {
                    entry.errorCode = "INVALID_RESPONSE"
                }
            } else {
                entry.errorCode = "INVALID_RESPONSE"
            }
        }
        add(entry)
    }
    public static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return
            "\(info["CFBundleShortVersionString"] as? String ?? "1.0.0")+\(info["CFBundleVersion"] as? String ?? "未知")"
    }
    public static var sourceHash: String {
        SHA256.hash(data: Data(BuiltInHongguoJSContent.trimmingCharacters(in: .whitespacesAndNewlines).utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }
    public static func advice(_ entry: SourceDiagnosticEntry) -> String {
        if entry.errorCode.hasPrefix("DNS") || (entry.stage == "游客注册" && entry.failed) {
            return "请检查 log.snssdk.com 是否被 DNS、去广告或代理规则拦截，并用手机热点对照。"
        }
        if entry.errorCode.hasPrefix("TIMEOUT") { return "请求超时，可换网络后重新检测。" }
        if entry.errorCode.hasPrefix("TLS") { return "安全连接失败，请检查设备时间、证书或代理。" }
        if ["HTTP_403", "HTTP_429", "BUSINESS_REJECTED"].contains(entry.errorCode) { return "服务端拒绝请求，请保留报告，稍后或换网络对照。" }
        return "请结合失败阶段、HTTP 状态和错误码反馈；单次检测不能判断是否被网络规则拦截。"
    }
    public var report: String {
        ([
            "THL 数据源诊断", "应用：\(Self.version)", "系统：tvOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "数据源：hongguo · SHA256 \(Self.sourceHash)", "报告时间：\(ISO8601DateFormatter().string(from: Date()))",
            "报告不含请求参数、设备标识、Cookie、签名和响应原文。",
        ] + entries.map(\.text)).joined(separator: "\n")
    }
    public var qrText: String {
        var recent = Array(entries.suffix(8))
        while true {
            let payload: [String: Any] = [
                "app": "THL", "version": Self.version, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "source": "hongguo", "sha256": Self.sourceHash, "at": ISO8601DateFormatter().string(from: Date()),
                "recent": recent.map { entry -> [String: Any] in
                    [
                        "at": ISO8601DateFormatter().string(from: entry.at), "stage": entry.stage, "host": entry.host,
                        "http": entry.status, "business": entry.businessCode, "error": entry.errorCode,
                        "ms": entry.elapsedMs,
                    ]
                },
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                return ""
            }
            if data.count <= 2300 || recent.isEmpty { return String(decoding: data, as: UTF8.self) }
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
        result = "正在检查游客注册、搜索、分页和详情…"
        let recorder = SourceDiagnostics.shared
        let context = "主动检测 " + ISO8601DateFormatter().string(from: Date())
        let bridge = NativeBridge(diagnostics: recorder, diagnosticContext: context)
        var stage = "搜索第一页"
        defer { running = false }
        do {
            let first = try await bridge.request(
                action: "catalog", payload: ["source": "hongguo", "query": "短剧", "page": 1])
            let items = first["items"] as? [[String: Any]] ?? []
            recorder.add(SourceDiagnosticEntry(context: context, stage: stage, count: items.count))
            let more = first["hasMore"] as? Bool == true
            if more {
                stage = "搜索分页"
                let next = try await bridge.request(
                    action: "catalog", payload: ["source": "hongguo", "query": "短剧", "page": 2])
                recorder.add(
                    SourceDiagnosticEntry(context: context, stage: stage, count: (next["items"] as? [Any])?.count ?? 0))
            }
            if let drama = items.first {
                stage = "详情解析"
                let detail = try await bridge.request(action: "detail", payload: ["drama": drama])
                guard let chapters = detail["chapters"] as? [Any], !chapters.isEmpty else {
                    throw NSError(domain: "SourceDiagnostic", code: 1)
                }
            }
            result = "检测完成：注册、搜索\(more ? "、分页" : "")\(items.isEmpty ? "（无结果）" : "、详情")通过"
        } catch {
            recorder.add(SourceDiagnosticEntry(context: context, stage: stage, errorCode: "DIAGNOSTIC_FAILED"))
            result = "检测失败：\(stage)，请查看下方记录"
        }
    }
}
