import Foundation
import Network
import Combine

@MainActor
final class ApkProfileImportServer: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var message = "正在准备手机导入…"
    @Published private(set) var progress: Double?
    @Published private(set) var importedVersion: String?
    private var listener: NWListener?
    private var clients: [UUID: ApkImportConnection] = [:]
    private var expiry: Task<Void, Never>?
    private var generation = UUID()
    private var importing = false
    private var onImported: (() async -> Void)?

    func start(onImported: @escaping () async -> Void) {
        stop()
        self.onImported = onImported
        let run = generation
        guard let host = DiagnosticsShareServer.localAddress() else {
            message = "未找到局域网地址，请检查电视网络"
            return
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let permit = ApkImportPermit()
        do {
            let server = try NWListener(using: .tcp, on: .any)
            listener = server
            message = "正在准备手机导入…"
            server.stateUpdateHandler = { [weak self, weak server] state in
                MainActor.assumeIsolated {
                    guard let self, self.generation == run else { return }
                    switch state {
                    case .ready:
                        guard let port = server?.port else { return }
                        self.url = URL(string: "http://\(host):\(port.rawValue)/\(token)")
                        self.message = "手机与电视连接同一 Wi-Fi，扫码后选择官方 APK"
                    case .failed:
                        self.stop()
                        self.message = "无法启动手机导入，请关闭后重试"
                    default: break
                    }
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    guard let self, self.generation == run, self.clients.count < 6 else { connection.cancel(); return }
                    let id = UUID()
                    let receiver = ApkImportConnection(connection: connection, token: token, permit: permit, onProgress: { [weak self] value in
                        Task { @MainActor in
                            guard let self, self.generation == run else { return }
                            self.progress = value
                            self.message = "正在接收 APK：\(Int(value * 100))%"
                        }
                    }, onFile: { [weak self] file, client in
                        Task { @MainActor in
                            guard let self, self.generation == run else {
                                try? FileManager.default.removeItem(at: file)
                                client.respond(status: 410, object: ["error": "导入页面已关闭"])
                                return
                            }
                            await self.importFile(file, client: client, run: run)
                        }
                    }, onClose: { [weak self] interrupted in
                        Task { @MainActor in
                            guard let self, self.generation == run else { return }
                            self.clients.removeValue(forKey: id)
                            if interrupted {
                                self.progress = nil
                                self.message = "传输已中断，请在手机上重新选择文件"
                            }
                        }
                    })
                    self.clients[id] = receiver
                    receiver.start()
                }
            }
            server.start(queue: .main)
            expiry = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000_000)
                guard !Task.isCancelled else { return }
                self?.stop()
                self?.message = "导入地址已过期，请返回后重新打开"
            }
        } catch { message = "无法启动手机导入，请关闭后重试" }
    }

    func stop() {
        generation = UUID()
        expiry?.cancel()
        expiry = nil
        listener?.cancel()
        listener = nil
        clients.values.forEach { $0.cancel() }
        clients.removeAll()
        onImported = nil
        importing = false
        url = nil
        progress = nil
    }

    private func importFile(_ file: URL, client: ApkImportConnection, run: UUID) async {
        guard !importing else {
            try? FileManager.default.removeItem(at: file)
            client.respond(status: 409, object: ["error": "另一份 APK 正在校验，请稍后再试"])
            return
        }
        importing = true
        message = "正在校验官方 APK…"
        do {
            let profile = try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: file) }
                return try HongguoApkImporter(url: file).extract()
            }.value
            guard generation == run else { client.respond(status: 410, object: ["error": "导入页面已关闭"]); return }
            try HongguoPlaybackProfileVault.save(profile)
            message = "正在应用播放配置…"
            await onImported?()
            guard generation == run else { return }
            importedVersion = profile.appVersion
            progress = 1
            message = "已导入红果 \(profile.appVersion)，可以返回播放"
            client.respond(status: 200, object: ["imported": true, "appVersion": profile.appVersion])
        } catch {
            guard generation == run else { return }
            message = error.localizedDescription
            progress = nil
            client.respond(status: 422, object: ["error": error.localizedDescription])
        }
        importing = false
    }
}

private final class ApkImportPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var occupied = false

    func acquire() -> Bool {
        lock.withLock {
            guard !occupied else { return false }
            occupied = true
            return true
        }
    }

    func release() { lock.withLock { occupied = false } }
}

private final class ApkImportConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let token: String
    private let queue = DispatchQueue(label: "THLRedGuo.ApkImport", qos: .userInitiated)
    private let onProgress: @Sendable (Double) -> Void
    private let onFile: @Sendable (URL, ApkImportConnection) -> Void
    private let onClose: @Sendable (Bool) -> Void
    private let permit: ApkImportPermit
    private var ownsPermit = false
    private var header = Data()
    private var expected: Int?
    private var received = 0
    private var file: URL?
    private var writer: FileHandle?
    private var watchdog: DispatchWorkItem?
    private var closed = false
    private var lastProgress = Date.distantPast

    init(connection: NWConnection, token: String, permit: ApkImportPermit, onProgress: @escaping @Sendable (Double) -> Void, onFile: @escaping @Sendable (URL, ApkImportConnection) -> Void, onClose: @escaping @Sendable (Bool) -> Void) {
        self.connection = connection
        self.token = token
        self.onProgress = onProgress
        self.onFile = onFile
        self.onClose = onClose
        self.permit = permit
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.close() }
            if case .failed = state { self?.close() }
        }
        connection.start(queue: queue)
        queue.async { self.receive() }
    }

    func cancel() { queue.async { self.close() } }

    func respond(status: Int, object: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        queue.async { self.send(status: status, type: "application/json; charset=utf-8", body: data) }
    }

    private func receive() {
        guard !closed else { return }
        watchdog?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.close() }
        watchdog = timeout
        queue.asyncAfter(deadline: .now() + 30, execute: timeout)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, complete, error in
            guard let self, !self.closed else { return }
            if let content, !content.isEmpty {
                if self.expected != nil { self.append(content) }
                else {
                    self.header.append(content)
                    if let boundary = self.header.range(of: Data("\r\n\r\n".utf8)) {
                        guard boundary.lowerBound <= 16384 else { self.send(status: 431, type: "text/plain", body: Data()); return }
                        let tail = self.header.subdata(in: boundary.upperBound..<self.header.count)
                        let head = self.header.subdata(in: 0..<boundary.lowerBound)
                        self.header.removeAll()
                        guard self.parse(head) else { return }
                        self.append(tail)
                    } else if self.header.count > 16384 { self.send(status: 431, type: "text/plain", body: Data()); return }
                }
            }
            if self.expected == self.received { return }
            if complete || error != nil { self.close() }
            else { self.receive() }
        }
    }

    private func parse(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { close(); return false }
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3 else { close(); return false }
        let path = String(first[1])
        if (first[0] == "GET" || first[0] == "HEAD") && path == "/\(token)" {
            send(status: 200, type: "text/html; charset=utf-8", body: Data(Self.page.utf8), headOnly: first[0] == "HEAD")
            return false
        }
        guard first[0] == "POST", path == "/\(token)/import" else { send(status: 404, type: "text/plain", body: Data()); return false }
        var headers = [String: String]()
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { close(); return false }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard headers.updateValue(value, forKey: key) == nil else { close(); return false }
        }
        guard headers["transfer-encoding"] == nil, let length = headers["content-length"].flatMap(Int.init), (22...314_572_800).contains(length) else {
            send(status: 413, type: "text/plain", body: Data("请选择不超过 300 MB 的 APK".utf8)); return false
        }
        guard permit.acquire() else {
            send(status: 409, type: "application/json", body: Data("{\"error\":\"另一份APK正在导入，请稍后重试\"}".utf8)); return false
        }
        ownsPermit = true
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("THL-APK-import-\(UUID().uuidString).apk")
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            file = url
            writer = try FileHandle(forWritingTo: url)
            expected = length
            return true
        } catch { send(status: 500, type: "text/plain", body: Data("无法接收文件，请检查电视存储空间".utf8)); return false }
    }

    private func append(_ data: Data) {
        guard let expected, data.count <= expected - received, let writer else { close(); return }
        do {
            try writer.write(contentsOf: data)
            received += data.count
            if received == expected || Date().timeIntervalSince(lastProgress) > 0.15 {
                lastProgress = Date()
                onProgress(Double(received) / Double(expected))
            }
            if received == expected {
                watchdog?.cancel()
                try writer.close()
                self.writer = nil
                guard let file else { close(); return }
                self.file = nil
                onFile(file, self)
            }
        } catch { close() }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        watchdog?.cancel()
        try? writer?.close()
        writer = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        let interrupted = ownsPermit && expected.map { received < $0 } == true
        if ownsPermit { permit.release(); ownsPermit = false }
        connection.cancel()
        onClose(interrupted)
    }

    private func send(status: Int, type: String, body: Data, headOnly: Bool = false) {
        guard !closed else { return }
        watchdog?.cancel()
        var output = Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n\r\n".utf8)
        if !headOnly { output.append(body) }
        connection.send(content: output, completion: .contentProcessed { [weak self] _ in self?.close() })
    }

    private static let page = """
    <!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>导入红果官方 APK</title><style>body{font:17px/1.6 system-ui;max-width:640px;margin:32px auto;padding:0 20px;background:#101722;color:#eef3fa}input,button{display:block;font:inherit;margin:24px 0;max-width:100%}button{padding:12px 24px;border:0;border-radius:12px;background:#bf234e;color:white}progress{width:100%}small{color:#bdc8d6}</style><h1>导入红果官方 APK</h1><p>选择手机“文件”中的红果官方 APK。仅发送到当前电视，电视会校验官方签名并提取播放配置。</p><form id="form"><input id="file" type="file" accept=".apk,application/vnd.android.package-archive" required><button id="submit">导入到电视</button></form><progress id="progress" hidden></progress><p id="status" role="status"></p><small>配置仅保存在这台电视，不同步到 iCloud，不包含登录信息。APK 校验后会自动删除。关闭电视上的导入页面，地址即失效。</small><script>const f=document.getElementById('form'),b=document.getElementById('submit'),s=document.getElementById('status'),p=document.getElementById('progress');f.onsubmit=async e=>{e.preventDefault();const file=document.getElementById('file').files[0];if(!file)return;if(file.size>314572800){s.textContent='请选择不超过300 MB的APK';return}b.disabled=true;p.hidden=false;s.textContent='正在传输并校验，请留在此页面…';try{const r=await fetch(location.pathname+'/import',{method:'POST',headers:{'Content-Type':'application/octet-stream'},body:file});const j=await r.json();if(!r.ok||!j.imported)throw Error(j.error||'导入失败，请重试');s.textContent='已导入红果 '+j.appVersion+'，可以返回电视播放'}catch(e){s.textContent=e.message||'连接失败，请确认手机与电视在同一Wi-Fi'}finally{b.disabled=false;p.hidden=true}};</script></html>
    """
}
