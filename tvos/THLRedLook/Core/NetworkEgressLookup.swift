import Foundation
import Network

public struct NetworkEgressLookup: Sendable {
    private let session: URLSession
    private let ownsSession: Bool

    public init(session: URLSession? = nil) {
        if let session { self.session = session; self.ownsSession = false }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4
            config.timeoutIntervalForResource = 5
            config.httpShouldSetCookies = false
            config.urlCache = nil
            self.session = URLSession(configuration: config)
            self.ownsSession = true
        }
    }

    public static func parse(_ body: Data, provider: String, at: Date = Date()) -> NetworkEgressResult? {
        guard body.count <= 32768,
              let data = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              data["success"] as? Bool != false,
              let ip = data["ip"] as? String,
              IPv4Address(ip) != nil || IPv6Address(ip) != nil else { return nil }
        func text(_ key: String) -> String {
            let value = data[key] as? String ?? ""
            return String(value.components(separatedBy: .controlCharacters).joined().prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let code = text("country_code").uppercased()
        return NetworkEgressResult(at: at, ip: ip, country: text("country"), countryCode: code.range(of: "^[A-Z]{2}$", options: .regularExpression) == nil ? "" : code, region: text("region"), city: text("city"), provider: provider, error: "")
    }

    public func lookup() async -> NetworkEgressResult {
        defer { if ownsSession { session.finishTasksAndInvalidate() } }
        var failures: [String] = []
        for (name, address) in [("IP.SB", "https://api.ip.sb/geoip"), ("IPWho.is", "https://ipwho.is/")] {
            if Task.isCancelled { break }
            do {
                var request = URLRequest(url: URL(string: address)!)
                request.timeoutInterval = 4
                request.setValue("THLRedLook/1.0.0 diagnostics", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (body, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { failures.append("\(name): HTTP_\(status)"); continue }
                if let value = Self.parse(body, provider: name) { return value }
                failures.append("\(name): INVALID_RESPONSE")
            } catch {
                failures.append("\(name): \(SourceDiagnostics.networkCode(error))")
            }
        }
        return NetworkEgressResult(at: Date(), ip: "", country: "", countryCode: "", region: "", city: "", provider: "IP.SB / IPWho.is", error: failures.isEmpty ? "CANCELLED" : failures.joined(separator: "; "))
    }
}
