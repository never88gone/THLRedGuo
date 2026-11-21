import Foundation
import AVFoundation
import ObjectiveC

extension Notification.Name {
    static let encryptedPlaybackFailed = Notification.Name("THLRedLook.EncryptedPlaybackFailed")
}

enum PlaybackAssetFactory {
    private static var loaderKey: UInt8 = 0

    static func prepare(_ plan: PlaybackPlan) async throws -> PreparedPlaybackAsset {
        guard !PlaybackPlan.isPublicPreviewURL(plan.url) else {
            throw NSError(domain: "THLRedLook.Playback", code: -1, userInfo: [NSLocalizedDescriptionKey: "已拒绝公共试看流，请重新获取完整分集", "diagnosticCode": "PREVIEW_STREAM_REJECTED"])
        }
        guard let url = URL(string: plan.url) else { throw CENCStreamIndex.invalid() }
        guard !plan.decryptionKey.isEmpty else {
            let options: [String: Any] = plan.headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": plan.headers]
            return PreparedPlaybackAsset(asset: AVURLAsset(url: url, options: options), decryptedURL: nil)
        }
        let key = plan.decryptionKey
        guard key.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil else { throw CENCStreamIndex.invalid() }
        let bytes = stride(from: 0, to: 32, by: 2).map { index -> UInt8 in
            let start = key.index(key.startIndex, offsetBy: index)
            return UInt8(key[start..<key.index(start, offsetBy: 2)], radix: 16)!
        }
        let session = CENCStreamSession(url: url, headers: plan.headers, key: bytes)
        do {
            let stats = try await session.prepare()
            try Task.checkCancellation()
            let loader = CENCAssetLoader(session: session, length: stats["mediaBytes"] ?? 0)
            let asset = AVURLAsset(url: URL(string: "thlcenc://\(UUID().uuidString)/video.mp4")!)
            loader.asset = asset
            asset.resourceLoader.setDelegate(loader, queue: loader.queue)
            objc_setAssociatedObject(asset, &loaderKey, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            NSLog("[Stream] prepared bytes=%lld media=%lld requests=%lld", stats["bytesFetched"] ?? 0, stats["mediaBytes"] ?? 0, stats["requests"] ?? 0)
            return PreparedPlaybackAsset(asset: asset, decryptedURL: nil)
        } catch {
            await session.close()
            try Task.checkCancellation()
            NSLog("[Stream] preparing fallback code=%ld", (error as NSError).code)
            let local = try await CENCMP4Decryptor.shared.decrypt(remoteURL: url, headers: plan.headers, hexKey: key, mediaBytes: plan.mediaBytes)
            return PreparedPlaybackAsset(asset: AVURLAsset(url: local), decryptedURL: local)
        }
    }

    static func statistics(for asset: AVAsset) async -> [String: Int64]? {
        guard let loader = objc_getAssociatedObject(asset, &loaderKey) as? CENCAssetLoader else { return nil }
        return await loader.session.statistics()
    }
}
