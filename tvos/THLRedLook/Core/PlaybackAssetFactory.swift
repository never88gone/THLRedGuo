import Foundation
import AVFoundation
import ObjectiveC

struct PreparedPlaybackAsset {
    let asset: AVURLAsset
    let decryptedURL: URL?
}

enum PlaybackAssetFactory {
    private static var loaderKey: UInt8 = 0

    static func prepare(_ plan: PlaybackPlan) async throws -> PreparedPlaybackAsset {
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

private final class CENCAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let session: CENCStreamSession
    let queue = DispatchQueue(label: "THLRedLook.CENC.ResourceLoader")
    private let length: Int64
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(session: CENCStreamSession, length: Int64) {
        self.session = session
        self.length = length
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        if let info = request.contentInformationRequest {
            info.contentType = AVFileType.mp4.rawValue
            info.contentLength = length
            info.isByteRangeAccessSupported = true
        }
        guard let data = request.dataRequest else {
            request.finishLoading()
            return true
        }
        let offset = max(data.requestedOffset, data.currentOffset)
        let requested = Int64(data.requestedLength)
        let end = data.requestsAllDataToEndOfResource ? length : min(length, data.requestedOffset + min(requested, length))
        let id = ObjectIdentifier(request)
        let session = self.session
        let queue = self.queue
        let task = Task { [weak self] in
            do {
                var cursor = offset
                while cursor < end {
                    try Task.checkCancellation()
                    let chunk = try await session.read(offset: cursor, count: Int(min(256 * 1024, end - cursor)))
                    try Task.checkCancellation()
                    let accepted: Bool = await withCheckedContinuation { continuation in
                        queue.async {
                            guard !request.isCancelled, !request.isFinished else { continuation.resume(returning: false); return }
                            data.respond(with: chunk)
                            continuation.resume(returning: true)
                        }
                    }
                    guard accepted else { break }
                    cursor += Int64(chunk.count)
                }
                queue.async { [weak self] in
                    if !request.isCancelled, !request.isFinished { request.finishLoading() }
                    self?.tasks.removeValue(forKey: id)
                }
            } catch {
                queue.async { [weak self] in
                    if !request.isCancelled, !request.isFinished { request.finishLoading(with: error) }
                    self?.tasks.removeValue(forKey: id)
                }
            }
        }
        tasks[id] = task
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        tasks.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
        let session = self.session
        Task { await session.close() }
    }
}
