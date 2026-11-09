import Foundation

// MARK: - 红果账号登录流程与会话轮询服务类

@MainActor
final class HongguoAccountLoginService {
    private let transportService: HongguoAccountTransport
    private let vault: HongguoAccountVault

    private var loginTask: Task<Void, Never>?
    private var phoneIdentity = ""
    private var phoneCodeSent = false
    private var phoneRetryAt = Date.distantPast
    private var stage = "idle"
    private var token = ""
    private var expiresAt = Date.distantPast
    private var cookies: [HongguoCookie] = []
    private var profileDevice: [String: String]?

    init(transportService: HongguoAccountTransport, vault: HongguoAccountVault = .shared) {
        self.transportService = transportService
        self.vault = vault
    }

    func cancel(onReset: () -> Void) {
        loginTask?.cancel()
        releaseLoginResources()
        onReset()
    }

    private func releaseLoginResources() {
        loginTask = nil
        transportService.cancelTransport()
        cookies = []
        token = ""
        phoneIdentity = ""
        phoneCodeSent = false
    }

    func begin(
        attempt: Int,
        onUpdate: @escaping (String?, Int, Bool, String) -> Void,
        onSuccess: @escaping (HongguoAccountRecord) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let owner = attempt
        stage = "qr"
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: HongguoLoginRedirectDelegate(), delegateQueue: nil)
        transportService.setTransport(session)
        onUpdate(nil, 0, true, "正在获取红果登录二维码")

        loginTask = Task { @MainActor in
            let revision = vault.snapshot.revision
            do {
                let (response, _, _) = try await transportService.call(
                    "qr",
                    owner: owner,
                    attempt: attempt,
                    account: nil,
                    cookies: cookies
                )
                try transportService.check(owner: owner, attempt: attempt)
                guard let value = response["qrUrl"] as? String,
                      let newToken = response["token"] as? String,
                      let expiry = response["expiresAt"] as? NSNumber else {
                    throw HongguoAccountError.invalid
                }
                token = newToken
                expiresAt = expiry.doubleValue > 1_000_000_000 ? Date(timeIntervalSince1970: expiry.doubleValue) : Date().addingTimeInterval(min(600, expiry.doubleValue))
                onUpdate(value, max(0, Int(expiresAt.timeIntervalSinceNow)), false, "等待手机红果 App 扫码确认")
                var tick = 0
                var failures = 0
                while expiresAt > Date() || cookies.contains(where: { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }) {
                    try transportService.check(owner: owner, attempt: attempt)
                    let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))
                    onUpdate(value, remaining, false, "等待手机红果 App 扫码确认")
                    try await Task.sleep(for: .seconds(1))
                    tick += 1
                    guard tick % 2 == 0 else { continue }
                    do {
                        let hasSession = cookies.contains { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }
                        let state = hasSession ? [:] : try await transportService.call(
                            "poll",
                            payload: ["token": token],
                            owner: owner,
                            attempt: attempt,
                            account: nil,
                            cookies: cookies
                        ).result
                        try transportService.check(owner: owner, attempt: attempt)
                        let status = state["status"] as? String ?? ""
                        transportService.trace(phase: "poll", status: status, account: nil, cookies: cookies)
                        if ["5", "expired"].contains(status) { throw HongguoAccountError.expired }
                        if status == "cancelled" { throw HongguoAccountError.cancelled }
                        if ["3", "confirmed"].contains(status), let redirect = state["redirect"] as? String, !redirect.isEmpty {
                            try await transportService.finishRedirect(redirect, owner: owner, attempt: attempt, account: nil, cookies: cookies)
                        }
                        if cookies.contains(where: { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }) {
                            onUpdate(nil, 0, true, "手机已确认，正在校验红果账号")
                            _ = try await transportService.call("webInfo", owner: owner, attempt: attempt, account: nil, cookies: cookies)
                            let (profile, dev, _) = try await transportService.call("profile", owner: owner, attempt: attempt, account: nil, cookies: cookies)
                            try transportService.check(owner: owner, attempt: attempt)
                            guard let id = profile["id"] as? String, !id.isEmpty else { throw HongguoAccountError.invalid }
                            let record = HongguoAccountRecord(
                                id: id,
                                nickname: profile["nickname"] as? String ?? "红果用户",
                                cookies: cookies,
                                device: dev ?? profileDevice,
                                avatar: profile["avatar"] as? String
                            )
                            try vault.save(record, expectedRevision: revision)
                            releaseLoginResources()
                            transportService.trace(phase: "saved", existing: true, account: record, cookies: cookies)
                            token = ""
                            cookies = []
                            onSuccess(record)
                            return
                        }
                        failures = 0
                    } catch {
                        try transportService.check(owner: owner, attempt: attempt)
                        if let issue = error as? HongguoAccountError, issue == .expired || issue == .cancelled { throw issue }
                        transportService.trace(phase: stage, error: error, account: nil, cookies: cookies)
                        failures += 1
                        onUpdate(value, remaining, false, "登录查询暂时失败，正在重试")
                        if failures >= 3 { throw error }
                    }
                }
                throw HongguoAccountError.expired
            } catch {
                if owner == attempt {
                    transportService.trace(phase: stage, error: error, account: nil, cookies: cookies)
                    let errDesc = ((error as? HongguoAccountError)?.localizedDescription ?? "登录请求失败，请稍后重试") + "（阶段：\(stage)）"
                    onError(errDesc)
                }
            }
        }
    }

    private func preparePhone(country: String, number: String, attempt: Int, onCancel: () -> Void) async throws -> Int {
        let identity = country + ":" + number
        if phoneIdentity != identity {
            onCancel()
            phoneIdentity = identity
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 15
            transportService.setTransport(URLSession(configuration: config, delegate: HongguoLoginRedirectDelegate(), delegateQueue: nil))
        }
        let owner = attempt
        if !cookies.contains(where: { $0.valid && ["passport_csrf_token", "passport_csrf_token_default"].contains($0.name) }) {
            _ = try await transportService.call("qr", owner: owner, attempt: attempt, account: nil, cookies: cookies)
        }
        try transportService.check(owner: owner, attempt: attempt)
        return owner
    }

    func sendPhoneCode(country: String, number: String, attempt: Int, busy: Bool, onCancel: () -> Void) async throws -> String {
        guard !busy, phoneRetryAt <= Date() else { throw HongguoAccountError.preparation("SMS_COOLDOWN") }
        let owner = try await preparePhone(country: country, number: number, attempt: attempt, onCancel: onCancel)
        do {
            let (data, _, _) = try await transportService.call("phoneCode", payload: ["country": country, "number": number], owner: owner, attempt: attempt, account: nil, cookies: cookies)
            try transportService.check(owner: owner, attempt: attempt)
            phoneCodeSent = true
            phoneRetryAt = Date().addingTimeInterval((data["retryAfter"] as? NSNumber)?.doubleValue ?? 60)
            return "验证码已发送"
        } catch {
            transportService.trace(phase: stage, error: error, account: nil, cookies: cookies)
            throw error
        }
    }

    func loginPhone(country: String, number: String, code: String, attempt: Int, busy: Bool, onCancel: () -> Void) async throws -> HongguoAccountRecord {
        guard !busy else { throw HongguoAccountError.cancelled }
        let owner = try await preparePhone(country: country, number: number, attempt: attempt, onCancel: onCancel)
        if !phoneCodeSent { throw HongguoAccountError.preparation("SMS_REQUIRED") }
        let revision = vault.snapshot.revision
        do {
            _ = try await transportService.call("phoneSms", payload: ["country": country, "number": number, "code": code], owner: owner, attempt: attempt, account: nil, cookies: cookies)
            try transportService.check(owner: owner, attempt: attempt)
            guard cookies.contains(where: { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }) else { throw HongguoAccountError.invalid }
            _ = try await transportService.call("webInfo", owner: owner, attempt: attempt, account: nil, cookies: cookies)
            let (profile, dev, _) = try await transportService.call("profile", owner: owner, attempt: attempt, account: nil, cookies: cookies)
            try transportService.check(owner: owner, attempt: attempt)
            guard let id = profile["id"] as? String else { throw HongguoAccountError.invalid }
            let record = HongguoAccountRecord(
                id: id,
                nickname: profile["nickname"] as? String ?? "红果用户",
                cookies: cookies,
                device: dev ?? profileDevice,
                avatar: profile["avatar"] as? String
            )
            try vault.save(record, expectedRevision: revision)
            releaseLoginResources()
            transportService.trace(phase: "saved", existing: true, account: record, cookies: cookies)
            return record
        } catch {
            transportService.trace(phase: stage, error: error, account: nil, cookies: cookies)
            throw error
        }
    }

    func prepareTransferred(_ candidate: HongguoAccountRecord, expectedRevision: UInt64, attempt: Int, isCurrent: () -> Bool) async throws -> HongguoVerifiedTransfer {
        let owner = attempt, revision = expectedRevision
        guard revision == vault.snapshot.revision else { throw HongguoAccountError.cancelled }
        let importedCookies = HongguoTransientCookies(candidate.cookies)
        guard isCurrent() else { throw HongguoAccountError.cancelled }
        _ = try await transportService.call("webInfo", owner: owner, attempt: attempt, account: nil, cookies: cookies, candidateCookies: importedCookies)
        guard let device = candidate.device,
              let data = try? JSONSerialization.data(withJSONObject: device),
              let bound = String(data: data, encoding: .utf8) else { throw HongguoAccountError.invalid }
        let (profile, _, _) = try await transportService.call("profile", payload: ["device": bound], owner: owner, attempt: attempt, account: nil, cookies: cookies, candidateCookies: importedCookies)
        try transportService.check(owner: owner, attempt: attempt)
        guard isCurrent(), profile["id"] as? String == candidate.id else { throw HongguoAccountError.invalid }
        let record = HongguoAccountRecord(
            id: candidate.id,
            nickname: profile["nickname"] as? String ?? "红果用户",
            cookies: importedCookies.values,
            device: device,
            avatar: profile["avatar"] as? String
        )
        return HongguoVerifiedTransfer(record: record, revision: revision, owner: owner)
    }

    func commitTransferred(_ transfer: HongguoVerifiedTransfer, attempt: Int, isCurrent: () -> Bool) throws {
        try transportService.check(owner: transfer.owner, attempt: attempt)
        guard isCurrent(), vault.snapshot.revision == transfer.revision else { throw HongguoAccountError.cancelled }
        try vault.save(transfer.record, expectedRevision: transfer.revision)
    }
}
