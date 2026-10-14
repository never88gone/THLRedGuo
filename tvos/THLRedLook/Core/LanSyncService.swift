import Foundation
import Network
import Combine
import UIKit

public final class LanSyncService: ObservableObject {
    public static let shared = LanSyncService()

    @Published public private(set) var discoveredDevices: [LanDevice] = []
    @Published public private(set) var isSearching = false
    @Published public var incomingPlayback: LanIncomingPlayback?

    private var browser: NWBrowser?
    private var listener: NWListener?
    private let serviceType = "_zgj-link._tcp"
    private let domain = "local."

    public init() {
        startAdvertising()
        startBrowsing()
    }

    deinit {
        stop()
    }

    public func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: domain)
        let b = NWBrowser(for: descriptor, using: params)

        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            var devices = [LanDevice]()
            for result in results {
                if case let .service(name, type, _, _) = result.endpoint {
                    if !name.contains("AppleTV") {
                        devices.append(LanDevice(id: "\(name)_\(type)", name: name, host: "局域网终端", port: 38473))
                    }
                }
            }
            DispatchQueue.main.async {
                self.discoveredDevices = devices
            }
        }

        b.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.isSearching = (state == .ready)
            }
        }

        b.start(queue: .main)
        self.browser = b
    }

    public func startAdvertising() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let l = try NWListener(using: params)
            let deviceName = "AppleTV-\(UIDevice.current.name)"
            l.service = NWListener.Service(name: deviceName, type: serviceType, domain: domain)

            l.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            l.start(queue: .main)
            self.listener = l
        } catch {
            print("LAN Listener start error: \(error)")
        }
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveData(from: connection)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, _ in
            if let data = content, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self?.processIncomingMessage(json)
            }
            if !isComplete {
                self?.receiveData(from: connection)
            }
        }
    }

    private func processIncomingMessage(_ json: [String: Any]) {
        let action = json["action"] as? String ?? ""
        if action == "handoff" || action == "playback" {
            if let dramaDict = json["drama"] as? [String: Any],
               let dramaData = try? JSONSerialization.data(withJSONObject: dramaDict),
               let drama = try? JSONDecoder().decode(Drama.self, from: dramaData) {
                let epIndex = json["episodeIndex"] as? Int ?? 1
                let pos = json["position"] as? Double ?? 0
                let sender = json["sender"] as? String ?? "手机端"
                DispatchQueue.main.async {
                    self.incomingPlayback = LanIncomingPlayback(drama: drama, episodeIndex: epIndex, position: pos, senderName: sender)
                }
            }
        }
    }

    public func syncWithDevice(_ device: LanDevice) async throws {
        // 与指定设备进行同步模拟或网络请求
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    public func stop() {
        browser?.cancel()
        listener?.cancel()
        browser = nil
        listener = nil
    }
}

