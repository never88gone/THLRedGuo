import Foundation
import CommonCrypto

// MARK: - 二进制 MP4 ISO BMFF 解析与解密核心引擎

final class CENCMP4BoxParser {
    static let shared = CENCMP4BoxParser()

    static let invalidMediaError = NSError(domain: "CENCMP4Decryptor", code: -3, userInfo: [NSLocalizedDescriptionKey: "加密媒体文件数据损坏或不完整"])

    struct Box {
        let type: String
        let offset: Int
        let size: Int
        let headerSize: Int
    }

    struct STSCEntry {
        let firstChunk: UInt32
        let samplesPerChunk: UInt32
        let sampleDescIndex: UInt32
    }

    func parseBoxes(data: Data, start: Int, end: Int) -> [Box] {
        var boxes = [Box]()
        var curr = start
        while curr + 8 <= end {
            let size = Int(readUInt32(from: data, at: curr))
            let typeData = data.subdata(in: curr+4..<curr+8)
            let typeStr = String(data: typeData, encoding: .ascii) ?? "????"
            var actualSize = size
            var headerSize = 8
            if size == 1 {
                if curr + 16 > end { break }
                let length = readUInt64(from: data, at: curr + 8)
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

    func findChildBox(data: Data, parent: Box, target: String) -> Box? {
        let children = parseBoxes(data: data, start: parent.offset + parent.headerSize, end: parent.offset + parent.size)
        return children.first { $0.type == target }
    }

    func performInPlaceDecryption(data: inout Data, keyBytes: [UInt8]) throws -> Bool {
        let rootBoxes = parseBoxes(data: data, start: 0, end: data.count)
        guard let moov = rootBoxes.first(where: { $0.type == "moov" }) else {
            throw CENCMP4BoxParser.invalidMediaError
        }

        let trakBoxes = parseBoxes(data: data, start: moov.offset + moov.headerSize, end: moov.offset + moov.size).filter { $0.type == "trak" }

        var anyDecrypted = false

        for trak in trakBoxes {
            guard let mdia = findChildBox(data: data, parent: trak, target: "mdia"),
                  let minf = findChildBox(data: data, parent: mdia, target: "minf"),
                  let stbl = findChildBox(data: data, parent: minf, target: "stbl") else {
                continue
            }

            guard let stsd = findChildBox(data: data, parent: stbl, target: "stsd") else { continue }
            let stsdContentOffset = stsd.offset + stsd.headerSize + 8

            var isCencTrack = false
            let sampleEntries = parseBoxes(data: data, start: stsdContentOffset, end: stsd.offset + stsd.size)
            for entry in sampleEntries {
                if entry.type == "encv" || entry.type == "enca" {
                    isCencTrack = true
                    if let sinf = findChildBox(data: data, parent: entry, target: "sinf"),
                       let frma = findChildBox(data: data, parent: sinf, target: "frma") {
                        let originalFormat = data.subdata(in: frma.offset + frma.headerSize..<frma.offset + frma.headerSize + 4)
                        let targetOffset = entry.offset + 4
                        data.replaceSubrange(targetOffset..<targetOffset + 4, with: originalFormat)
                    }
                }
            }

            guard isCencTrack else { continue }

            var defaultIvSize = 16
            if let tenc = findTencBox(data: data, stbl: stbl) {
                let ivSizeByte = data[tenc.offset + tenc.headerSize + 7]
                defaultIvSize = Int(ivSizeByte)
            }

            var chunkOffsets = [UInt64]()
            if let stco = findChildBox(data: data, parent: stbl, target: "stco") {
                let count = Int(readUInt32(from: data, at: stco.offset + stco.headerSize + 4))
                var ptr = stco.offset + stco.headerSize + 8
                for _ in 0..<count {
                    chunkOffsets.append(UInt64(readUInt32(from: data, at: ptr)))
                    ptr += 4
                }
            } else if let co64 = findChildBox(data: data, parent: stbl, target: "co64") {
                let count = Int(readUInt32(from: data, at: co64.offset + co64.headerSize + 4))
                var ptr = co64.offset + co64.headerSize + 8
                for _ in 0..<count {
                    chunkOffsets.append(readUInt64(from: data, at: ptr))
                    ptr += 8
                }
            }

            var sampleSizes = [Int]()
            if let stsz = findChildBox(data: data, parent: stbl, target: "stsz") {
                let defaultSize = Int(readUInt32(from: data, at: stsz.offset + stsz.headerSize + 4))
                let sampleCount = Int(readUInt32(from: data, at: stsz.offset + stsz.headerSize + 8))
                if defaultSize > 0 {
                    sampleSizes = Array(repeating: defaultSize, count: sampleCount)
                } else {
                    var ptr = stsz.offset + stsz.headerSize + 12
                    for _ in 0..<sampleCount {
                        sampleSizes.append(Int(readUInt32(from: data, at: ptr)))
                        ptr += 4
                    }
                }
            }

            var stscEntries = [STSCEntry]()
            if let stsc = findChildBox(data: data, parent: stbl, target: "stsc") {
                let entryCount = Int(readUInt32(from: data, at: stsc.offset + stsc.headerSize + 4))
                var ptr = stsc.offset + stsc.headerSize + 8
                for _ in 0..<entryCount {
                    stscEntries.append(STSCEntry(
                        firstChunk: readUInt32(from: data, at: ptr),
                        samplesPerChunk: readUInt32(from: data, at: ptr + 4),
                        sampleDescIndex: readUInt32(from: data, at: ptr + 8)
                    ))
                    ptr += 12
                }
            }

            var sampleOffsets = [Int]()
            var currentSampleIdx = 0
            for chunkIdx in 0..<chunkOffsets.count {
                let chunkNum = UInt32(chunkIdx + 1)
                var spc = 1
                for i in (0..<stscEntries.count).reversed() {
                    if chunkNum >= stscEntries[i].firstChunk {
                        spc = Int(stscEntries[i].samplesPerChunk)
                        break
                    }
                }
                var currentChunkOffset = Int(chunkOffsets[chunkIdx])
                for _ in 0..<spc {
                    if currentSampleIdx >= sampleSizes.count { break }
                    guard currentChunkOffset >= 0, currentChunkOffset <= data.count,
                          sampleSizes[currentSampleIdx] <= data.count - currentChunkOffset else {
                        throw CENCMP4BoxParser.invalidMediaError
                    }
                    sampleOffsets.append(currentChunkOffset)
                    currentChunkOffset += sampleSizes[currentSampleIdx]
                    currentSampleIdx += 1
                }
            }

            var sencBox: Box? = findChildBox(data: data, parent: stbl, target: "senc")
            if sencBox == nil {
                sencBox = rootBoxes.first(where: { $0.type == "senc" })
            }

            guard let senc = sencBox else {
                continue
            }

            let flags = Int(readUInt32(from: data, at: senc.offset + senc.headerSize)) & 0xFFFFFF
            let hasSubsampleEncryption = (flags & 0x02) != 0

            let sencSampleCount = Int(readUInt32(from: data, at: senc.offset + senc.headerSize + 4))
            var sencPtr = senc.offset + senc.headerSize + 8

            let totalToDecrypt = min(sampleOffsets.count, min(sampleSizes.count, sencSampleCount))

            for i in 0..<totalToDecrypt {
                let sampleOffset = sampleOffsets[i]
                let sampleSize = sampleSizes[i]

                if sencPtr + defaultIvSize > senc.offset + senc.size { break }
                let ivBytes = Array(data[sencPtr..<sencPtr + defaultIvSize])
                sencPtr += defaultIvSize

                var subSamples = [(clear: Int, enc: Int)]()
                if hasSubsampleEncryption {
                    if sencPtr + 2 > senc.offset + senc.size { break }
                    let subCount = Int(readUInt16(from: data, at: sencPtr))
                    sencPtr += 2
                    for _ in 0..<subCount {
                        if sencPtr + 6 > senc.offset + senc.size { break }
                        let clear = Int(readUInt16(from: data, at: sencPtr))
                        let enc = Int(readUInt32(from: data, at: sencPtr + 2))
                        sencPtr += 6
                        subSamples.append((clear: clear, enc: enc))
                    }
                }

                if subSamples.isEmpty {
                    subSamples.append((clear: 0, enc: sampleSize))
                }

                try decryptSample(
                    data: &data,
                    sampleOffset: sampleOffset,
                    sampleSize: sampleSize,
                    subSamples: subSamples,
                    keyBytes: keyBytes,
                    ivBytes: ivBytes
                )
            }

            anyDecrypted = true
        }

        return anyDecrypted
    }

    private func findTencBox(data: Data, stbl: Box) -> Box? {
        let children = parseBoxes(data: data, start: stbl.offset + stbl.headerSize, end: stbl.offset + stbl.size)
        for child in children {
            if child.type == "stsd" {
                let stsdEntries = parseBoxes(data: data, start: child.offset + child.headerSize + 8, end: child.offset + child.size)
                for entry in stsdEntries {
                    if let sinf = findChildBox(data: data, parent: entry, target: "sinf"),
                       let schi = findChildBox(data: data, parent: sinf, target: "schi"),
                       let tenc = findChildBox(data: data, parent: schi, target: "tenc") {
                        return tenc
                    }
                }
            }
        }
        return nil
    }

    private func decryptSample(
        data: inout Data,
        sampleOffset: Int,
        sampleSize: Int,
        subSamples: [(clear: Int, enc: Int)],
        keyBytes: [UInt8],
        ivBytes: [UInt8]
    ) throws {
        var fullIv = [UInt8](repeating: 0, count: 16)
        for i in 0..<min(16, ivBytes.count) {
            fullIv[i] = ivBytes[i]
        }

        var cryptor: CCCryptorRef?
        let createStatus = CCCryptorCreateWithMode(
            CCOperation(kCCDecrypt),
            CCMode(kCCModeCTR),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            fullIv,
            keyBytes,
            keyBytes.count,
            nil,
            0,
            0,
            CCModeOptions(kCCModeOptionCTR_BE),
            &cryptor
        )

        guard createStatus == kCCSuccess, let cryptorRef = cryptor else {
            throw NSError(domain: "CENCMP4Decryptor", code: -3, userInfo: [NSLocalizedDescriptionKey: "AES-CTR 密码句柄初始化失败"])
        }
        defer { CCCryptorRelease(cryptorRef) }

        var currentOffset = sampleOffset
        for sub in subSamples {
            currentOffset += sub.clear
            let encLen = sub.enc
            guard currentOffset + encLen <= data.count else {
                throw CENCMP4BoxParser.invalidMediaError
            }
            if encLen > 0 {
                data.withUnsafeMutableBytes { (rawPtr: UnsafeMutableRawBufferPointer) in
                    let base = rawPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let targetPtr = base.advanced(by: currentOffset)
                    var dataOutMoved = 0
                    CCCryptorUpdate(cryptorRef, targetPtr, encLen, targetPtr, encLen, &dataOutMoved)
                }
                currentOffset += encLen
            }
        }
    }

    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset <= data.count - 4 else { return 0 }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset <= data.count - 2 else { return 0 }
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return (b0 << 8) | b1
    }

    private func readUInt64(from data: Data, at offset: Int) -> UInt64 {
        guard offset >= 0, offset <= data.count - 8 else { return 0 }
        let high = UInt64(readUInt32(from: data, at: offset))
        let low = UInt64(readUInt32(from: data, at: offset + 4))
        return (high << 32) | low
    }
}
