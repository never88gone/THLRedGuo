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

    func parseBoxes(data: Data, start: Int, end: Int) -> [Box] {
        var boxes = [Box]()
        var curr = start
        while curr + 8 <= end {
            let size = Int(readUInt32(from: data, at: curr))
            let typeData = data.subdata(in: curr + 4..<curr + 8)
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

    func performInPlaceDecryption(data: inout Data, keyBytes: [UInt8]) throws -> Bool {
        let rootBoxes = parseBoxes(data: data, start: 0, end: data.count)
        guard let moov = rootBoxes.first(where: { $0.type == "moov" }) else {
            throw CENCMP4BoxParser.invalidMediaError
        }
        let moovData = data.subdata(in: moov.offset..<moov.offset + moov.size)
        let streamIndex = try CENCStreamIndex(
            data: moovData,
            offset: Int64(moov.offset),
            fileSize: Int64(data.count)
        )
        let chunkSize = 1024 * 1024
        var cursor = 0
        while cursor < data.count {
            let end = min(data.count, cursor + chunkSize)
            let chunk = data.subdata(in: cursor..<end)
            let decrypted = try streamIndex.decrypt(chunk, offset: Int64(cursor), key: keyBytes)
            data.replaceSubrange(cursor..<end, with: decrypted)
            cursor = end
        }
        return true
    }

    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset <= data.count - 4 else { return 0 }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    private func readUInt64(from data: Data, at offset: Int) -> UInt64 {
        guard offset >= 0, offset <= data.count - 8 else { return 0 }
        let high = UInt64(readUInt32(from: data, at: offset))
        let low = UInt64(readUInt32(from: data, at: offset + 4))
        return (high << 32) | low
    }
}
