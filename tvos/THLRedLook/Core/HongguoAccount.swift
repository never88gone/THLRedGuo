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
    var avatar: String? = nil
    var hasSession: Bool { cookies.contains { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) } }
}

struct HongguoVerifiedTransfer {
    let record: HongguoAccountRecord
    let revision: UInt64
    let owner: Int
}

final class HongguoTransientCookies {
    var values: [HongguoCookie]
    init(_ values: [HongguoCookie]) { self.values = values }
}

final class HongguoAccountVault: @unchecked Sendable {
    static let shared = HongguoAccountVault()
    private let lock = NSLock()
    private var value: HongguoAccountRecord?
    private var generation: UInt64 = 0
    private let service = "THLRedLook.hongguo.account"
    static let credentialNames: Set<String> = ["sessionid", "sessionid_ss", "sid_guard", "sid_tt", "uid_tt", "uid_tt_ss", "sid_ucp_v1", "ssid_ucp_v1", "passport_auth_status", "passport_auth_status_ss"]
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
        return (host == "reading.snssdk.com" || host == "api5-normal.fqnovel.com" || host.range(of: "^api[0-9]+-normal-sinfonline[a-z]\\.fqnovel\\.com$", options: .regularExpression) != nil) &&
            (url.path.hasPrefix("/reading/") || url.path.hasPrefix("/novel/"))
    }
    func header(for url: URL, record: HongguoAccountRecord? = nil) -> String {
        guard Self.businessURL(url) else { return "" }
        let account = record ?? snapshot.record
        guard account?.hasSession == true else { return "" }
        return account?.cookies.filter { $0.valid && Self.credentialNames.contains($0.name) }
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
    case cancelled, storage, invalid, expired, challenge, server(Int), business(Int), preparation(String), network
    var errorDescription: String? {
        switch self {
        case .cancelled: return "账号操作已取消"
        case .storage: return "账号安全存储暂不可用，请重试"
        case .invalid: return "账号校验失败，请重新扫码或稍后重试"
        case .expired: return "二维码已过期，请刷新"
        case .challenge: return "红果要求额外安全验证，请使用红果 App 扫码登录"
        case .server(let status): return "账号请求失败（HTTP \(status)）"
        case .business(let code): return "官方账号请求失败（错误码 \(code)）"
        case .preparation(let code): return "账号请求准备失败（\(code)）"
        case .network: return "账号网络请求失败，请稍后重试"
        }
    }
}

final class HongguoAccountLibraryCache: @unchecked Sendable {
    static let shared = HongguoAccountLibraryCache()
    private let lock = NSLock()
    private var revision: UInt64 = .max
    private var watches: [String: WatchEntry] = [:]
    private var historyIds: Set<String> = []
    private var favorites: [String: Drama] = [:]
    private var favoriteOrder: [String] = []
    static func id(_ value: String) -> String { value.hasPrefix("hongguo:") ? String(value.dropFirst(8)) : value }
    func handles(_ id: String) -> Bool {
        let record = HongguoAccountVault.shared.snapshot.record
        return record?.hasSession == true &&
            (id.hasPrefix("hongguo:") || id.range(of: "^\\d{10,30}$", options: .regularExpression) != nil)
    }
    private func resetIfNeeded() {
        let current = HongguoAccountVault.shared.snapshot.revision
        if revision != current { revision = current; watches = [:]; favorites = [:]; historyIds = []; favoriteOrder = [] }
    }
    func watch(_ id: String) -> WatchEntry? { lock.withLock { resetIfNeeded(); return watches[Self.id(id)] } }
    func followed(_ id: String) -> Bool { lock.withLock { resetIfNeeded(); return favorites[Self.id(id)] != nil } }
    func entries(history: Bool) -> [WatchEntry] {
        lock.withLock {
            resetIfNeeded()
            if history { return historyIds.compactMap { watches[$0] }.sorted { $0.updatedAt > $1.updatedAt } }
            return favoriteOrder.compactMap { favorites[$0] }.map { WatchEntry(drama: $0, episode: 0, position: 0, duration: 0, updatedAt: Date(timeIntervalSince1970: 0)) }
        }
    }
    func update(_ rows: [WatchEntry], history: Bool, owner: UInt64, preserving: Set<String> = []) {
        lock.withLock {
            resetIfNeeded(); guard revision == owner else { return }
            if history { historyIds = Set(rows.map { Self.id($0.drama.id) }).union(preserving); for row in rows { let key = Self.id(row.drama.id); if watches[key] == nil || watches[key]!.updatedAt <= row.updatedAt { watches[key] = row } } }
            else { favoriteOrder = rows.map { Self.id($0.drama.id) }; favorites = Dictionary(rows.map { (Self.id($0.drama.id), $0.drama) }, uniquingKeysWith: { _, last in last }) }
        }
    }
    func progress(_ entry: WatchEntry?, id: String, owner: UInt64, recordHistory: Bool = false) {
        lock.withLock { resetIfNeeded(); guard revision == owner else { return }; watches[Self.id(id)] = entry; if entry == nil { historyIds.remove(Self.id(id)) } else if recordHistory { historyIds.insert(Self.id(id)) } }
    }
    func follow(_ drama: Drama, add: Bool, owner: UInt64) {
        lock.withLock { resetIfNeeded(); guard revision == owner else { return }; favorites[Self.id(drama.id)] = add ? drama : nil; favoriteOrder.removeAll { $0 == Self.id(drama.id) }; if add { favoriteOrder.insert(Self.id(drama.id), at: 0) } }
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
    @Published private(set) var libraryVersion = 0
    @Published private(set) var libraryWriteError: String?
    private var accountWrites: Task<Void, Error>?
    private var reportedAt: [String: Date] = [:]
    private var favoriteGeneration: UInt64 = 0
    private var progressGeneration: [String: UInt64] = [:]
    private var favoriteRevision: UInt64?
    private var attempt = 0
    private var token = ""
    private var expiresAt = Date.distantPast
    private var cookies: [HongguoCookie] = []
    private var profileDevice: [String: String]?
    private var loginTask: Task<Void, Never>?
    private var transport: URLSession?
    private var stage = "idle"
    private var lastTrace = ""
    private var phoneIdentity = ""
    private var phoneCodeSent = false
    @Published private(set) var phoneRetryAt = Date.distantPast
    private let vault = HongguoAccountVault.shared
    var loggedIn: Bool { account?.hasSession == true }
    func cancel() {
        attempt += 1; loginTask?.cancel(); loginTask = nil
        transport?.invalidateAndCancel(); transport = nil
        qrURL = nil; token = ""; cookies = []; busy = false; phoneIdentity = ""; phoneCodeSent = false
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
                            let record = HongguoAccountRecord(id: id, nickname: profile["nickname"] as? String ?? "红果用户", cookies: cookies, device: profileDevice, avatar: profile["avatar"] as? String)
                            try vault.save(record, expectedRevision: revision)
                            releaseLoginResources()
                            account = record; verified = true; qrURL = nil; busy = false; message = "红果账号已登录"
                            trace("saved", existing: true)
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
    private func preparePhone(country: String, number: String) async throws -> Int {
        let identity = country + ":" + number
        if phoneIdentity != identity {
            cancel(); phoneIdentity = identity
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
            transport = URLSession(configuration: config, delegate: HongguoLoginRedirectDelegate(), delegateQueue: nil)
        }
        let owner = attempt
        if !cookies.contains(where: { $0.valid && ["passport_csrf_token", "passport_csrf_token_default"].contains($0.name) }) { _ = try await call("qr", owner: owner) }
        try check(owner)
        return owner
    }
    func sendPhoneCode(country: String, number: String) async throws {
        guard !busy, phoneRetryAt <= Date() else { throw HongguoAccountError.preparation("SMS_COOLDOWN") }
        let owner = try await preparePhone(country: country, number: number)
        busy = true
        defer { if owner == attempt { busy = false } }
        do {
            let data = try await call("phoneCode", payload: ["country": country, "number": number], owner: owner)
            try check(owner)
            phoneCodeSent = true
            phoneRetryAt = Date().addingTimeInterval((data["retryAfter"] as? NSNumber)?.doubleValue ?? 60)
            message = "验证码已发送"
        } catch { trace(stage, error: error); throw error }
    }
    func loginPhone(country: String, number: String, code: String) async throws {
        guard !busy else { throw HongguoAccountError.cancelled }
        let owner = try await preparePhone(country: country, number: number)
        if !phoneCodeSent { throw HongguoAccountError.preparation("SMS_REQUIRED") }
        let revision = vault.snapshot.revision
        busy = true
        defer { if owner == attempt { busy = false } }
        do {
            _ = try await call("phoneSms",
                payload: ["country": country, "number": number, "code": code], owner: owner)
            try check(owner)
            guard cookies.contains(where: { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }) else { throw HongguoAccountError.invalid }
            _ = try await call("webInfo", owner: owner)
            let profile = try await call("profile", owner: owner)
            try check(owner)
            guard let id = profile["id"] as? String else { throw HongguoAccountError.invalid }
            let record = HongguoAccountRecord(id: id, nickname: profile["nickname"] as? String ?? "红果用户",
                cookies: cookies, device: profileDevice, avatar: profile["avatar"] as? String)
            try vault.save(record, expectedRevision: revision)
            releaseLoginResources()
            account = record; verified = true; message = "红果账号已登录"
            trace("saved", existing: true)
        } catch { trace(stage, error: error); throw error }
    }
    func prepareTransferred(_ candidate: HongguoAccountRecord, expectedRevision: UInt64, isCurrent: () -> Bool) async throws -> HongguoVerifiedTransfer {
        let owner = attempt, revision = expectedRevision
        guard revision == vault.snapshot.revision else { throw HongguoAccountError.cancelled }
        let importedCookies = HongguoTransientCookies(candidate.cookies)
        guard isCurrent() else { throw HongguoAccountError.cancelled }
        _ = try await call("webInfo", owner: owner, candidateCookies: importedCookies)
        guard let device = candidate.device,
            let data = try? JSONSerialization.data(withJSONObject: device), let bound = String(data: data, encoding: .utf8) else { throw HongguoAccountError.invalid }
        let profile = try await call("profile", payload: ["device": bound], owner: owner, candidateCookies: importedCookies)
        try check(owner)
        guard isCurrent(), profile["id"] as? String == candidate.id else { throw HongguoAccountError.invalid }
        let record = HongguoAccountRecord(id: candidate.id, nickname: profile["nickname"] as? String ?? "红果用户",
            cookies: importedCookies.values, device: device, avatar: profile["avatar"] as? String)
        return HongguoVerifiedTransfer(record: record, revision: revision, owner: owner)
    }
    func commitTransferred(_ transfer: HongguoVerifiedTransfer, isCurrent: () -> Bool) throws {
        try check(transfer.owner)
        guard isCurrent(), vault.snapshot.revision == transfer.revision else { throw HongguoAccountError.cancelled }
        try vault.save(transfer.record, expectedRevision: transfer.revision)
        account = transfer.record; verified = true; message = "红果账号已登录"
    }

    private func releaseLoginResources() {
        loginTask = nil; transport?.finishTasksAndInvalidate(); transport = nil
        cookies = []; token = ""; phoneIdentity = ""; phoneCodeSent = false; qrURL = nil
    }
    func verify(force: Bool = false) async {
        guard loggedIn, !busy, force || !verified else { return }
        let owner = attempt; busy = true
        defer { busy = false }
        do {
            let profile = try await call("profile", owner: owner, existing: true)
            try check(owner)
            guard profile["id"] as? String == account?.id else { throw HongguoAccountError.invalid }
            if let current = account {
                account = HongguoAccountRecord(id: current.id, nickname: profile["nickname"] as? String ?? current.nickname,
                    cookies: current.cookies, device: current.device, avatar: profile["avatar"] as? String ?? current.avatar)
            }
            verified = true; message = "红果账号已登录"
        } catch { if owner == attempt { trace(stage, error: error, existing: true); message = "暂时无法确认账号，本机资料已保留" } }
    }
    func library(history: Bool) async throws -> [WatchEntry] {
        guard loggedIn else { throw HongguoAccountError.invalid }
        let owner = attempt
        let revision = vault.snapshot.revision
        let generation = favoriteGeneration, progressSnapshot = progressGeneration
        let response = try await call(history ? "history" : "favorites", payload: history ? [:] : ["userId": account?.id ?? ""], owner: owner, existing: true)
        guard let rows = response["items"] as? [[String: Any]] else { throw HongguoAccountError.invalid }
        var details: [String: [String: Any]] = [:]
        for offset in stride(from: 0, to: rows.count, by: 50) {
            let ids = rows.dropFirst(offset).prefix(50).compactMap { $0["id"] as? String }.joined(separator: ",")
            let response = try await call("libraryDetails", payload: ["ids": ids], owner: owner, existing: true)
            guard let entries = response["items"] as? [[String: Any]] else { throw HongguoAccountError.invalid }
            for entry in entries { if let id = entry["id"] as? String { details[id] = entry } }
        }
        try check(owner)
        guard vault.snapshot.revision == revision, loggedIn else { throw HongguoAccountError.cancelled }
        let entries: [WatchEntry] = rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let detail = details[id] ?? row
            let title = detail["title"] as? String ?? ""
            let count = (detail["episodes"] as? NSNumber)?.intValue ?? 0
            let drama = Drama(id: "hongguo:" + id, sourceId: id, title: title.isEmpty ? "剧集" + id : title,
                description: detail["description"] as? String ?? "", cover: detail["cover"] as? String ?? "",
                episodes: count > 0 ? count : (row["episodes"] as? NSNumber)?.intValue ?? 0)
            return WatchEntry(drama: drama, episode: (row["episode"] as? NSNumber)?.intValue ?? 0,
                position: ((row["positionMs"] as? NSNumber)?.doubleValue ?? 0) / 1000,
                duration: ((row["durationMs"] as? NSNumber)?.doubleValue ?? 0) / 1000,
                updatedAt: Date(timeIntervalSince1970: ((row["updatedAt"] as? NSNumber)?.doubleValue ?? 0) / 1000))
        }
        if history || generation == favoriteGeneration {
            HongguoAccountLibraryCache.shared.update(entries, history: history, owner: revision, preserving: Set(progressGeneration.filter { $0.value > (progressSnapshot[$0.key] ?? 0) }.keys.map(HongguoAccountLibraryCache.id)))
            if !history { favoriteRevision = revision }
            publishLibraryChange()
        }
        return HongguoAccountLibraryCache.shared.entries(history: history)
    }
    private func publishLibraryChange() {
        libraryVersion += 1
        LocalStore.shared.objectWillChange.send()
    }
    func prepareLibrary(_ drama: Drama) async throws {
        guard HongguoAccountLibraryCache.shared.handles(drama.id) else { return }
        if favoriteRevision != vault.snapshot.revision { _ = try await library(history: false) }
        _ = try await progress(drama)
    }
    func progress(_ drama: Drama) async throws -> WatchEntry? {
        let owner = attempt, revision = vault.snapshot.revision, generation = progressGeneration[drama.id] ?? 0
        guard loggedIn else { throw HongguoAccountError.invalid }
        let rows = try await Self.progressRows(id: drama.cleanSourceId) { action, payload in
            try await self.call(action, payload: payload, owner: owner, existing: true)
        }
        guard vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        let row = rows.first { $0["id"] as? String == drama.cleanSourceId }
        let entry = row.map { row in WatchEntry(drama: drama,
            episode: (row["episode"] as? NSNumber)?.intValue ?? 0,
            position: ((row["positionMs"] as? NSNumber)?.doubleValue ?? 0) / 1000,
            duration: ((row["durationMs"] as? NSNumber)?.doubleValue ?? 0) / 1000,
            updatedAt: Date(timeIntervalSince1970: ((row["updatedAt"] as? NSNumber)?.doubleValue ?? 0) / 1000)) }
        if generation == progressGeneration[drama.id] ?? 0 {
            HongguoAccountLibraryCache.shared.progress(entry, id: drama.id, owner: revision)
            publishLibraryChange()
        }
        return HongguoAccountLibraryCache.shared.watch(drama.id)
    }
    static func progressRows(id: String, request: (String, [String: String]) async throws -> [String: Any]) async throws -> [[String: Any]] {
        do {
            let response = try await request("progressGet", ["id": id])
            guard let rows = response["items"] as? [[String: Any]] else { throw HongguoAccountError.invalid }
            return rows
        } catch HongguoAccountError.business(101112) {
            let response = try await request("history", [:])
            guard let rows = response["items"] as? [[String: Any]], rows.contains(where: { $0["id"] as? String == id }) else { throw HongguoAccountError.business(101112) }
            return rows
        }
    }
    private func enqueueWrite(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let revision = vault.snapshot.revision, previous = accountWrites
        let task = Task { @MainActor in
            _ = await previous?.result
            guard self.loggedIn, self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
            try await operation()
            guard self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        }
        accountWrites = task
        do { try await task.value; libraryWriteError = nil }
        catch { if vault.snapshot.revision == revision { libraryWriteError = "账号同步失败，请检查网络后重试" }; throw error }
    }
    func setFollowing(_ drama: Drama, add: Bool?) async throws {
        let revision = vault.snapshot.revision
        try await enqueueWrite {
            let follow = add ?? !HongguoAccountLibraryCache.shared.followed(drama.id)
            let owner = self.attempt
            _ = try await self.call("favoriteUpdate", payload: ["id": drama.cleanSourceId, "follow": follow ? "1" : "0"], owner: owner, existing: true)
            let check = try await self.call("favorites", payload: ["userId": self.account?.id ?? ""], owner: owner, existing: true)
            guard let rows = check["items"] as? [[String: Any]], rows.contains(where: { $0["id"] as? String == drama.cleanSourceId }) == follow,
                self.vault.snapshot.revision == revision else { throw HongguoAccountError.invalid }
            self.favoriteGeneration += 1
            HongguoAccountLibraryCache.shared.follow(drama, add: follow, owner: revision)
            self.publishLibraryChange()
        }
    }
    func uploadProgress(_ entry: WatchEntry, itemId: String, force: Bool) async throws {
        let revision = vault.snapshot.revision
        let key = "\(revision):\(entry.drama.id):\(entry.episode)"
        if !force, Date().timeIntervalSince(reportedAt[key] ?? .distantPast) < 30 { return }
        reportedAt[key] = Date()
        try await enqueueWrite {
            _ = try await self.call("progressUpdate", payload: ["id": entry.drama.cleanSourceId, "itemId": itemId,
                "episode": String(entry.episode), "positionMs": String(Int(entry.position * 1000)),
                "durationMs": String(Int(entry.duration * 1000)), "episodes": String(entry.drama.episodes),
                "updatedAt": String(Int(entry.updatedAt.timeIntervalSince1970 * 1000))], owner: self.attempt, existing: true)
            guard self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
            self.progressGeneration[entry.drama.id] = (self.progressGeneration[entry.drama.id] ?? 0) + 1
            HongguoAccountLibraryCache.shared.progress(entry, id: entry.drama.id, owner: revision, recordHistory: true)
            self.publishLibraryChange()
        }
    }
    func logout() {
        cancel()
        do { try vault.logout(); account = nil; verified = false; message = "已退出红果账号" }
        catch { account = nil; verified = false; message = "当前会话已退出，安全存储清理失败，请重试" }
    }
    private func check(_ owner: Int) throws {
        if Task.isCancelled || owner != attempt { throw HongguoAccountError.cancelled }
    }
    private func call(_ action: String, payload: [String: String] = [:], owner: Int, existing: Bool = false, candidateCookies: HongguoTransientCookies? = nil) async throws -> [String: Any] {
        try check(owner)
        stage = action
        let command = try await NativeBridge.shared.accountRequest(action, payload: payload)
        guard let value = command["url"] as? String, let url = URL(string: value) else { throw HongguoAccountError.invalid }
        if action == "profile", let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            profileDevice = Dictionary(uniqueKeysWithValues: query.filter { ["iid", "device_id", "cdid"].contains($0.name) && $0.value != nil }.map { ($0.name, $0.value!) })
        }
        let body = try await request(url, headers: command["headers"] as? [String: String] ?? [:], owner: owner, existing: existing,
            method: command["method"] as? String ?? "GET", form: command["body"] as? String, candidateCookies: candidateCookies)
        let result: [String: Any]
        do { result = try await NativeBridge.shared.accountParse(action, body: body) }
        catch { trace(action, error: error, existing: existing); throw error }
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
        case .challenge: code = "CHALLENGE_REQUIRED"
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
    private func request(_ url: URL, headers: [String: String], owner: Int, existing: Bool = false,
        method: String = "GET", form: String? = nil, candidateCookies: HongguoTransientCookies? = nil) async throws -> String {
        try check(owner)
        let web = url.scheme == "https" && url.host == "hongguoduanju.com" && url.port == nil
        guard web || HongguoAccountVault.businessURL(url) else { throw HongguoAccountError.invalid }
        guard ["GET", "POST"].contains(method) else { throw HongguoAccountError.invalid }
        var request = URLRequest(url: url); request.timeoutInterval = 12; request.httpMethod = method
        if method == "POST" {
            guard let form, form.utf8.count <= 16 * 1024 else { throw HongguoAccountError.invalid }
            request.httpBody = Data(form.utf8)
        }
        if web {
            request.setValue("Mozilla/5.0 THLRedLook/1.0.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://hongguoduanju.com/", forHTTPHeaderField: "Referer")
        }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let active = candidateCookies?.values ?? (existing ? account?.cookies ?? [] : cookies)
        if web {
            let matched = active.filter { $0.valid && (url.path == $0.path || url.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/")) }
            request.setValue(matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            if let csrf = matched.first(where: { $0.name == "passport_csrf_token" && !$0.value.isEmpty }) ?? matched.first(where: { $0.name == "passport_csrf_token_default" && !$0.value.isEmpty }) { request.setValue(csrf.value, forHTTPHeaderField: "x-tt-passport-csrf-token") }
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
            var updated = candidateCookies?.values ?? cookies
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                guard domain == "hongguoduanju.com" else { continue }
                updated.removeAll { $0.name == cookie.name && $0.domain == domain && $0.path == cookie.path }
                let value = HongguoCookie(name: cookie.name, value: cookie.value, domain: domain, path: cookie.path, expires: cookie.expiresDate)
                if value.valid { updated.append(value) }
            }
            if let candidateCookies { candidateCookies.values = updated } else { cookies = updated }
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
