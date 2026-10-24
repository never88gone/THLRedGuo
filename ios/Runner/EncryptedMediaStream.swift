import Foundation
#if canImport(Flutter)
import Flutter
#endif
import AVFoundation

private final class CENCRangeLoader: NSObject, URLSessionDataDelegate {
    struct Response {
        let data: Data
        let total: Int64
    }
    private final class Transfer {
        let offset: Int64
        let count: Int
        let continuation: CheckedContinuation<Response, Error>
        var data = Data()
        var total: Int64 = 0
        var failure: Error?
        init(_ offset: Int64, _ count: Int, _ continuation: CheckedContinuation<Response, Error>) {
            self.offset = offset
            self.count = count
            self.continuation = continuation
        }
    }
    private let url: URL
    private let headers: [String: String]
    private let lock = NSLock()
    private var transfers = [Int: Transfer]()
    private var session: URLSession!
    private var closed = false
    private var fetched: Int64 = 0
    private var requests = 0

    init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func fetch(offset: Int64, count: Int) async throws -> Response {
        guard offset >= 0, count > 0, count <= 8 * 1024 * 1024 else { throw CENCStreamIndex.invalid() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !closed else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            var request = URLRequest(url: url)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            request.setValue("bytes=\(offset)-\(offset + Int64(count) - 1)", forHTTPHeaderField: "Range")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let task = session.dataTask(with: request)
            transfers[task.taskIdentifier] = Transfer(offset, count, continuation)
            requests += 1
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        guard let transfer = transfers[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else {
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        var valid = false
        if http.statusCode == 206, let value = http.value(forHTTPHeaderField: "Content-Range"), value.hasPrefix("bytes ") {
            let parts = value.dropFirst(6).split(separator: "/")
            if parts.count == 2 {
                let range = parts[0].split(separator: "-")
                if range.count == 2, let start = Int64(range[0]), let end = Int64(range[1]), let total = Int64(parts[1]) {
                    valid = start == transfer.offset && end >= start && total > end && end - start + 1 <= Int64(transfer.count) && total <= 512 * 1024 * 1024
                    transfer.total = total
                }
            }
        } else if http.statusCode == 200, transfer.offset == 0, response.expectedContentLength > 0, response.expectedContentLength <= Int64(transfer.count) {
            transfer.total = response.expectedContentLength
            valid = true
        }
        if let encoding = http.value(forHTTPHeaderField: "Content-Encoding"), encoding.lowercased() != "identity" { valid = false }
        if !valid {
            transfer.failure = NSError(domain: "THLEncryptedStream", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "媒体服务器未返回有效的分段数据（HTTP \(http.statusCode)）"])
        }
        lock.unlock()
        completionHandler(valid ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        fetched += Int64(data.count)
        guard let transfer = transfers[dataTask.taskIdentifier] else { lock.unlock(); return }
        if data.count > transfer.count - transfer.data.count {
            transfer.failure = CENCStreamIndex.invalid()
            lock.unlock()
            dataTask.cancel()
            return
        }
        transfer.data.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let transfer = transfers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let transfer else { return }
        if let failure = transfer.failure ?? error {
            transfer.continuation.resume(throwing: failure)
        } else if transfer.total > 0, transfer.data.count == min(transfer.count, Int(transfer.total - transfer.offset)) {
            transfer.continuation.resume(returning: Response(data: transfer.data, total: transfer.total))
        } else {
            transfer.continuation.resume(throwing: CENCStreamIndex.invalid())
        }
    }

    func statistics() -> [String: Int64] {
        lock.lock()
        defer { lock.unlock() }
        return ["bytesFetched": fetched, "requests": Int64(requests), "activeRequests": Int64(transfers.count)]
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
        session.invalidateAndCancel()
    }
}

actor CENCStreamSession {
    private let loader: CENCRangeLoader
    private let key: [UInt8]
    private var length: Int64 = 0
    private var index: CENCStreamIndex?
    private var prefix = Data()
    private var closed = false
    private let blockSize = 256 * 1024
    private var blocks = [Int64: Data]()
    private var order = [Int64]()
    private var pending = [Int64: Task<Data, Error>]()
    private var hits: Int64 = 0

    init(url: URL, headers: [String: String], key: [UInt8]) {
        self.loader = CENCRangeLoader(url: url, headers: headers)
        self.key = key
    }

    func prepare() async throws -> [String: Int64] {
        let initial = try await loader.fetch(offset: 0, count: 64 * 1024)
        try check()
        length = initial.total
        prefix = initial.data
        guard initial.data.count >= 16, ["ftyp", "styp"].contains(CENCStreamIndex.fourCC(initial.data, 4)) else { throw CENCStreamIndex.invalid() }
        var offset: Int64 = 0
        var count = 0
        while offset + 8 <= length, count < 128 {
            try check()
            let header: Data
            if offset + 16 <= Int64(initial.data.count) {
                header = initial.data.subdata(in: Int(offset)..<Int(offset) + 16)
            } else {
                header = try await loader.fetch(offset: offset, count: Int(min(16, length - offset))).data
            }
            guard header.count >= 8 else { throw CENCStreamIndex.invalid() }
            let rawSize = CENCStreamIndex.read32(header, 0)
            let headerSize = rawSize == 1 ? 16 : 8
            guard header.count >= headerSize else { throw CENCStreamIndex.invalid() }
            let rawLength = rawSize == 1 ? CENCStreamIndex.read64(header, 8) : rawSize == 0 ? UInt64(length - offset) : UInt64(rawSize)
            guard rawLength >= UInt64(headerSize), rawLength <= UInt64(length - offset) else { throw CENCStreamIndex.invalid() }
            let type = CENCStreamIndex.fourCC(header, 4)
            guard type != "moof" else { throw CENCStreamIndex.invalid() }
            if type == "moov" {
                guard rawLength <= 8 * 1024 * 1024 else { throw CENCStreamIndex.invalid() }
                let data: Data
                if offset + Int64(rawLength) <= Int64(initial.data.count) {
                    data = initial.data.subdata(in: Int(offset)..<Int(offset) + Int(rawLength))
                } else {
                    let response = try await loader.fetch(offset: offset, count: Int(rawLength))
                    guard response.total == length else { throw CENCStreamIndex.invalid() }
                    data = response.data
                }
                try check()
                index = try CENCStreamIndex(data: data, offset: offset, fileSize: length)
                return statistics()
            }
            offset += Int64(rawLength)
            count += 1
        }
        throw CENCStreamIndex.invalid()
    }

    func read(offset: Int64, count: Int) async throws -> Data {
        try check()
        guard let index, offset >= 0, offset < length, count > 0, count <= 1024 * 1024 else { throw CENCStreamIndex.invalid() }
        let end = min(length, offset + Int64(count))
        var cursor = offset
        var result = Data()
        result.reserveCapacity(Int(end - offset))
        while cursor < end {
            if cursor < Int64(prefix.count) {
                let finish = min(end, Int64(prefix.count))
                result.append(prefix[Int(cursor)..<Int(finish)])
                cursor = finish
                continue
            }
            if cursor >= index.moovOffset, cursor < index.moovOffset + Int64(index.moov.count) {
                let finish = min(end, index.moovOffset + Int64(index.moov.count))
                result.append(index.moov[Int(cursor - index.moovOffset)..<Int(finish - index.moovOffset)])
                cursor = finish
                continue
            }
            let blockStart = cursor / Int64(blockSize) * Int64(blockSize)
            let data = try await block(blockStart)
            try check()
            let local = Int(cursor - blockStart)
            let amount = min(data.count - local, Int(end - cursor), cursor < index.moovOffset ? Int(index.moovOffset - cursor) : Int(end - cursor))
            guard amount > 0 else { throw CENCStreamIndex.invalid() }
            result.append(data[local..<local + amount])
            cursor += Int64(amount)
        }
        return try index.decrypt(result, offset: offset, key: key)
    }

    private func block(_ offset: Int64) async throws -> Data {
        if let cached = blocks[offset] {
            hits += 1
            touch(offset)
            return cached
        }
        let task: Task<Data, Error>
        if let existing = pending[offset] {
            hits += 1
            task = existing
        } else {
            let loader = self.loader
            let count = Int(min(Int64(blockSize), length - offset))
            let expected = length
            task = Task {
                let response = try await loader.fetch(offset: offset, count: count)
                guard response.total == expected else { throw CENCStreamIndex.invalid() }
                return response.data
            }
            pending[offset] = task
        }
        do {
            let data = try await task.value
            pending.removeValue(forKey: offset)
            try check()
            blocks[offset] = data
            touch(offset)
            while order.count > 12 {
                let oldest = order.removeFirst()
                blocks.removeValue(forKey: oldest)
            }
            return data
        } catch {
            pending.removeValue(forKey: offset)
            throw error
        }
    }

    private func touch(_ offset: Int64) {
        order.removeAll { $0 == offset }
        order.append(offset)
    }

    private func check() throws {
        try Task.checkCancellation()
        if closed { throw CancellationError() }
    }

    func statistics() -> [String: Int64] {
        var result = loader.statistics()
        result["mediaBytes"] = length
        result["cachedBytes"] = Int64(blocks.values.reduce(0) { $0 + $1.count })
        result["cacheHits"] = hits
        return result
    }

    func close() {
        closed = true
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        blocks.removeAll()
        order.removeAll()
        prefix = Data()
        index = nil
        loader.close()
    }
}

#if canImport(Flutter)
final class EncryptedMediaStream {
    private let lock = NSLock()
    private var sessions = [String: CENCStreamSession]()

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "audioStatus" {
            let audio = AVAudioSession.sharedInstance()
            result(["category": audio.category.rawValue, "outputVolume": audio.outputVolume, "outputs": audio.currentRoute.outputs.map { $0.portType.rawValue }])
            return
        }
        let arguments = call.arguments as? [String: Any] ?? [:]
        let id = arguments["id"] as? String ?? ""
        if call.method == "open" {
            let key = arguments["key"] as? String ?? ""
            let rawURL = arguments["url"] as? String ?? ""
            guard id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
                  key.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil,
                  let url = URL(string: rawURL), url.host != nil, (url.scheme == "https" || url.scheme == "http" && ["127.0.0.1", "::1"].contains(url.host!)) else {
                result(FlutterError(code: "ios_stream_input", message: "加密媒体参数无效", details: nil))
                return
            }
            let bytes = stride(from: 0, to: 32, by: 2).map { index -> UInt8 in
                let start = key.index(key.startIndex, offsetBy: index)
                return UInt8(key[start..<key.index(start, offsetBy: 2)], radix: 16)!
            }
            let session = CENCStreamSession(url: url, headers: arguments["headers"] as? [String: String] ?? [:], key: bytes)
            lock.lock()
            let previous = sessions.updateValue(session, forKey: id)
            lock.unlock()
            Task {
                await previous?.close()
                do {
                    let value = try await session.prepare()
                    await MainActor.run { result(value) }
                } catch {
                    await session.close()
                    self.remove(id, session)
                    await MainActor.run { result(self.failure(error)) }
                }
            }
            return
        }
        lock.lock()
        let session = call.method == "close" ? sessions.removeValue(forKey: id) : sessions[id]
        lock.unlock()
        guard let session else {
            result(call.method == "close" ? true : FlutterError(code: "ios_stream_closed", message: "播放准备已取消", details: nil))
            return
        }
        Task {
            do {
                switch call.method {
                case "read":
                    let offset = (arguments["offset"] as? NSNumber)?.int64Value ?? -1
                    let count = (arguments["count"] as? NSNumber)?.intValue ?? 0
                    let data = try await session.read(offset: offset, count: count)
                    await MainActor.run { result(FlutterStandardTypedData(bytes: data)) }
                case "stats":
                    let value = await session.statistics()
                    await MainActor.run { result(value) }
                case "close":
                    await session.close()
                    await MainActor.run { result(true) }
                default:
                    await MainActor.run { result(FlutterMethodNotImplemented) }
                }
            } catch {
                await MainActor.run { result(self.failure(error)) }
            }
        }
    }

    private func remove(_ id: String, _ session: CENCStreamSession) {
        lock.lock()
        if sessions[id] === session { sessions.removeValue(forKey: id) }
        lock.unlock()
    }

    private func failure(_ error: Error) -> FlutterError {
        let error = error as NSError
        let message = error.domain == "THLEncryptedStream" ? error.localizedDescription : "媒体分段请求失败（\(error.code)），请重试"
        return FlutterError(code: "ios_stream_\(error.code)", message: message, details: nil)
    }
}
#endif
