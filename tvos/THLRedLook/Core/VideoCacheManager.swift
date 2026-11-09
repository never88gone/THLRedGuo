import Foundation
import AVFoundation

@MainActor
public final class VideoCacheManager {
    public static let shared = VideoCacheManager()
    private var players: [String: AVPlayer] = [:]
    private var order: [String] = []

    private init() {}

    public func getPlayer(for urlString: String, headers: [String: String] = [:], namespace: String = "default") -> AVPlayer {
        let key = "\(namespace)_\(urlString)"
        if let player = players[key] { touch(key); return player }
        guard let url = URL(string: urlString) else { return AVPlayer() }
        let options: [String: Any]? = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        preload(asset: AVURLAsset(url: url, options: options), for: urlString, namespace: namespace)
        return players[key] ?? AVPlayer()
    }

    func takePlayer(for urlString: String, namespace: String) -> AVPlayer? {
        let key = "\(namespace)_\(urlString)"
        order.removeAll { $0 == key }
        let player = players.removeValue(forKey: key)
        player?.isMuted = false
        return player
    }

    func cachedPlayer(for urlString: String, namespace: String) -> AVPlayer? {
        players["\(namespace)_\(urlString)"]
    }

    func preload(asset: AVURLAsset, for urlString: String, namespace: String) {
        let key = "\(namespace)_\(urlString)"
        guard players[key] == nil else { return }
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = true
        players[key] = player
        touch(key)
        let keys = order.filter { $0.hasPrefix("\(namespace)_") }
        for expired in keys.dropLast(3) { discard(expired) }
    }

    public func focusOnVideo(urlString: String, namespace: String = "default") {
        let key = "\(namespace)_\(urlString)"
        players[key]?.isMuted = false
        touch(key)
    }

    public func clearNamespace(_ namespace: String) {
        for key in Array(players.keys) where key.hasPrefix("\(namespace)_") { discard(key) }
    }

    public func clearAll() {
        for key in Array(players.keys) { discard(key) }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func discard(_ key: String) {
        order.removeAll { $0 == key }
        if let player = players.removeValue(forKey: key) {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }
}
