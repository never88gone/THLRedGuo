import Foundation
import CryptoKit
import Network
import Combine
import Security

struct AccountPairCipher {
    let id: String
    let key: Data
    let expires: Date
    static func random(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let result = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard result == errSecSuccess else { throw HongguoAccountError.storage }
        return bytes
    }
    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ value: Any?, max: Int) throws -> Data {
        guard let value = value as? String, value.count <= max * 2,
            value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw HongguoAccountError.invalid }
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        guard let bytes = Data(base64Encoded: padded), bytes.count <= max else { throw HongguoAccountError.invalid }
        return bytes
    }
    private func directionKey(_ response: Bool) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: key), salt: Data(id.utf8),
            info: Data((response ? "THL-HAW/ACCOUNT/v1/server" : "THL-HAW/ACCOUNT/v1/client").utf8), outputByteCount: 32)
    }
    private func aad(_ response: Bool) -> Data { Data("THL-HAW/ACCOUNT/v1/\(id)/\(response ? "response" : "request")".utf8) }
    func seal(_ payload: [String: Any], response: Bool) throws -> [String: Any] {
        guard expires > Date() else { throw HongguoAccountError.expired }
        let bytes = try JSONSerialization.data(withJSONObject: payload)
        guard bytes.count <= 68 * 1024 else { throw HongguoAccountError.invalid }
        let box = try AES.GCM.seal(bytes, using: directionKey(response), authenticating: aad(response))
        return ["v": 1, "id": id, "nonce": Self.encode(Data(box.nonce)), "cipher": Self.encode(box.ciphertext), "tag": Self.encode(box.tag)]
    }
    func open(_ envelope: [String: Any], response: Bool) throws -> [String: Any] {
        guard expires > Date(), envelope["v"] as? Int == 1, envelope["id"] as? String == id,
            Set(envelope.keys) == Set(["v", "id", "nonce", "cipher", "tag"]) else { throw HongguoAccountError.invalid }
        let nonce = try Self.decode(envelope["nonce"], max: 12), tag = try Self.decode(envelope["tag"], max: 16)
        guard nonce.count == 12, tag.count == 16 else { throw HongguoAccountError.invalid }
        let cipher = try Self.decode(envelope["cipher"], max: 68 * 1024)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: cipher, tag: tag)
        let data = try AES.GCM.open(box, using: directionKey(response), authenticating: aad(response))
        guard data.count <= 68 * 1024, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HongguoAccountError.invalid }
        return object
    }
    func qr(host: String, port: UInt16, name: String) -> String? {
        var url = URLComponents()
        url.scheme = "thlhaw"; url.host = "account-pair"
        url.queryItems = [URLQueryItem(name: "v", value: "1"), URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "host", value: host), URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "name", value: String(name.prefix(80))), URLQueryItem(name: "expires", value: String(Int(expires.timeIntervalSince1970)))]
        url.fragment = "key=" + Self.encode(key)
        return url.string
    }
}

enum AccountTransferRecord {
    static func decode(_ data: Data) throws -> HongguoAccountRecord {
        guard data.count <= 48 * 1024, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["v"] as? Int == 1, Set(root.keys) == Set(["v", "id", "cookies", "device"]),
            let id = root["id"] as? String, id.range(of: "^[0-9]{1,30}$", options: .regularExpression) != nil,
            let raw = root["cookies"] as? [[String: Any]], !raw.isEmpty, raw.count <= 16,
            let device = root["device"] as? [String: String], Set(device.keys) == Set(["iid", "device_id", "cdid"]),
            let cdid = device["cdid"], !cdid.isEmpty, cdid.count <= 80 else { throw HongguoAccountError.invalid }
        for field in ["iid", "device_id"] {
            guard device[field]?.range(of: "^[0-9]{10,24}$", options: .regularExpression) != nil else { throw HongguoAccountError.invalid }
        }
        var names = Set<String>()
        let cookies = try raw.map { row -> HongguoCookie in
            guard Set(row.keys).isSubset(of: Set(["name", "value", "domain", "path", "expires"])),
                let name = row["name"] as? String, HongguoAccountVault.credentialNames.contains(name), names.insert(name).inserted,
                let value = row["value"] as? String, !value.isEmpty, value.count <= 4096,
                value.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7e && ![34, 44, 59, 92].contains($0.value) }),
                row["domain"] as? String == "hongguoduanju.com", row["path"] as? String == "/" else { throw HongguoAccountError.invalid }
            var expires: Date?
            if let stamp = row["expires"], !(stamp is NSNull) {
                guard let number = stamp as? NSNumber else { throw HongguoAccountError.invalid }
                expires = Date(timeIntervalSince1970: number.doubleValue / 1000)
            }
            return HongguoCookie(name: name, value: value, domain: "hongguoduanju.com", path: "/", expires: expires)
        }
        guard cookies.contains(where: { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }) else { throw HongguoAccountError.invalid }
        return HongguoAccountRecord(id: id, nickname: "", cookies: cookies, device: device)
    }
}

@MainActor
final class AccountPairingServer: ObservableObject {
    @Published private(set) var qr: String?
    @Published private(set) var message = "正在准备设备配对"
    @Published private(set) var accepted = false
    private var listener: NWListener?
    private var clients: [UUID: AccountPairHTTPClient] = [:]
    private var cipher: AccountPairCipher?
    private var expiry: Task<Void, Never>?
    private var generation = UUID()
    private var seen = Set<String>()
    private var processing = false
    private var receiverRevision: UInt64 = 0
    private var prepared: HongguoVerifiedTransfer?
    private var transferID: String?
    private var badRequests = 0
    private var rateWindow = Date()
    var onAccepted: (() -> Void)?
    var approveReplacement: ((String) async -> Bool)?
    private let validator: ((HongguoAccountRecord, UInt64, () -> Bool) async throws -> HongguoVerifiedTransfer)?
    private let committer: ((HongguoVerifiedTransfer, () -> Bool) async throws -> Void)?
    init(validator: ((HongguoAccountRecord, UInt64, () -> Bool) async throws -> HongguoVerifiedTransfer)? = nil,
        committer: ((HongguoVerifiedTransfer, () -> Bool) async throws -> Void)? = nil) { self.validator = validator; self.committer = committer }
    var active: Bool { listener != nil && !accepted && (cipher?.expires ?? .distantPast) > Date() }
    func start() {
        stop(); accepted = false; badRequests = 0; rateWindow = Date(); seen = []; processing = false
        guard let host = DiagnosticsShareServer.localAddress() else { message = "请连接与手机相同的局域网后重试"; return }
        let owner = generation
        receiverRevision = HongguoAccountVault.shared.snapshot.revision
        do {
            let pair = AccountPairCipher(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                key: try AccountPairCipher.random(32), expires: Date().addingTimeInterval(120))
            cipher = pair
            let server = try NWListener(using: .tcp, on: .any)
            listener = server; message = "正在准备设备配对"
            server.stateUpdateHandler = { [weak self, weak server] state in
                MainActor.assumeIsolated {
                    guard let self, self.generation == owner else { return }
                    switch state {
                    case .ready:
                        guard let port = server?.port else { return }
                        self.qr = pair.qr(host: host, port: port.rawValue, name: "糖葫芦 Haw Apple TV")
                        self.message = "请用已登录的手机糖葫芦 Haw 扫码并确认"
                    case .failed: self.stop(); self.message = "无法准备设备配对，请重试"
                    default: break
                    }
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    guard let self, self.generation == owner, self.active, self.clients.count < 4,
                        Self.privateEndpoint(connection.endpoint) else { connection.cancel(); return }
                    let id = UUID()
                    let client = AccountPairHTTPClient(connection: connection, onBody: { [weak self] body, client in
                        guard let self, self.generation == owner else { client.respond(status: 400, body: ["error": "PAIR_INVALID"]); return }
                        self.receive(body, from: client, owner: owner)
                    }, onClose: { [weak self] in self?.clients.removeValue(forKey: id) })
                    self.clients[id] = client; client.start()
                }
            }
            server.start(queue: .main)
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled, let self, self.generation == owner else { return }
                self.stop(); self.message = "配对码已过期，请重新生成"
            }
        } catch { stop(); message = "无法准备设备配对，请重试" }
    }
    private static func privateEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        var bytes: [UInt8]
        switch host {
        case .ipv4(let address): bytes = Array(address.rawValue)
        case .ipv6(let address):
            bytes = Array(address.rawValue)
            if bytes.count == 16 && bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 255 && bytes[11] == 255 { bytes = Array(bytes.suffix(4)) }
        default: return false
        }
        if bytes.count == 4 { return bytes[0] == 10 || bytes[0] == 172 && (16...31).contains(bytes[1]) || bytes[0] == 192 && bytes[1] == 168 || bytes[0] == 169 && bytes[1] == 254 }
        return bytes.count == 16 && ((bytes[0] & 254) == 252 || bytes[0] == 254 && (bytes[1] & 192) == 128)
    }
    private func receive(_ body: Data, from client: AccountPairHTTPClient, owner: UUID) {
        if Date().timeIntervalSince(rateWindow) > 15 { badRequests = 0; rateWindow = Date() }
        guard active, HongguoAccountVault.shared.snapshot.revision == receiverRevision, badRequests < 6, let cipher else { client.respond(status: 400, body: ["error": "PAIR_INVALID"]); return }
        do {
            guard let envelope = try JSONSerialization.jsonObject(with: body) as? [String: Any], let nonce = envelope["nonce"] as? String,
                !seen.contains(nonce), seen.count < 20 else { throw HongguoAccountError.invalid }
            let value = try cipher.open(envelope, response: false)
            seen.insert(nonce)
            guard let requestID = value["requestId"] as? String,
                requestID.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else { throw HongguoAccountError.invalid }
            if value["action"] as? String == "hello", Set(value.keys) == Set(["action", "requestId"]) {
                client.respond(status: 200, body: try cipher.seal(["requestId": requestID, "status": "ready", "name": "糖葫芦 Haw Apple TV"], response: true)); return
            }
            if value["action"] as? String == "commit" {
                guard !processing, let prepared, value["transferId"] as? String == transferID,
                    Set(value.keys) == Set(["action", "requestId", "transferId"]) else { throw HongguoAccountError.invalid }
                processing = true
                Task { [weak self, weak client] in
                    guard let self, let client else { return }
                    var saved = false
                    do {
                        let current = { self.generation == owner && self.active && client.isOpen }
                        if let committer = self.committer { try await committer(prepared, current) }
                        else { try HongguoAccountModel.shared.commitTransferred(prepared, isCurrent: current) }
                        saved = true
                        self.prepared = nil; self.transferID = nil; self.processing = false
                        let reply = try cipher.seal(["requestId": requestID, "status": "accepted"], response: true)
                        client.respond(status: 200, body: reply, completion: { [weak self] in self?.finishAccepted(owner: owner) })
                    } catch {
                        if saved { self.finishAccepted(owner: owner); client.close(); return }
                        guard self.generation == owner else { client.close(); return }
                        self.processing = false; self.prepared = nil; self.transferID = nil
                        if self.generation == owner {
                            self.message = "账号提交未完成，原有账号与本地资料已保留"
                            if let reply = try? cipher.seal(["requestId": requestID, "status": "rejected"], response: true) { client.respond(status: 200, body: reply) }
                            else { client.close() }
                        }
                    }
                }
                return
            }
            guard value["action"] as? String == "session", Set(value.keys) == Set(["action", "requestId", "session"]), !processing, prepared == nil else { throw HongguoAccountError.invalid }
            let candidate = try AccountTransferRecord.decode(AccountPairCipher.decode(value["session"], max: 48 * 1024))
            processing = true; message = "正在校验手机授权的红果账号"
            Task { [weak self, weak client] in
                guard let self, let client else { return }
                var validated: HongguoVerifiedTransfer?
                do {
                    let current = { self.generation == owner && self.active && client.isOpen }
                    if let existing = HongguoAccountVault.shared.snapshot.record, existing.id != candidate.id {
                        guard let approve = self.approveReplacement, await approve(candidate.id), current() else { throw HongguoAccountError.cancelled }
                    }
                    if let validator = self.validator { validated = try await validator(candidate, self.receiverRevision, current) }
                    else { validated = try await HongguoAccountModel.shared.prepareTransferred(candidate, expectedRevision: self.receiverRevision, isCurrent: current) }
                } catch { if self.generation == owner { self.message = "账号校验未通过，原有账号与本地资料已保留" } }
                guard self.generation == owner else { client.close(); return }
                guard self.active, client.isOpen else { self.processing = false; client.close(); return }
                self.prepared = validated; self.transferID = validated == nil ? nil : requestID; self.processing = false
                if validated != nil { self.message = "账号已验证，等待手机提交确认" }
                guard let reply = try? cipher.seal(["requestId": requestID, "status": validated == nil ? "rejected" : "validated"], response: true) else { client.close(); return }
                client.respond(status: 200, body: reply)
            }
        } catch { badRequests += 1; client.respond(status: 400, body: ["error": "PAIR_INVALID"]) }
    }
    private func finishAccepted(owner: UUID) {
        guard generation == owner else { return }
        accepted = true; message = "红果账号已登录"; listener?.cancel(); listener = nil; expiry?.cancel(); qr = nil
        onAccepted?()
    }
    func stop() {
        generation = UUID(); prepared = nil; transferID = nil; expiry?.cancel(); expiry = nil; listener?.cancel(); listener = nil; qr = nil; cipher = nil
        let active = clients.values; clients = [:]; for client in active { client.close() }
    }
}

@MainActor
private final class AccountPairHTTPClient {
    let connection: NWConnection
    private var buffer = Data()
    private var length: Int?
    private var closed = false
    var isOpen: Bool { !closed }
    private var readExpiry: Task<Void, Never>?
    private let onBody: (Data, AccountPairHTTPClient) -> Void
    private let onClose: () -> Void
    init(connection: NWConnection, onBody: @escaping (Data, AccountPairHTTPClient) -> Void, onClose: @escaping () -> Void) {
        self.connection = connection; self.onBody = onBody; self.onClose = onClose
    }
    func start() {
        connection.start(queue: .main)
        readExpiry = Task { [weak self] in try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { self?.close() } }
        read()
    }
    private func read() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                if let data { self.buffer.append(data) }
                do {
                    guard self.buffer.count <= 104 * 1024 else { throw HongguoAccountError.invalid }
                    if self.length == nil {
                        if let end = self.buffer.range(of: Data("\r\n\r\n".utf8)) {
                            guard end.upperBound <= 4096, let header = String(data: self.buffer[..<end.lowerBound], encoding: .utf8) else { throw HongguoAccountError.invalid }
                            let lines = header.components(separatedBy: "\r\n")
                            guard let first = lines.first, ["POST /thl/account-pair/v1 HTTP/1.1", "POST /thl/account-pair/v1 HTTP/1.0"].contains(first) else { throw HongguoAccountError.invalid }
                            var fields: [String: String] = [:]
                            for line in lines.dropFirst() {
                                guard let colon = line.firstIndex(of: ":") else { throw HongguoAccountError.invalid }
                                let name = line[..<colon].lowercased(), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                                guard fields[name] == nil else { throw HongguoAccountError.invalid }
                                fields[name] = value
                            }
                            guard fields["origin"] == nil, fields["transfer-encoding"] == nil,
                                fields["content-type"]?.lowercased().hasPrefix("application/json") == true,
                                let raw = fields["content-length"], raw.range(of: "^[0-9]{1,6}$", options: .regularExpression) != nil,
                                let count = Int(raw), count > 0, count <= 100 * 1024 else { throw HongguoAccountError.invalid }
                            self.length = count; self.buffer.removeSubrange(..<end.upperBound)
                        } else if self.buffer.count > 4096 { throw HongguoAccountError.invalid }
                    }
                    if let count = self.length, self.buffer.count >= count {
                        guard self.buffer.count == count else { throw HongguoAccountError.invalid }
                        self.readExpiry?.cancel(); self.onBody(self.buffer, self); self.buffer = Data(); self.monitorDisconnect(); return
                    }
                    if complete || error != nil { self.close() } else { self.read() }
                } catch { self.respond(status: 400, body: ["error": "PAIR_INVALID"]) }
            }
        }
    }
    private func monitorDisconnect() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                if complete || error != nil || data?.isEmpty == false { self.close() }
                else { self.monitorDisconnect() }
            }
        }
    }
    func respond(status: Int, body: [String: Any], completion: (() -> Void)? = nil) {
        guard !closed, let bytes = try? JSONSerialization.data(withJSONObject: body) else { close(); return }
        readExpiry?.cancel()
        var data = Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Bad Request")\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n".utf8)
        data.append(bytes)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in MainActor.assumeIsolated { self?.close(); completion?() } })
    }
    func close() { guard !closed else { return }; closed = true; readExpiry?.cancel(); connection.cancel(); onClose() }
}
