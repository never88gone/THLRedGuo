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
    case configuration = "configuration"
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
        case .configuration: return "本机播放配置"
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
        case .configuration: return "配置未就绪"
        case .unknown: return "检测失败"
        }
    }
}
