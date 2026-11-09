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
