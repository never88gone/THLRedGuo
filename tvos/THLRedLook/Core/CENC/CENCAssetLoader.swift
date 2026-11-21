import Foundation
import AVFoundation

final class CENCAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let session: CENCStreamSession
    let queue = DispatchQueue(label: "THLRedLook.CENC.ResourceLoader")
    private let length: Int64
    weak var asset: AVURLAsset?
    private var reportedFailure = false
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
                    if !request.isCancelled, !request.isFinished {
                        request.finishLoading(with: error)
                        if let self, !self.reportedFailure, !(error is CancellationError), (error as NSError).code != NSURLErrorCancelled {
                            self.reportedFailure = true
                            if let asset = self.asset { NotificationCenter.default.post(name: .encryptedPlaybackFailed, object: asset, userInfo: [NSUnderlyingErrorKey: error]) }
                        }
                    }
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
