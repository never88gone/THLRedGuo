import Foundation
import CommonCrypto
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
        let decrypted = try performInPlaceDecryption(data: &videoData, keyBytes: keyBytes)
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

        defer {
            try? fileManager.removeItem(at: tempDownloadedURL)
        }

        let size = try fileManager.attributesOfItem(atPath: tempDownloadedURL.path)[.size] as? NSNumber
        guard let size, size.int64Value > 0, size.int64Value <= 512 * 1024 * 1024 else {
            throw invalidMedia()
        }
        var videoData = try Data(contentsOf: tempDownloadedURL)
        NSLog("🎬 [CENC] 媒体流下载完成, 大小: %ld 字节, 开始执行 CENC 解密", videoData.count)

        let startTime = CFAbsoluteTimeGetCurrent()
        let decrypted = try performInPlaceDecryption(data: &videoData, keyBytes: keyBytes)
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

    // MARK: - 二进制 MP4 ISO BMFF 解析与解密核心
    private struct Box {
        let type: String
        let offset: Int
        let size: Int
        let headerSize: Int
    }

    private struct STSCEntry {
        let firstChunk: UInt32
        let samplesPerChunk: UInt32
        let sampleDescIndex: UInt32
    }

    private func parseBoxes(data: Data, start: Int, end: Int) -> [Box] {
        var boxes = [Box]()
        var curr = start
        while curr + 8 <= end {
            let size = Int(data.readUInt32(at: curr))
            let typeData = data.subdata(in: curr+4..<curr+8)
            let typeStr = String(data: typeData, encoding: .ascii) ?? "????"
            var actualSize = size
            var headerSize = 8
            if size == 1 {
                if curr + 16 > end { break }
                let length = data.readUInt64(at: curr + 8)
                guard length <= UInt64(end - curr) else { break }
                actualSize = Int(length)
                headerSize = 16
            } else if size == 0 {
                actualSize = end - curr
            }
            if actualSize < headerSize || actualSize > end - curr { break }
            boxes.append(Box(type: typeStr, offset: curr, size: actualSize, headerSize: headerSize))
            curr += actualSize
        }
        return boxes
    }

    private func findChildBox(data: Data, parent: Box, target: String) -> Box? {
        let children = parseBoxes(data: data, start: parent.offset + parent.headerSize, end: parent.offset + parent.size)
        return children.first { $0.type == target }
    }

    private func performInPlaceDecryption(data: inout Data, keyBytes: [UInt8]) throws -> Bool {
        let topBoxes = parseBoxes(data: data, start: 0, end: data.count)
        guard let moov = topBoxes.first(where: { $0.type == "moov" }) else {
            return false
        }

        var anyDecrypted = false
        let moovChildren = parseBoxes(data: data, start: moov.offset + moov.headerSize, end: moov.offset + moov.size)
        for trak in moovChildren where trak.type == "trak" {
            if try decryptTrack(data: &data, trak: trak, keyBytes: keyBytes) {
                anyDecrypted = true
            }
        }
        return anyDecrypted
    }

    private func decryptTrack(data: inout Data, trak: Box, keyBytes: [UInt8]) throws -> Bool {
        guard let mdia = findChildBox(data: data, parent: trak, target: "mdia"),
              let minf = findChildBox(data: data, parent: mdia, target: "minf"),
              let stbl = findChildBox(data: data, parent: minf, target: "stbl") else {
            return false
        }

        let stblBoxes = parseBoxes(data: data, start: stbl.offset + stbl.headerSize, end: stbl.offset + stbl.size)
        guard let stsdBox = stblBoxes.first(where: { $0.type == "stsd" }) else { return false }
        let stsdOff = stsdBox.offset + stsdBox.headerSize
        guard stsdOff + 16 <= stsdBox.offset + stsdBox.size else { throw invalidMedia() }
        let entryType = String(data: data.subdata(in: stsdOff+12..<stsdOff+16), encoding: .ascii) ?? ""
        guard entryType == "encv" || entryType == "enca" else { return false }
        guard let stszBox = stblBoxes.first(where: { $0.type == "stsz" }),
              let stscBox = stblBoxes.first(where: { $0.type == "stsc" }),
              let sencBox = stblBoxes.first(where: { $0.type == "senc" }) else { throw invalidMedia() }
        let stcoBox = stblBoxes.first(where: { $0.type == "stco" })
        let co64Box = stblBoxes.first(where: { $0.type == "co64" })
        if stcoBox == nil && co64Box == nil { throw invalidMedia() }
        var ivSize = 8
        var originalFormatFound = false

        // 1. 处理 stsd：将 encv -> hvc1 或 enca -> mp4a，将 sinf 改为 free
        let entryCount = data.readUInt32(at: stsdOff + 4)
        if entryCount > 0 {
            let entryOff = stsdOff + 8
            let entrySize = Int(data.readUInt32(at: entryOff))
            guard entrySize >= 8, entrySize <= stsdBox.offset + stsdBox.size - entryOff else { throw invalidMedia() }
            let entryType = String(data: data.subdata(in: entryOff+4..<entryOff+8), encoding: .ascii) ?? ""

            if entryType == "encv" || entryType == "enca" {
                let subStart = entryOff + (entryType == "encv" ? 86 : 36)
                var p = subStart
                while p + 8 <= entryOff + entrySize {
                    let subSize = Int(data.readUInt32(at: p))
                    let subType = String(data: data.subdata(in: p+4..<p+8), encoding: .ascii) ?? ""
                    if subSize < 8 || p + subSize > entryOff + entrySize { break }
                    if subType == "sinf" {
                        let sinf = Box(type: "sinf", offset: p, size: subSize, headerSize: 8)
                        if let schi = findChildBox(data: data, parent: sinf, target: "schi"),
                           let tenc = findChildBox(data: data, parent: schi, target: "tenc") {
                            let offset = tenc.offset + tenc.headerSize
                            guard offset + 24 <= tenc.offset + tenc.size else { throw invalidMedia() }
                            ivSize = Int(data[offset + 7])
                        }
                        if let schm = findChildBox(data: data, parent: sinf, target: "schm") {
                            let offset = schm.offset + schm.headerSize
                            guard offset + 8 <= schm.offset + schm.size,
                                  String(data: data.subdata(in: offset+4..<offset+8), encoding: .ascii) == "cenc" else { throw invalidMedia() }
                        }
                        var sp = p + 8
                        while sp + 8 <= p + subSize {
                            let ssize = Int(data.readUInt32(at: sp))
                            let stype = String(data: data.subdata(in: sp+4..<sp+8), encoding: .ascii) ?? ""
                            if ssize < 8 || sp + ssize > p + subSize { break }
                            if stype == "frma" {
                                guard ssize >= 12 else { throw invalidMedia() }
                                originalFormatFound = true
                                let origFourCCData = data.subdata(in: sp+8..<sp+12)
                                data.replaceSubrange(entryOff+4..<entryOff+8, with: origFourCCData)
                                break
                            }
                            sp += ssize
                        }
                        if let freeBytes = "free".data(using: .ascii) {
                            data.replaceSubrange(p+4..<p+8, with: freeBytes)
                        }
                        break
                    }
                    p += subSize
                }
            }
        }

        // 2. 解析 stsz (Sample Sizes)
        let stszOff = stszBox.offset + stszBox.headerSize
        guard originalFormatFound, [8, 16].contains(ivSize), stszOff + 12 <= stszBox.offset + stszBox.size else { throw invalidMedia() }
        let uniformSize = Int(data.readUInt32(at: stszOff + 4))
        let sampleCount = Int(data.readUInt32(at: stszOff + 8))
        guard sampleCount > 0, sampleCount <= 2_000_000,
              uniformSize != 0 || sampleCount <= (stszBox.offset + stszBox.size - stszOff - 12) / 4 else { throw invalidMedia() }
        var sampleSizes = [Int]()
        sampleSizes.reserveCapacity(sampleCount)
        if uniformSize != 0 {
            sampleSizes = Array(repeating: uniformSize, count: sampleCount)
        } else {
            var ptr = stszOff + 12
            for _ in 0..<sampleCount {
                sampleSizes.append(Int(data.readUInt32(at: ptr)))
                ptr += 4
            }
        }

        // 3. 解析 stco 或 co64 (Chunk Offsets)
        var chunkOffsets = [Int]()
        if let stco = stcoBox {
            let stcoOff = stco.offset + stco.headerSize
            guard stcoOff + 8 <= stco.offset + stco.size else { throw invalidMedia() }
            let entryCnt = Int(data.readUInt32(at: stcoOff + 4))
            guard entryCnt <= (stco.offset + stco.size - stcoOff - 8) / 4 else { throw invalidMedia() }
            chunkOffsets.reserveCapacity(entryCnt)
            var ptr = stcoOff + 8
            for _ in 0..<entryCnt {
                chunkOffsets.append(Int(data.readUInt32(at: ptr)))
                ptr += 4
            }
        } else if let co64 = co64Box {
            let co64Off = co64.offset + co64.headerSize
            guard co64Off + 8 <= co64.offset + co64.size else { throw invalidMedia() }
            let entryCnt = Int(data.readUInt32(at: co64Off + 4))
            guard entryCnt <= (co64.offset + co64.size - co64Off - 8) / 8 else { throw invalidMedia() }
            chunkOffsets.reserveCapacity(entryCnt)
            var ptr = co64Off + 8
            for _ in 0..<entryCnt {
                let offset = data.readUInt64(at: ptr)
                guard offset <= UInt64(data.count) else { throw invalidMedia() }
                chunkOffsets.append(Int(offset))
                ptr += 8
            }
        }

        // 4. 解析 stsc (Sample to Chunk)
        let stscOff = stscBox.offset + stscBox.headerSize
        guard stscOff + 8 <= stscBox.offset + stscBox.size else { throw invalidMedia() }
        let stscCnt = Int(data.readUInt32(at: stscOff + 4))
        guard stscCnt > 0, stscCnt <= (stscBox.offset + stscBox.size - stscOff - 8) / 12 else { throw invalidMedia() }
        var stscEntries = [STSCEntry]()
        stscEntries.reserveCapacity(stscCnt)
        var stscPtr = stscOff + 8
        for _ in 0..<stscCnt {
            let firstChunk = data.readUInt32(at: stscPtr)
            let spc = data.readUInt32(at: stscPtr + 4)
            let desc = data.readUInt32(at: stscPtr + 8)
            stscEntries.append(STSCEntry(firstChunk: firstChunk, samplesPerChunk: spc, sampleDescIndex: desc))
            stscPtr += 12
        }

        // 5. 计算 Sample 绝对偏移量
        var sampleOffsets = [Int]()
        sampleOffsets.reserveCapacity(sampleCount)
        var stscIdx = 0
        var currSampleIdx = 0
        for chunkIdx in 0..<chunkOffsets.count {
            let chunkNum = UInt32(chunkIdx + 1)
            while stscIdx + 1 < stscEntries.count && chunkNum >= stscEntries[stscIdx + 1].firstChunk {
                stscIdx += 1
            }
            let spc = Int(stscEntries[stscIdx].samplesPerChunk)
            var offset = chunkOffsets[chunkIdx]
            for _ in 0..<spc {
                guard currSampleIdx < sampleCount else { break }
                guard offset >= 0, offset <= data.count, sampleSizes[currSampleIdx] <= data.count - offset else { throw invalidMedia() }
                sampleOffsets.append(offset)
                offset += sampleSizes[currSampleIdx]
                currSampleIdx += 1
            }
        }

        // 6. 解析 senc 并通过 CommonCrypto AES-128-CTR 解密 sample 样本
        let sencOff = sencBox.offset + sencBox.headerSize
        guard sencOff + 8 <= sencBox.offset + sencBox.size else { throw invalidMedia() }
        let flags = (UInt32(data[sencOff+1]) << 16) | (UInt32(data[sencOff+2]) << 8) | UInt32(data[sencOff+3])
        guard sampleOffsets.count == sampleCount, sencOff + 8 <= sencBox.offset + sencBox.size else { throw invalidMedia() }
        var sencPos = sencOff + 4
        if flags & 0x01 != 0 {
            guard sencPos + 20 <= sencBox.offset + sencBox.size else { throw invalidMedia() }
            ivSize = Int(data[sencPos + 3])
            guard [8, 16].contains(ivSize) else { throw invalidMedia() }
            sencPos += 20
        }
        guard sencPos + 4 <= sencBox.offset + sencBox.size else { throw invalidMedia() }
        let sencSampleCnt = Int(data.readUInt32(at: sencPos))
        guard sencSampleCnt == sampleCount else { throw invalidMedia() }
        sencPos += 4

        struct SampleCryptoInfo {
            var iv: [UInt8]
            var subsamples: [(clear: Int, cipher: Int)]
        }

        var cryptoInfos = [SampleCryptoInfo]()
        cryptoInfos.reserveCapacity(min(sencSampleCnt, sampleCount))

        for index in 0..<sampleCount {
            guard sencPos + ivSize <= sencBox.offset + sencBox.size else { throw invalidMedia() }
            var iv = [UInt8](repeating: 0, count: 16)
            for b in 0..<ivSize {
                iv[b] = data[sencPos + b]
            }
            sencPos += ivSize

            var subs = [(clear: Int, cipher: Int)]()
            if (flags & 0x02) != 0 {
                guard sencPos + 2 <= sencBox.offset + sencBox.size else { throw invalidMedia() }
                let subsampleCount = Int(data.readUInt16(at: sencPos))
                sencPos += 2
                guard subsampleCount <= (sencBox.offset + sencBox.size - sencPos) / 6 else { throw invalidMedia() }
                var total = 0
                for _ in 0..<subsampleCount {
                    let clearBytes = Int(data.readUInt16(at: sencPos))
                    let cipherBytes = Int(data.readUInt32(at: sencPos + 2))
                    sencPos += 6
                    guard clearBytes <= sampleSizes[index] - total,
                          cipherBytes <= sampleSizes[index] - total - clearBytes else { throw invalidMedia() }
                    total += clearBytes + cipherBytes
                    subs.append((clear: clearBytes, cipher: cipherBytes))
                }
            }
            cryptoInfos.append(SampleCryptoInfo(iv: iv, subsamples: subs))
        }

        try data.withUnsafeMutableBytes { rawBuf in
            guard let basePtr = rawBuf.baseAddress else { return }
            for i in 0..<cryptoInfos.count {
                if i % 256 == 0 { try Task.checkCancellation() }
                let info = cryptoInfos[i]
                var cryptor: CCCryptorRef?
                let status = CCCryptorCreateWithMode(
                    CCOperation(kCCDecrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    info.iv,
                    keyBytes,
                    keyBytes.count,
                    nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
                guard status == kCCSuccess, let cryptor else { throw invalidMedia() }
                defer { CCCryptorRelease(cryptor) }

                if !info.subsamples.isEmpty {
                    var sOff = sampleOffsets[i]
                    for sub in info.subsamples {
                        sOff += sub.clear
                        if sub.cipher > 0 {
                            let targetPtr = basePtr.advanced(by: sOff)
                            var moved: size_t = 0
                            guard CCCryptorUpdate(cryptor, targetPtr, sub.cipher, targetPtr, sub.cipher, &moved) == kCCSuccess, moved == sub.cipher else { throw invalidMedia() }
                            sOff += sub.cipher
                        }
                    }
                } else {
                    let sOff = sampleOffsets[i]
                    let sLen = sampleSizes[i]
                    let targetPtr = basePtr.advanced(by: sOff)
                    var moved: size_t = 0
                    guard CCCryptorUpdate(cryptor, targetPtr, sLen, targetPtr, sLen, &moved) == kCCSuccess, moved == sLen else { throw invalidMedia() }
                }
            }
        }

        if let freeBytes = "free".data(using: .ascii) {
            data.replaceSubrange(sencBox.offset+4..<sencBox.offset+8, with: freeBytes)
        }

        return true
    }

    private func invalidMedia() -> NSError {
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

// MARK: - 安全大端序二进制解析扩展（完全杜绝 misaligned pointer 异常）
private extension Data {
    @inline(__always)
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset <= count - 4 else { return 0 }
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    @inline(__always)
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset <= count - 2 else { return 0 }
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1])
        return (b0 << 8) | b1
    }

    @inline(__always)
    func readUInt64(at offset: Int) -> UInt64 {
        guard offset >= 0, offset <= count - 8 else { return 0 }
        let high = UInt64(readUInt32(at: offset))
        let low = UInt64(readUInt32(at: offset + 4))
        return (high << 32) | low
    }
}
