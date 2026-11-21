import Foundation
import Network
import Combine

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
