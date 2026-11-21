import Foundation

enum CENCMediaDownloader {
    static func download(request: URLRequest, session: URLSession, sizeHint: Int64 = 0, rangeThreshold: Int64 = 4 * 1024 * 1024) async throws -> (URL, URLResponse) {
        var head = request
        head.httpMethod = "HEAD"
        let metadata = try await session.data(for: head).1
        let size = metadata.expectedContentLength > 0 ? metadata.expectedContentLength : sizeHint
        guard size <= 512 * 1024 * 1024 else { throw failure("视频体积超出当前播放准备上限") }
        if size < rangeThreshold || (metadata as? HTTPURLResponse)?.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "none" {
            return try await session.download(for: request)
        }
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("thl_media_" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<4 {
                    let start = size * Int64(index) / 4
                    let end = size * Int64(index + 1) / 4 - 1
                    group.addTask {
                        var part = request
                        part.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                        let (url, response) = try await session.download(for: part)
                        defer { try? FileManager.default.removeItem(at: url) }
                        try Task.checkCancellation()
                        guard let http = response as? HTTPURLResponse else { throw failure("视频分段响应无效") }
                        guard http.statusCode == 206 else { throw failure("片源未提供可用分段", code: http.statusCode == 200 ? -3 : http.statusCode) }
                        guard http.value(forHTTPHeaderField: "Content-Range")?.lowercased() == "bytes \(start)-\(end)/\(size)",
                              (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value == end - start + 1 else {
                            throw failure("视频分段数据不完整")
                        }
                        try FileManager.default.moveItem(at: url, to: workspace.appendingPathComponent("part_\(index)"))
                    }
                }
                try await group.waitForAll()
            }
        } catch {
            if (error as NSError).domain == "CENCMediaDownload", (error as NSError).code == -3, !Task.isCancelled {
                return try await session.download(for: request)
            }
            throw error
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("thl_media_" + UUID().uuidString + ".mp4")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        do {
            let writer = try FileHandle(forWritingTo: output)
            defer { try? writer.close() }
            for index in 0..<4 {
                let reader = try FileHandle(forReadingFrom: workspace.appendingPathComponent("part_\(index)"))
                defer { try? reader.close() }
                while let bytes = try reader.read(upToCount: 1024 * 1024), !bytes.isEmpty {
                    try Task.checkCancellation()
                    try writer.write(contentsOf: bytes)
                }
            }
            guard (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value == size else { throw failure("视频合并校验失败") }
            NSLog("[CENC] verified ranged download bytes=%lld parts=4", size)
            return (output, metadata)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private static func failure(_ message: String, code: Int = -2) -> NSError {
        NSError(domain: "CENCMediaDownload", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
