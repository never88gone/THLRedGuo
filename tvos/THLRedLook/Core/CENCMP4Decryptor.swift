import Foundation
import CryptoKit

/// 负责将 ISO/IEC 23001-7 CENC（AES-128-CTR）加密的 MP4 视频流解密为 Apple 原生 AVPlayer 可直接播放的标准明文 MP4
public final class CENCMP4Decryptor {
    public static let shared = CENCMP4Decryptor()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var inFlightTasks: [String: Task<URL, Error>] = [:]
    private let lock = NSLock()

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = base.appendingPathComponent("DecryptedMedia", isDirectory: true)
        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "mp4" {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    /// 解密给定的视频地址，若已解密则直接返回沙盒本地缓存地址
    public func decrypt(remoteURL: URL, headers: [String: String], hexKey: String, mediaBytes: Int64 = 0) async throws -> URL {
        let cleanKey = hexKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanKey.count == 32, let keyData = dataFromHexString(cleanKey) else {
            throw NSError(domain: "CENCMP4Decryptor", code: -1, userInfo: [NSLocalizedDescriptionKey: "视频内容密钥无效"])
        }

        let identity = Data((cleanKey + "\u{0}" + remoteURL.absoluteString).utf8)
        let cacheKey = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined() + ".mp4"
        let targetFileURL = cacheDirectory.appendingPathComponent(cacheKey)

        if fileManager.fileExists(atPath: targetFileURL.path) {
            if let attrs = try? fileManager.attributesOfItem(atPath: targetFileURL.path),
               let size = attrs[.size] as? Int64, size > 1024 {
                NSLog("🎬 [CENC] 命中文档缓存: %@ (大小: %lld 字节)", targetFileURL.path, size)
                return targetFileURL
            }
        }

        let task: Task<URL, Error> = lock.withLock {
            if let existing = inFlightTasks[cacheKey] {
                return existing
            }
            let newTask = Task.detached(priority: .userInitiated) { () -> URL in
                defer {
                    self.lock.withLock {
                        _ = self.inFlightTasks.removeValue(forKey: cacheKey)
                    }
                }
                return try await self.downloadAndDecrypt(
                    remoteURL: remoteURL,
                    headers: headers,
                    keyBytes: [UInt8](keyData),
                    destinationURL: targetFileURL,
                    mediaBytes: mediaBytes
                )
            }
            inFlightTasks[cacheKey] = newTask
            return newTask
        }

        return try await withTaskCancellationHandler(operation: {
            let url = try await task.value
            if Task.isCancelled {
                self.removePlaybackCache(at: url)
                throw CancellationError()
            }
            return url
        }, onCancel: { task.cancel() })
    }

    public func removePlaybackCache(at url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == cacheDirectory.standardizedFileURL else { return }
        try? fileManager.removeItem(at: url)
    }

    /// 解密已下载到本地临时路径的媒体文件，写入目标路径；若无密钥则直接移动
    public func decryptDownloadedFile(at sourceURL: URL, hexKey: String, destinationURL: URL) throws {
        let cleanKey = hexKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanKey.isEmpty {
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return
        }
        guard cleanKey.count == 32, let keyData = dataFromHexString(cleanKey) else {
            throw NSError(domain: "CENCMP4Decryptor", code: -1, userInfo: [NSLocalizedDescriptionKey: "视频内容密钥无效"])
        }

        var videoData = try Data(contentsOf: sourceURL)
        let keyBytes = [UInt8](keyData)
        let startTime = CFAbsoluteTimeGetCurrent()
        let decrypted = try CENCMP4BoxParser.shared.performInPlaceDecryption(data: &videoData, keyBytes: keyBytes)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard decrypted else { throw NSError(domain: "CENCMP4Decryptor", code: -2, userInfo: [NSLocalizedDescriptionKey: "当前加密媒体格式无法解密"]) }
        try? fileManager.removeItem(at: destinationURL)
        try videoData.write(to: destinationURL, options: .atomic)
        NSLog("🎬 [CENC] 离线下载文件解密完成: decrypted=%d, 耗时: %.2f ms, 目标: %@", decrypted ? 1 : 0, elapsed * 1000, destinationURL.path)
    }

    private func downloadAndDecrypt(
        remoteURL: URL,
        headers: [String: String],
        keyBytes: [UInt8],
        destinationURL: URL,
        mediaBytes: Int64
    ) async throws -> URL {
        NSLog("[CENC] 开始准备媒体")
        var req = URLRequest(url: remoteURL)
        req.timeoutInterval = 30
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (tempDownloadedURL, response) = try await CENCMediaDownloader.download(request: req, session: session, sizeHint: mediaBytes)
        defer { try? fileManager.removeItem(at: tempDownloadedURL) }
        try Task.checkCancellation()
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "CENCMP4Decryptor", code: code, userInfo: [NSLocalizedDescriptionKey: "下载视频流失败，HTTP \(code)"])
        }

        let size = try fileManager.attributesOfItem(atPath: tempDownloadedURL.path)[.size] as? NSNumber
        guard let size, size.int64Value > 0, size.int64Value <= 512 * 1024 * 1024 else {
            throw invalidMedia()
        }
        var videoData = try Data(contentsOf: tempDownloadedURL)
        NSLog("🎬 [CENC] 媒体流下载完成, 大小: %ld 字节, 开始执行 CENC 解密", videoData.count)

        let startTime = CFAbsoluteTimeGetCurrent()
        let decrypted = try CENCMP4BoxParser.shared.performInPlaceDecryption(data: &videoData, keyBytes: keyBytes)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        if decrypted {
            try Task.checkCancellation()
            try videoData.write(to: destinationURL, options: .atomic)
            NSLog("🎬 [CENC] 解密完成! 耗时: %.2f ms, 目标文件: %@", elapsed * 1000, destinationURL.path)
            return destinationURL
        } else {
            throw NSError(domain: "CENCMP4Decryptor", code: -2, userInfo: [NSLocalizedDescriptionKey: "当前加密媒体格式无法解密"])
        }
    }

    func invalidMedia() -> NSError {
        NSError(domain: "CENCMP4Decryptor", code: -2, userInfo: [NSLocalizedDescriptionKey: "加密视频数据不完整或格式不受支持"])
    }

    private func dataFromHexString(_ hex: String) -> Data? {
        var data = Data()
        var hexStr = hex
        while !hexStr.isEmpty {
            let sub = String(hexStr.prefix(2))
            hexStr = String(hexStr.dropFirst(2))
            guard let byte = UInt8(sub, radix: 16) else { return nil }
            data.append(byte)
        }
        return data
    }
}
