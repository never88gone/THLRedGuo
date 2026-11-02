import Foundation
import Security
import Combine

struct HongguoCookie: Codable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    var valid: Bool { domain == "hongguoduanju.com" && (expires == nil || expires! > Date()) }
}

struct HongguoAccountRecord: Codable, Sendable {
    let id: String
    let nickname: String
    var cookies: [HongguoCookie]
    var device: [String: String]? = nil
}

final class HongguoAccountVault: @unchecked Sendable {
    static let shared = HongguoAccountVault()
    private let lock = NSLock()
    private var value: HongguoAccountRecord?
    private var generation: UInt64 = 0
    private let service = "THLRedLook.hongguo.account"
    private let credentialNames: Set<String> = ["sessionid", "sessionid_ss", "sid_guard", "sid_tt", "uid_tt", "uid_tt_ss", "sid_ucp_v1", "ssid_ucp_v1", "passport_auth_status", "passport_auth_status_ss"]
    init() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "default", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            value = try? JSONDecoder().decode(HongguoAccountRecord.self, from: data)
        }
    }
    var snapshot: (record: HongguoAccountRecord?, revision: UInt64) { lock.withLock { (value, generation) } }
    static func businessURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.port == nil else { return false }
        let host = url.host ?? ""
        return (host == "reading.snssdk.com" || host.range(of: "^api[0-9]+-normal-sinfonline[a-z]\\.fqnovel\\.com$", options: .regularExpression) != nil) &&
            (url.path.hasPrefix("/reading/") || url.path.hasPrefix("/novel/"))
    }
    func header(for url: URL, record: HongguoAccountRecord? = nil) -> String {
        guard Self.businessURL(url) else { return "" }
        let account = record ?? snapshot.record
        return account?.cookies.filter { $0.valid && credentialNames.contains($0.name) }
            .map { "\($0.name)=\($0.value)" }.joined(separator: "; ") ?? ""
    }
    func save(_ record: HongguoAccountRecord, expectedRevision: UInt64) throws {
        try lock.withLock {
            guard expectedRevision == generation else { throw HongguoAccountError.cancelled }
            let data = try JSONEncoder().encode(record)
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "default"]
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query; item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw HongguoAccountError.storage }
            } else if status != errSecSuccess { throw HongguoAccountError.storage }
            value = record; generation += 1
        }
    }
    func logout() throws {
        try lock.withLock {
            value = nil; generation += 1
            let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "default"] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw HongguoAccountError.storage }
        }
    }
}

enum HongguoAccountError: LocalizedError, Equatable {
    case cancelled, storage, invalid, expired, server(Int), business(Int), preparation(String), network
    var errorDescription: String? {
        switch self {
        case .cancelled: return "账号操作已取消"
        case .storage: return "账号安全存储暂不可用，请重试"
        case .invalid: return "账号校验失败，请重新扫码或稍后重试"
        case .expired: return "二维码已过期，请刷新"
        case .server(let status): return "账号请求失败（HTTP \(status)）"
        case .business(let code): return "官方登录校验失败（错误码 \(code)）"
        case .preparation(let code): return "账号请求准备失败（\(code)）"
        case .network: return "账号网络请求失败，请稍后重试"
        }
    }
}

@MainActor
final class HongguoAccountModel: ObservableObject {
    static let shared = HongguoAccountModel()
    @Published private(set) var account = HongguoAccountVault.shared.snapshot.record
    @Published private(set) var verified = false
    @Published private(set) var qrURL: String?
    @Published private(set) var remaining = 0
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    private var attempt = 0
    private var token = ""
    private var expiresAt = Date.distantPast
    private var cookies: [HongguoCookie] = []
    private var profileDevice: [String: String]?
    private var loginTask: Task<Void, Never>?
    private var transport: URLSession?
    private var stage = "idle"
    private var lastTrace = ""
    private let vault = HongguoAccountVault.shared
    var loggedIn: Bool { account?.cookies.contains { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) } == true }
    func cancel() {
        attempt += 1; loginTask?.cancel(); loginTask = nil
        transport?.invalidateAndCancel(); transport = nil
        qrURL = nil; token = ""; cookies = []; busy = false
    }
    func begin() {
        cancel(); let owner = attempt; let revision = vault.snapshot.revision
        busy = true; message = "正在申请二维码"; lastTrace = ""
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
        transport = URLSession(configuration: config, delegate: HongguoLoginRedirectDelegate(), delegateQueue: nil)
        loginTask = Task {
            do {
                let response = try await call("qr", owner: owner)
                try check(owner)
                guard let value = response["qrUrl"] as? String, let newToken = response["token"] as? String,
                    let expiry = response["expiresAt"] as? NSNumber else { throw HongguoAccountError.invalid }
                token = newToken
                expiresAt = expiry.doubleValue > 1_000_000_000 ? Date(timeIntervalSince1970: expiry.doubleValue) : Date().addingTimeInterval(min(600, expiry.doubleValue))
                qrURL = value; busy = false; message = "等待手机红果 App 扫码确认"
                var tick = 0; var failures = 0
                while expiresAt > Date() || cookies.contains(where: { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }) {
                    try check(owner)
                    remaining = max(0, Int(expiresAt.timeIntervalSinceNow))
                    try await Task.sleep(for: .seconds(1))
                    tick += 1
                    guard tick % 2 == 0 else { continue }
                    do {
                        let hasSession = cookies.contains { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }
                        let state = hasSession ? [:] : try await call("poll", payload: ["token": token], owner: owner)
                        try check(owner)
                        let status = state["status"] as? String ?? ""
                        trace("poll", status: status)
                        if ["5", "expired"].contains(status) { throw HongguoAccountError.expired }
                        if status == "cancelled" { throw HongguoAccountError.cancelled }
                        if ["3", "confirmed"].contains(status) {
                            if let redirect = state["redirect"] as? String, !redirect.isEmpty { try await finishRedirect(redirect, owner: owner) }
                        }
                        if cookies.contains(where: { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }) {
                            message = "手机已确认，正在校验红果账号"; qrURL = nil; busy = true
                            _ = try await call("webInfo", owner: owner)
                            let profile = try await call("profile", owner: owner)
                            try check(owner)
                            guard let id = profile["id"] as? String, !id.isEmpty else { throw HongguoAccountError.invalid }
                            let record = HongguoAccountRecord(id: id, nickname: profile["nickname"] as? String ?? "红果用户", cookies: cookies, device: profileDevice)
                            try vault.save(record, expectedRevision: revision)
                            trace("saved")
                            account = record; verified = true; qrURL = nil; busy = false; message = "红果账号已登录"
                            token = ""; cookies = []; return
                        }
                        failures = 0
                    } catch {
                        try check(owner)
                        if let issue = error as? HongguoAccountError, issue == .expired || issue == .cancelled { throw issue }
                        trace(stage, error: error)
                        failures += 1; message = "登录查询暂时失败，正在重试"
                        if failures >= 3 { throw error }
                    }
                }
                throw HongguoAccountError.expired
            } catch {
                if owner == attempt {
                    trace(stage, error: error)
                    qrURL = nil; busy = false
                    message = ((error as? HongguoAccountError)?.localizedDescription ?? "登录请求失败，请稍后重试") + "（阶段：\(stage)）"
                }
            }
        }
    }
    func verify(force: Bool = false) async {
        guard loggedIn, !busy, force || !verified else { return }
        let owner = attempt; busy = true
        defer { busy = false }
        do {
            let profile = try await call("profile", owner: owner, existing: true)
            try check(owner)
            guard profile["id"] as? String == account?.id else { throw HongguoAccountError.invalid }
            verified = true; message = "红果账号已登录"
        } catch { if owner == attempt { trace(stage, error: error, existing: true); message = "暂时无法确认账号，本机资料已保留" } }
    }
    func logout() {
        cancel()
        do { try vault.logout(); account = nil; verified = false; message = "已退出红果账号" }
        catch { account = nil; verified = false; message = "当前会话已退出，安全存储清理失败，请重试" }
    }
    private func check(_ owner: Int) throws {
        if Task.isCancelled || owner != attempt { throw HongguoAccountError.cancelled }
    }
    private func call(_ action: String, payload: [String: String] = [:], owner: Int, existing: Bool = false) async throws -> [String: Any] {
        try check(owner)
        stage = action
        let command = try await NativeBridge.shared.accountRequest(action, payload: payload)
        guard let value = command["url"] as? String, let url = URL(string: value) else { throw HongguoAccountError.invalid }
        if action == "profile", let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            profileDevice = Dictionary(uniqueKeysWithValues: query.filter { ["iid", "device_id", "cdid"].contains($0.name) && $0.value != nil }.map { ($0.name, $0.value!) })
        }
        let body = try await request(url, headers: command["headers"] as? [String: String] ?? [:], owner: owner, existing: existing)
        let result = try await NativeBridge.shared.accountParse(action, body: body)
        if action != "poll" { trace(action, existing: existing) }
        return result
    }
    private func trace(_ phase: String, status: String = "", error: Error? = nil, existing: Bool = false) {
        let safeStatus = ["0", "1", "2", "3", "4", "5", "new", "scanned", "confirmed", "expired", "cancelled"].contains(status) ? status : status.isEmpty ? "" : "unknown"
        let session = (existing ? account?.cookies ?? [] : cookies).contains { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }
        let issue = error as? HongguoAccountError
        let code: String
        switch issue {
        case .business(let value): code = "BUSINESS_\(value)"
        case .server(let value): code = "HTTP_\(value)"
        case .expired: code = "QR_EXPIRED"
        case .cancelled: code = "CANCELLED"
        case .storage: code = "STORAGE"
        case .invalid: code = "INVALID_RESPONSE"
        case .preparation(let value): code = value
        default: code = error == nil ? "" : "NETWORK"
        }
        let summary = "phase=\(phase) status=\(safeStatus) session=\(session) error=\(code)"
        guard summary != lastTrace else { return }
        lastTrace = summary
        NSLog("[Account] %@", summary)
        SourceDiagnostics.shared.add(SourceDiagnosticEntry(context: "红果登录", stage: phase, errorCode: code, sessionStatus: "status=\(safeStatus) session=\(session)"))
    }
    private func request(_ url: URL, headers: [String: String], owner: Int, existing: Bool = false) async throws -> String {
        try check(owner)
        let web = url.scheme == "https" && url.host == "hongguoduanju.com" && url.port == nil
        guard web || HongguoAccountVault.businessURL(url) else { throw HongguoAccountError.invalid }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        if web {
            request.setValue("Mozilla/5.0 THLRedLook/1.0.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://hongguoduanju.com/", forHTTPHeaderField: "Referer")
        }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let active = existing ? account?.cookies ?? [] : cookies
        if web {
            let matched = active.filter { $0.valid && (url.path == $0.path || url.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/")) }
            request.setValue(matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            if let csrf = matched.first(where: { $0.name == "passport_csrf_token" }) { request.setValue(csrf.value, forHTTPHeaderField: "x-tt-passport-csrf-token") }
        } else {
            let record = HongguoAccountRecord(id: "", nickname: "", cookies: active)
            request.setValue(vault.header(for: url, record: record), forHTTPHeaderField: "Cookie")
        }
        let session = transport ?? URLSession(configuration: .ephemeral, delegate: HongguoLoginRedirectDelegate(), delegateQueue: nil)
        let (data, raw) = try await session.data(for: request)
        try check(owner)
        guard let response = raw as? HTTPURLResponse, data.count <= 2 * 1024 * 1024 else { throw HongguoAccountError.invalid }
        if web && !existing {
            let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in result[String(describing: pair.key)] = String(describing: pair.value) }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                guard domain == "hongguoduanju.com" else { continue }
                cookies.removeAll { $0.name == cookie.name && $0.domain == domain && $0.path == cookie.path }
                let value = HongguoCookie(name: cookie.name, value: cookie.value, domain: domain, path: cookie.path, expires: cookie.expiresDate)
                if value.valid { cookies.append(value) }
            }
        }
        if [301,302,303,307,308].contains(response.statusCode), let next = response.value(forHTTPHeaderField: "Location"), web {
            return "redirect:" + next
        }
        guard response.statusCode == 200 else { throw HongguoAccountError.server(response.statusCode) }
        guard !data.isEmpty, let body = String(data: data, encoding: .utf8) else { throw HongguoAccountError.invalid }
        return body
    }
    private func finishRedirect(_ value: String, owner: Int) async throws {
        stage = "redirect"
        var next = value
        for _ in 0..<5 {
            guard let url = URL(string: next, relativeTo: URL(string: "https://hongguoduanju.com/"))?.absoluteURL,
                url.scheme == "https", url.host == "hongguoduanju.com", url.port == nil else { throw HongguoAccountError.invalid }
            let body = try await request(url, headers: [:], owner: owner)
            if !body.hasPrefix("redirect:") { return }
            next = String(body.dropFirst(9))
        }
        throw HongguoAccountError.invalid
    }
}

private final class HongguoLoginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class HongguoBusinessRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if task.originalRequest?.value(forHTTPHeaderField: "Cookie") != nil { completionHandler(nil) }
        else { completionHandler(request) }
    }
}
