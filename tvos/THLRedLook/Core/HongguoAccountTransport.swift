import Foundation

// MARK: - 红果官方账号接口网络传输与 RPC 调度服务类

final class HongguoAccountTransport: @unchecked Sendable {
    private var transport: URLSession?
    private var lastTrace = ""

    func setTransport(_ session: URLSession?) {
        self.transport = session
    }

    func cancelTransport() {
        transport?.finishTasksAndInvalidate()
        transport = nil
    }

    func check(owner: Int, attempt: Int) throws {
        if Task.isCancelled || owner != attempt {
            throw HongguoAccountError.cancelled
        }
    }

    func trace(
        phase: String,
        status: String = "",
        error: Error? = nil,
        existing: Bool = false,
        account: HongguoAccountRecord?,
        cookies: [HongguoCookie]
    ) {
        let safeStatus = ["0", "1", "2", "3", "4", "5", "new", "scanned", "confirmed", "expired", "cancelled"].contains(status) ? status : status.isEmpty ? "" : "unknown"
        let session = (existing ? account?.cookies ?? [] : cookies).contains { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }
        let issue = error as? HongguoAccountError
        let code: String
        switch issue {
        case .business(let value): code = "BUSINESS_\(value)"
        case .followSecurity: code = "BUSINESS_103012"
        case .server(let value): code = "HTTP_\(value)"
        case .expired: code = "QR_EXPIRED"
        case .challenge: code = "CHALLENGE_REQUIRED"
        case .cancelled: code = "CANCELLED"
        case .storage: code = "STORAGE"
        case .invalid, .interactionInvalid: code = "INVALID_RESPONSE"
        case .preparation(let value): code = value
        default: code = error == nil ? "" : "NETWORK"
        }
        let summary = "phase=\(phase) status=\(safeStatus) session=\(session) error=\(code)"
        guard summary != lastTrace else { return }
        lastTrace = summary
        NSLog("[Account] %@", summary)
        SourceDiagnostics.shared.add(SourceDiagnosticEntry(context: phase == "creatorFollow" ? "红果作者关注" : "红果登录", stage: phase, errorCode: code, sessionStatus: "status=\(safeStatus) session=\(session)"))
    }

    func call(
        _ action: String,
        payload: [String: String] = [:],
        owner: Int,
        attempt: Int,
        existing: Bool = false,
        account: HongguoAccountRecord?,
        cookies: [HongguoCookie],
        candidateCookies: HongguoTransientCookies? = nil
    ) async throws -> (result: [String: Any], profileDevice: [String: String]?, updatedCookies: [HongguoCookie]?) {
        try check(owner: owner, attempt: attempt)
        let vault = HongguoAccountVault.shared
        let revision = vault.snapshot.revision
        let command = try await NativeBridge.shared.accountRequest(action, payload: payload)
        guard !existing || vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        guard let value = command["url"] as? String, let url = URL(string: value) else { throw HongguoAccountError.invalid }
        var detectedDevice: [String: String]?
        if action == "profile", let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            detectedDevice = Dictionary(uniqueKeysWithValues: query.filter { ["iid", "device_id", "cdid"].contains($0.name) && $0.value != nil }.map { ($0.name, $0.value!) })
        }
        let (body, newCookies) = try await request(
            url,
            headers: command["headers"] as? [String: String] ?? [:],
            owner: owner,
            attempt: attempt,
            existing: existing,
            account: account,
            cookies: cookies,
            method: command["method"] as? String ?? "GET",
            form: command["body"] as? String,
            candidateCookies: candidateCookies,
            diagnosticAction: action
        )
        guard !existing || vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        let result: [String: Any]
        do {
            result = try await NativeBridge.shared.accountParse(action, body: body)
        } catch {
            trace(phase: action, error: error, existing: existing, account: account, cookies: cookies)
            throw error
        }
        guard !existing || vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        if action != "poll" {
            trace(phase: action, existing: existing, account: account, cookies: cookies)
        }
        return (result, detectedDevice, newCookies)
    }

    func request(
        _ url: URL,
        headers: [String: String],
        owner: Int,
        attempt: Int,
        existing: Bool = false,
        account: HongguoAccountRecord?,
        cookies: [HongguoCookie],
        method: String = "GET",
        form: String? = nil,
        candidateCookies: HongguoTransientCookies? = nil,
        diagnosticAction: String? = nil
    ) async throws -> (body: String, updatedCookies: [HongguoCookie]?) {
        try check(owner: owner, attempt: attempt)
        let started = ProcessInfo.processInfo.systemUptime
        let web = url.scheme == "https" && url.host == "hongguoduanju.com" && url.port == nil
        guard web || HongguoAccountVault.businessURL(url) else { throw HongguoAccountError.invalid }
        guard ["GET", "POST"].contains(method) else { throw HongguoAccountError.invalid }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.httpMethod = method
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
        let vault = HongguoAccountVault.shared
        if web {
            let matched = active.filter { $0.valid && (url.path == $0.path || url.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/")) }
            request.setValue(matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            if let csrf = matched.first(where: { $0.name == "passport_csrf_token" && !$0.value.isEmpty }) ?? matched.first(where: { $0.name == "passport_csrf_token_default" && !$0.value.isEmpty }) {
                request.setValue(csrf.value, forHTTPHeaderField: "x-tt-passport-csrf-token")
            }
        } else {
            let record = HongguoAccountRecord(id: "", nickname: "", cookies: active)
            request.setValue(vault.header(for: url, record: record), forHTTPHeaderField: "Cookie")
        }
        let session = transport ?? URLSession(configuration: .ephemeral, delegate: HongguoLoginRedirectDelegate(), delegateQueue: nil)
        let (data, raw) = try await session.data(for: request)
        try check(owner: owner, attempt: attempt)
        guard let response = raw as? HTTPURLResponse, data.count <= 2 * 1024 * 1024 else { throw HongguoAccountError.invalid }
        if diagnosticAction == "creatorFollow", url.path == "/novel/commentapi/comment/do_action/v1/" {
            let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let rawCode = SourceDiagnostics.safeCode(parsed?["code"])
            let business = rawCode.range(of: "^-?[0-9]{1,9}$", options: .regularExpression) != nil ? rawCode : ""
            let risk = response.statusCode == 200 && business == "103012"
            let logId = response.value(forHTTPHeaderField: "x-tt-logid") ?? ""
            let gateway = response.value(forHTTPHeaderField: "x-tt-agw-login") ?? ""
            let location = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let endpoint = (location?.scheme ?? "https") + "://" + (location?.host ?? "") + (location?.path ?? "")
            let errorCode = response.statusCode != 200 ? "HTTP_\(response.statusCode)" : business.isEmpty ? "INVALID_RESPONSE" : business != "0" ? "BUSINESS_\(business)" : ""
            let sessionState = "session=\(account?.hasSession == true) boundDevice=\(account?.device != nil)" + (["0", "1"].contains(gateway) ? " gatewayLogin=\(gateway)" : "")
            SourceDiagnostics.shared.add(SourceDiagnosticEntry(
                context: "红果作者关注",
                stage: "creatorFollow",
                host: url.host ?? "",
                url: endpoint,
                method: method,
                logId: logId.range(of: "^[0-9A-Fa-f]{16,64}$", options: .regularExpression) != nil ? logId : "",
                status: response.statusCode,
                businessCode: business,
                errorCode: errorCode,
                elapsedMs: Int(max(0, (ProcessInfo.processInfo.systemUptime - started) * 1000)),
                category: risk ? .businessRejected : .unknown,
                errorDetail: risk ? "官方评论接口返回 HitSharkRule，具体触发条件未提供" : "",
                sessionStatus: sessionState
            ))
        }
        var returnedCookies: [HongguoCookie]?
        if web && !existing {
            let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                result[String(describing: pair.key)] = String(describing: pair.value)
            }
            var updated = candidateCookies?.values ?? cookies
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                guard domain == "hongguoduanju.com" else { continue }
                updated.removeAll { $0.name == cookie.name && $0.domain == domain && $0.path == cookie.path }
                let value = HongguoCookie(name: cookie.name, value: cookie.value, domain: domain, path: cookie.path, expires: cookie.expiresDate)
                if value.valid { updated.append(value) }
            }
            if let candidateCookies { candidateCookies.values = updated } else { returnedCookies = updated }
        }
        if [301, 302, 303, 307, 308].contains(response.statusCode), let next = response.value(forHTTPHeaderField: "Location"), web {
            return ("redirect:" + next, returnedCookies)
        }
        guard response.statusCode == 200 else { throw HongguoAccountError.server(response.statusCode) }
        guard !data.isEmpty, let body = String(data: data, encoding: .utf8) else { throw HongguoAccountError.invalid }
        return (body, returnedCookies)
    }

    func finishRedirect(
        _ value: String,
        owner: Int,
        attempt: Int,
        account: HongguoAccountRecord?,
        cookies: [HongguoCookie]
    ) async throws {
        var next = value
        for _ in 0..<5 {
            guard let url = URL(string: next, relativeTo: URL(string: "https://hongguoduanju.com/"))?.absoluteURL,
                  url.scheme == "https", url.host == "hongguoduanju.com", url.port == nil else {
                throw HongguoAccountError.invalid
            }
            let (body, _) = try await request(url, headers: [:], owner: owner, attempt: attempt, account: account, cookies: cookies)
            if !body.hasPrefix("redirect:") { return }
            next = String(body.dropFirst(9))
        }
        throw HongguoAccountError.invalid
    }
}
