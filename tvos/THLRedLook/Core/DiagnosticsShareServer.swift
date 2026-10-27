import Foundation
import Network
import Combine
import Darwin

@MainActor
final class DiagnosticsShareServer: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var message = "正在准备手机访问地址…"
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var expiry: Task<Void, Never>?
    private var token = ""
    private var report = ""

    func start(report: String, lifetime: TimeInterval = 600) {
        stop()
        self.report = SourceDiagnostics.redact(report)
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let host = Self.localAddress() else {
            message = "未找到局域网地址，请检查电视网络连接"
            return
        }
        do {
            let server = try NWListener(using: .tcp, on: .any)
            listener = server
            message = "正在准备手机访问地址…"
            server.stateUpdateHandler = { [weak self, weak server] state in
                MainActor.assumeIsolated {
                    guard let self, self.listener === server else { return }
                    switch state {
                    case .ready:
                        guard let port = server?.port else { return }
                        self.url = URL(string: "http://\(host):\(port.rawValue)/\(self.token)")
                        self.message = "手机与电视连接同一 Wi-Fi，扫码打开后可复制或下载日志"
                    case .failed:
                        self.stop()
                        self.message = "无法启动日志分享，请关闭后重试"
                    default: break
                    }
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            server.start(queue: .main)
            expiry = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(1, lifetime) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stop()
                self?.message = "分享已过期，请返回诊断后重新生成二维码"
            }
        } catch {
            message = "无法启动日志分享，请关闭后重试"
        }
    }

    func stop() {
        expiry?.cancel()
        expiry = nil
        listener?.cancel()
        listener = nil
        for connection in clients.values { connection.cancel() }
        clients.removeAll()
        token = ""
        report = ""
        url = nil
    }

    private func accept(_ connection: NWConnection) {
        guard clients.count < 8 else { connection.cancel(); return }
        let id = ObjectIdentifier(connection)
        clients[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            MainActor.assumeIsolated {
                guard let connection else { return }
                if case .cancelled = state { self?.clients.removeValue(forKey: ObjectIdentifier(connection)) }
                if case .failed = state { connection.cancel() }
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak connection] in connection?.cancel() }
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] content, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, let connection else { return }
                var request = buffer
                if let content { request.append(content) }
                if request.count > 16384 { self.send(connection, status: 431, type: "text/plain", body: Data()); return }
                if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                    self.respond(connection, request: request)
                } else if complete || error != nil { connection.cancel() }
                else { self.receive(connection, buffer: request) }
            }
        }
    }

    private func respond(_ connection: NWConnection, request: Data) {
        let line = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET" || parts[0] == "HEAD" else {
            send(connection, status: 405, type: "text/plain", body: Data()); return
        }
        let path = String(parts[1])
        guard !token.isEmpty, path == "/\(token)" || path == "/\(token)/report.txt" else {
            send(connection, status: 404, type: "text/plain", body: Data()); return
        }
        let download = path.hasSuffix("/report.txt")
        let body = Data((download ? report : Self.page(report: report, token: token)).utf8)
        send(connection, status: 200, type: download ? "text/plain; charset=utf-8" : "text/html; charset=utf-8", body: body, head: parts[0] == "HEAD", download: download)
    }

    private func send(_ connection: NWConnection, status: Int, type: String, body: Data, head: Bool = false, download: Bool = false) {
        var header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n"
        if download { header += "Content-Disposition: attachment; filename=THL-diagnostics.txt\r\n" }
        header += "\r\n"
        var response = Data(header.utf8)
        if !head { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    static func page(report: String, token: String) -> String {
        let text = report.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>糖葫芦诊断日志</title><style>body{font:16px/1.6 system-ui;margin:24px;max-width:960px;background:#111827;color:#ecf2fa}button,a{display:inline-block;font:inherit;padding:12px 18px;border:0;border-radius:10px;background:#bf234e;color:white;text-decoration:none;margin:8px 8px 8px 0}textarea{box-sizing:border-box;width:100%;height:60vh;background:#1c2739;color:#ecf2fa;padding:12px;border:1px solid #40516b;border-radius:10px}small{color:#bcc9dd}</style><h1>糖葫芦诊断日志</h1><p>复制日志，或下载文件后通过聊天、邮件手动发送给开发者。</p><button id="copy">复制报告</button><a href="/\(token)/report.txt" download="THL-diagnostics.txt">下载日志文件</a><p id="status" role="status"></p><textarea id="report" readonly>\(text)</textarea><p><small>报告已脱敏，不包含 Cookie、设备凭据或搜索词。关闭电视上的二维码页面后，此链接立即失效；最长有效 10 分钟。不会自动上传。</small></p><script>document.getElementById('copy').onclick=async()=>{const t=document.getElementById('report'),s=document.getElementById('status');try{if(navigator.clipboard&&window.isSecureContext)await navigator.clipboard.writeText(t.value);else{t.focus();t.select();t.setSelectionRange(0,t.value.length);if(!document.execCommand('copy'))throw Error()}s.textContent='已复制，请粘贴发送给开发者'}catch(e){t.focus();t.select();s.textContent='请长按文本选择复制，或下载日志文件'}}</script></html>
        """
    }

    private static func localAddress() -> String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        var addresses: [(String, String)] = []
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard item.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append((String(cString: item.pointee.ifa_name), String(cString: host)))
            }
        }
        return addresses.first(where: { ["en0", "en1"].contains($0.0) })?.1 ?? addresses.first?.1
    }
}
