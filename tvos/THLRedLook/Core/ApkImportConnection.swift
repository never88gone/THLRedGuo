import Foundation
import Network

final class ApkImportConnection: @unchecked Sendable {
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
