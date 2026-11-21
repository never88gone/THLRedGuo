import Foundation

public struct NetworkEgressResult: Sendable {
    public let at: Date
    public let ip: String
    public let country: String
    public let countryCode: String
    public let region: String
    public let city: String
    public let provider: String
    public let error: String

    public var location: String {
        let values = [country, region, city].filter { !$0.isEmpty }
        return values.isEmpty ? "归属地未知" : values.joined(separator: " · ")
    }

    public var summary: String {
        ip.isEmpty ? "出口 IP：检测失败（\(error)）" : "出口 IP：\(ip) · \(location)\(countryCode.isEmpty ? "" : " [\(countryCode)]")"
    }

    public static let notice = "IP 归属地由查询服务估算；代理分流时可能与红果接口出口不同，不能单独证明风控。"

    public var reportLines: [String] {
        var lines = ["· 出口 IP: \(ip.isEmpty ? "未取得" : ip)", "· IP 归属地区: \(location)\(countryCode.isEmpty ? "" : " [\(countryCode)]")", "· IP 查询来源: \(provider)", "· IP 检测时间: \(ISO8601DateFormatter().string(from: at))"]
        if !error.isEmpty { lines.append("· IP 检测状态: \(error)") }
        lines.append("· IP 说明: \(Self.notice)")
        return lines
    }

    public init(at: Date, ip: String, country: String, countryCode: String, region: String, city: String, provider: String, error: String) {
        self.at = at
        self.ip = ip
        self.country = country
        self.countryCode = countryCode
        self.region = region
        self.city = city
        self.provider = provider
        self.error = error
    }
}
