import Foundation
import Network

@MainActor
final class AccountPairHTTPClient {
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
