import Foundation
import CryptoKit
import CommonCrypto
import Security
import zlib

struct HongguoApkProfile: Codable, Sendable {
    let appVersion: String
    let sdkVersion: String
    let configuration: String
    let importedAt: Date
}

enum HongguoApkError: Error, LocalizedError {
    case invalidArchive
    case invalidSignature
    case unsupportedPackage
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "APK 文件不完整或格式不受支持，请重新选择官方安装包"
        case .invalidSignature: return "无法验证红果官方安装包签名，请使用未修改的官方 APK"
        case .unsupportedPackage: return "当前仅支持含兼容播放配置的红果官方 APK"
        case .missingConfiguration: return "未找到兼容的播放配置，请使用其他官方 APK 版本"
        }
    }
}

struct ApkBytes {
    let data: Data

    func range(_ offset: Int, _ count: Int) throws -> Range<Int> {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
            throw HongguoApkError.invalidArchive
        }
        return offset..<(offset + count)
    }

    func u16(_ offset: Int) throws -> Int {
        let r = try range(offset, 2)
        return Int(data[r.lowerBound]) | Int(data[r.lowerBound + 1]) << 8
    }

    func u32(_ offset: Int) throws -> Int {
        let r = try range(offset, 4)
        return (0..<4).reduce(0) { $0 | Int(data[r.lowerBound + $1]) << ($1 * 8) }
    }

    func u64(_ offset: Int) throws -> Int {
        let r = try range(offset, 8)
        let value = (0..<8).reduce(UInt64(0)) { $0 | UInt64(data[r.lowerBound + $1]) << ($1 * 8) }
        guard value <= UInt64(Int.max) else { throw HongguoApkError.invalidArchive }
        return Int(value)
    }

    func bytes(_ offset: Int, _ count: Int) throws -> Data {
        data.subdata(in: try range(offset, count))
    }

    func prefixed(_ offset: inout Int, end: Int) throws -> Data {
        let count = try u32(offset)
        offset += 4
        guard offset <= end, count <= end - offset else { throw HongguoApkError.invalidArchive }
        let value = try bytes(offset, count)
        offset += count
        return value
    }

    func varint(_ offset: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<10 {
            guard offset < data.count else { throw HongguoApkError.invalidArchive }
            let byte = data[offset]
            offset += 1
            if index == 9, byte > 1 { throw HongguoApkError.invalidArchive }
            value |= UInt64(byte & 127) << (index * 7)
            if byte < 128 { return value }
        }
        throw HongguoApkError.invalidArchive
    }
}

struct HongguoApkImporter {
    private struct Entry {
        let name: String
        let method: Int
        let flags: Int
        let crc: Int
        let compressed: Int
        let expanded: Int
        let offset: Int
    }

    private let bytes: ApkBytes
    private let directory: Int
    private let endRecord: Int
    private let signingStart: Int
    private let entries: [Entry]

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        guard (22...314_572_800).contains(data.count) else { throw HongguoApkError.invalidArchive }
        let reader = ApkBytes(data: data)
        var found: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try reader.u32(offset) == 0x06054b50, try offset + 22 + reader.u16(offset + 20) == data.count {
                found = offset
                break
            }
        }
        guard let end = found, try reader.u16(end + 4) == 0, try reader.u16(end + 6) == 0,
              try reader.u16(end + 8) == reader.u16(end + 10) else { throw HongguoApkError.invalidArchive }
        let directory = try reader.u32(end + 16)
        guard try directory + reader.u32(end + 12) == end, directory >= 32,
              try reader.bytes(directory - 16, 16) == Data("APK Sig Block 42".utf8) else {
            throw HongguoApkError.invalidSignature
        }
        let signingSize = try reader.u64(directory - 24)
        guard signingSize >= 24, signingSize <= directory - 8 else { throw HongguoApkError.invalidSignature }
        let signingStart = directory - signingSize - 8
        guard try reader.u64(signingStart) == signingSize else { throw HongguoApkError.invalidSignature }
        var entries = [Entry]()
        var names = Set<String>()
        var cursor = directory
        for _ in 0..<(try reader.u16(end + 10)) {
            guard try reader.u32(cursor) == 0x02014b50 else { throw HongguoApkError.invalidArchive }
            let nameLength = try reader.u16(cursor + 28)
            let total = try 46 + nameLength + reader.u16(cursor + 30) + reader.u16(cursor + 32)
            guard total <= end - cursor, let name = String(data: try reader.bytes(cursor + 46, nameLength), encoding: .utf8), names.insert(name).inserted else {
                throw HongguoApkError.invalidArchive
            }
            entries.append(Entry(name: name, method: try reader.u16(cursor + 10), flags: try reader.u16(cursor + 8), crc: try reader.u32(cursor + 16), compressed: try reader.u32(cursor + 20), expanded: try reader.u32(cursor + 24), offset: try reader.u32(cursor + 42)))
            cursor += total
        }
        guard cursor == end else { throw HongguoApkError.invalidArchive }
        self.bytes = reader
        self.directory = directory
        self.endRecord = end
        self.signingStart = signingStart
        self.entries = entries
    }

    func extract() throws -> HongguoApkProfile {
        try verifySignature()
        guard let manifestEntry = entries.first(where: { $0.name == "AndroidManifest.xml" }) else { throw HongguoApkError.unsupportedPackage }
        let manifest = try manifestAttributes(unpack(manifestEntry, maximum: 4_194_304))
        guard manifest["package"] == "com.phoenix.read", let version = manifest["versionName"], !version.isEmpty else {
            throw HongguoApkError.unsupportedPackage
        }
        guard let sdkEntry = entries.first(where: { $0.name == "lib/arm64-v8a/libmetasec_ml.so" }) else { throw HongguoApkError.unsupportedPackage }
        let sdkHash = SHA256.hash(data: try unpack(sdkEntry, maximum: 16_777_216)).map { String(format: "%02x", $0) }.joined()
        guard sdkHash == "c6831ab265a0cb76dacfa3b7041e9ea0f706490106a74e12f39058671cc14fe3" else { throw HongguoApkError.unsupportedPackage }
        let dexEntries = entries.filter { $0.name.range(of: "^classes([0-9]+)?\\.dex$", options: .regularExpression) != nil }
        guard !dexEntries.isEmpty, dexEntries.count <= 64 else { throw HongguoApkError.unsupportedPackage }
        var configurations = Set<String>()
        for entry in dexEntries {
            try visitDex(unpack(entry, maximum: 67_108_864)) { string in
                if Self.compatibleConfiguration(string) { configurations.insert(string) }
            }
        }
        guard configurations.count == 1, let configuration = configurations.first else {
            throw HongguoApkError.missingConfiguration
        }
        return HongguoApkProfile(appVersion: version, sdkVersion: "v04.10.03-ml-android", configuration: configuration, importedAt: Date())
    }

    private func verifySignature() throws {
        var offset = signingStart + 8
        let limit = directory - 24
        var block: Data?
        while offset < limit {
            let length = try bytes.u64(offset)
            offset += 8
            guard length >= 4, offset <= limit, length <= limit - offset else { throw HongguoApkError.invalidSignature }
            if try bytes.u32(offset) == 0x7109871a {
                guard block == nil else { throw HongguoApkError.invalidSignature }
                block = try bytes.bytes(offset + 4, length - 4)
            }
            offset += length
        }
        guard offset == limit, let block else { throw HongguoApkError.invalidSignature }
        let outer = ApkBytes(data: block)
        var cursor = 0
        let signers = ApkBytes(data: try outer.prefixed(&cursor, end: block.count))
        guard cursor == block.count else { throw HongguoApkError.invalidSignature }
        cursor = 0
        let signer = ApkBytes(data: try signers.prefixed(&cursor, end: signers.data.count))
        guard cursor == signers.data.count else { throw HongguoApkError.invalidSignature }
        cursor = 0
        let signed = try signer.prefixed(&cursor, end: signer.data.count)
        let signatures = try signer.prefixed(&cursor, end: signer.data.count)
        let publicKey = try signer.prefixed(&cursor, end: signer.data.count)
        guard cursor == signer.data.count else { throw HongguoApkError.invalidSignature }
        let signedReader = ApkBytes(data: signed)
        cursor = 0
        let digests = try signedReader.prefixed(&cursor, end: signed.count)
        let certificates = ApkBytes(data: try signedReader.prefixed(&cursor, end: signed.count))
        _ = try signedReader.prefixed(&cursor, end: signed.count)
        let trailingPadding = try signed.count - cursor == 4 && signedReader.u32(cursor) == 0
        guard cursor == signed.count || trailingPadding else { throw HongguoApkError.invalidSignature }
        cursor = 0
        let certificateData = try certificates.prefixed(&cursor, end: certificates.data.count)
        let fingerprint = SHA256.hash(data: certificateData).map { String(format: "%02x", $0) }.joined()
        guard fingerprint == "1fe01f1425c72dc1cd158e05cb696cb9fc17259a70f9d233fc48e8e42e6510ec",
              let certificate = SecCertificateCreateWithData(nil, certificateData as CFData),
              let key = SecCertificateCopyKey(certificate), try Self.certificatePublicKey(certificateData) == publicKey else {
            throw HongguoApkError.invalidSignature
        }
        let signatureRows = try Self.records(signatures)
        let digestRows = try Self.records(digests)
        guard signatureRows.map(\.0) == digestRows.map(\.0),
              let signature = signatureRows.first(where: { $0.0 == 0x0103 }),
              let expected = digestRows.first(where: { $0.0 == 0x0103 }),
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, signature.1 as CFData, nil),
              try contentDigest() == expected.1 else { throw HongguoApkError.invalidSignature }
    }

    private static func records(_ data: Data) throws -> [(Int, Data)] {
        let reader = ApkBytes(data: data)
        var cursor = 0
        var rows = [(Int, Data)]()
        while cursor < data.count {
            let value = ApkBytes(data: try reader.prefixed(&cursor, end: data.count))
            let algorithm = try value.u32(0)
            var at = 4
            let record = try value.prefixed(&at, end: value.data.count)
            guard at == value.data.count, !rows.contains(where: { $0.0 == algorithm }) else { throw HongguoApkError.invalidSignature }
            rows.append((algorithm, record))
        }
        return rows
    }

    private func contentDigest() throws -> Data {
        var end = try bytes.bytes(endRecord, bytes.data.count - endRecord)
        for index in 0..<4 { end[16 + index] = UInt8(truncatingIfNeeded: signingStart >> (index * 8)) }
        let sections = [bytes.data[0..<signingStart], bytes.data[directory..<endRecord], end[0..<end.count]]
        let count = sections.reduce(0) { $0 + ($1.count + 1_048_575) / 1_048_576 }
        var final = SHA256()
        var prefix = Data([0x5a])
        for index in 0..<4 { prefix.append(UInt8(truncatingIfNeeded: count >> (index * 8))) }
        final.update(data: prefix)
        for section in sections {
            var cursor = section.startIndex
            while cursor < section.endIndex {
                let length = min(1_048_576, section.endIndex - cursor)
                var chunk = SHA256()
                var header = Data([0xa5])
                for index in 0..<4 { header.append(UInt8(truncatingIfNeeded: length >> (index * 8))) }
                chunk.update(data: header)
                chunk.update(data: section[cursor..<(cursor + length)])
                final.update(data: Data(chunk.finalize()))
                cursor += length
            }
        }
        return Data(final.finalize())
    }

    private static func certificatePublicKey(_ data: Data) throws -> Data {
        func item(_ data: Data, _ cursor: inout Int) throws -> (UInt8, Data, Data) {
            let start = cursor
            guard cursor + 2 <= data.count else { throw HongguoApkError.invalidSignature }
            let tag = data[cursor]
            cursor += 1
            var length = Int(data[cursor])
            cursor += 1
            if length & 128 != 0 {
                let count = length & 127
                guard (1...4).contains(count), count <= data.count - cursor else { throw HongguoApkError.invalidSignature }
                length = 0
                for _ in 0..<count { length = length << 8 | Int(data[cursor]); cursor += 1 }
            }
            guard length <= data.count - cursor else { throw HongguoApkError.invalidSignature }
            let value = data.subdata(in: cursor..<(cursor + length))
            cursor += length
            return (tag, value, data.subdata(in: start..<cursor))
        }
        var cursor = 0
        let root = try item(data, &cursor)
        guard root.0 == 0x30, cursor == data.count else { throw HongguoApkError.invalidSignature }
        cursor = 0
        let tbs = try item(root.1, &cursor)
        guard tbs.0 == 0x30 else { throw HongguoApkError.invalidSignature }
        cursor = 0
        let first = try item(tbs.1, &cursor)
        if first.0 == 0xa0 { _ = try item(tbs.1, &cursor) }
        for _ in 0..<4 { _ = try item(tbs.1, &cursor) }
        let key = try item(tbs.1, &cursor)
        guard key.0 == 0x30 else { throw HongguoApkError.invalidSignature }
        return key.2
    }

    private func unpack(_ entry: Entry, maximum: Int) throws -> Data {
        guard entry.flags & 1 == 0, entry.expanded > 0, entry.expanded <= maximum,
              try bytes.u32(entry.offset) == 0x04034b50,
              try bytes.u16(entry.offset + 8) == entry.method else { throw HongguoApkError.invalidArchive }
        let nameLength = try bytes.u16(entry.offset + 26)
        let start = try entry.offset + 30 + nameLength + bytes.u16(entry.offset + 28)
        guard try bytes.bytes(entry.offset + 30, nameLength) == Data(entry.name.utf8), start <= signingStart,
              entry.compressed <= signingStart - start else { throw HongguoApkError.invalidArchive }
        let compressed = try bytes.bytes(start, entry.compressed)
        let output: Data
        if entry.method == 0 {
            guard entry.compressed == entry.expanded else { throw HongguoApkError.invalidArchive }
            output = compressed
        } else if entry.method == 8 {
            var result = Data(count: entry.expanded)
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw HongguoApkError.invalidArchive }
            defer { inflateEnd(&stream) }
            let status = compressed.withUnsafeBytes { input in
                result.withUnsafeMutableBytes { target in
                    stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                    stream.avail_in = uInt(compressed.count)
                    stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(entry.expanded)
                    return inflate(&stream, Z_FINISH)
                }
            }
            guard status == Z_STREAM_END, stream.total_out == entry.expanded, stream.total_in == entry.compressed else { throw HongguoApkError.invalidArchive }
            output = result
        } else { throw HongguoApkError.invalidArchive }
        let checksum = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(output.count)) }
        guard Int(checksum) == entry.crc else { throw HongguoApkError.invalidArchive }
        return output
    }

    private func visitDex(_ data: Data, visit: (String) -> Void) throws {
        let reader = ApkBytes(data: data)
        guard data.count >= 112, data.prefix(4) == Data("dex\n".utf8), try reader.u32(32) == data.count,
              try reader.u32(36) == 112, try reader.u32(40) == 0x12345678 else { throw HongguoApkError.unsupportedPackage }
        let count = try reader.u32(56)
        let table = try reader.u32(60)
        guard count <= 2_000_000 else { throw HongguoApkError.invalidArchive }
        _ = try reader.range(table, count * 4)
        for index in 0..<count {
            var offset = try reader.u32(table + index * 4)
            let length = try reader.varint(&offset)
            guard length == 20 || (128...4096).contains(length) else { continue }
            let maximum = min(data.count, offset + Int(length) * 3 + 1)
            guard offset < maximum, let end = data[offset..<maximum].firstIndex(of: 0) else { throw HongguoApkError.invalidArchive }
            if let string = String(data: data[offset..<end], encoding: .utf8) { visit(string) }
        }
    }

    private func manifestAttributes(_ data: Data) throws -> [String: String] {
        let reader = ApkBytes(data: data)
        guard try reader.u16(0) == 3, try reader.u32(4) == data.count else { throw HongguoApkError.unsupportedPackage }
        var strings = [String]()
        var cursor = try reader.u16(2)
        while cursor < data.count {
            let type = try reader.u16(cursor)
            let header = try reader.u16(cursor + 2)
            let size = try reader.u32(cursor + 4)
            guard header >= 8, size >= header, size <= data.count - cursor else { throw HongguoApkError.invalidArchive }
            if type == 1 {
                let count = try reader.u32(cursor + 8)
                let flags = try reader.u32(cursor + 16)
                let start = try cursor + reader.u32(cursor + 20)
                guard count <= 100_000, header + count * 4 <= size else { throw HongguoApkError.invalidArchive }
                for index in 0..<count {
                    var at = try start + reader.u32(cursor + header + index * 4)
                    if flags & 0x100 != 0 {
                        func length() throws -> Int {
                            _ = try reader.range(at, 1)
                            let first = Int(data[at]); at += 1
                            if first & 128 == 0 { return first }
                            _ = try reader.range(at, 1)
                            let next = Int(data[at]); at += 1
                            return (first & 127) << 8 | next
                        }
                        _ = try length()
                        let bytes = try length()
                        guard let string = String(data: try reader.bytes(at, bytes), encoding: .utf8) else { throw HongguoApkError.invalidArchive }
                        strings.append(string)
                    } else {
                        var length = try reader.u16(at); at += 2
                        if length & 0x8000 != 0 { length = try (length & 0x7fff) << 16 | reader.u16(at); at += 2 }
                        guard let string = String(data: try reader.bytes(at, length * 2), encoding: .utf16LittleEndian) else { throw HongguoApkError.invalidArchive }
                        strings.append(string)
                    }
                }
            } else if type == 0x0102 {
                let name = try reader.u32(cursor + 20)
                guard strings.indices.contains(name) else { throw HongguoApkError.invalidArchive }
                if strings[name] == "manifest" {
                    let start = try cursor + 16 + reader.u16(cursor + 24)
                    let width = try reader.u16(cursor + 26)
                    let count = try reader.u16(cursor + 28)
                    guard width >= 20, start <= cursor + size, count * width <= cursor + size - start else { throw HongguoApkError.invalidArchive }
                    var attributes = [String: String]()
                    for index in 0..<count {
                        let at = start + index * width
                        let key = try reader.u32(at + 4)
                        let raw = try reader.u32(at + 8)
                        let typed = try reader.u32(at + 16)
                        guard strings.indices.contains(key) else { throw HongguoApkError.invalidArchive }
                        let value = raw == 0xffffffff ? typed : raw
                        if raw != 0xffffffff || data[at + 15] == 3, strings.indices.contains(value) { attributes[strings[key]] = strings[value] }
                    }
                    return attributes
                }
            }
            cursor += size
        }
        throw HongguoApkError.unsupportedPackage
    }

    private static func protobuf(_ data: Data) throws -> [(Int, Data)] {
        let reader = ApkBytes(data: data)
        var cursor = 0
        var fields = [(Int, Data)]()
        while cursor < data.count {
            let tag = try reader.varint(&cursor)
            guard tag >> 3 > 0 else { throw HongguoApkError.invalidArchive }
            if tag & 7 == 0 { _ = try reader.varint(&cursor) }
            else if tag & 7 == 2 {
                let length = try reader.varint(&cursor)
                guard length <= UInt64(data.count - cursor) else { throw HongguoApkError.invalidArchive }
                fields.append((Int(tag >> 3), try reader.bytes(cursor, Int(length))))
                cursor += Int(length)
            } else { throw HongguoApkError.invalidArchive }
        }
        return fields
    }

    static func compatibleConfiguration(_ text: String) -> Bool {
        guard text.count % 4 == 0, let raw = Data(base64Encoded: text), raw.count >= 20, (raw.count - 4) % 16 == 0 else { return false }
        let prefix = raw.prefix(4)
        let app = Data("8662".utf8)
        let key = Data(Insecure.MD5.hash(data: app + prefix + app))
        var plain = Data(count: raw.count + 16)
        var outputCount = 0
        let capacity = plain.count
        let result = key.withUnsafeBytes { k in
            raw.withUnsafeBytes { input in
                plain.withUnsafeMutableBytes { output in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding), k.baseAddress, key.count, nil, input.baseAddress!.advanced(by: 4), raw.count - 4, output.baseAddress, capacity, &outputCount)
                }
            }
        }
        guard result == kCCSuccess, outputCount >= 8 else { return false }
        plain.count = outputCount
        let head = plain.prefix(4)
        let tail = plain.suffix(4)
        let streamKey = Array(Insecure.SHA1.hash(data: head + app + prefix))
        var state = Array(UInt8.min...UInt8.max)
        var j = 0
        for i in 0..<256 { j = (j + Int(state[i]) + Int(streamKey[i % streamKey.count])) & 255; state.swapAt(i, j) }
        var i = 0
        j = 0
        var decoded = [UInt8]()
        for value in plain.dropFirst(4).dropLast(4) {
            i = (i + 1) & 255; j = (j + Int(state[i])) & 255; state.swapAt(i, j)
            decoded.append(value ^ state[(Int(state[i]) + Int(state[j])) & 255])
        }
        let mask = (prefix + head + tail).reduce(UInt8(0), ^)
        let message = Data(decoded.reversed().map { $0 ^ mask })
        guard let fields = try? protobuf(message), fields.contains(where: { $0.0 == 2 && $0.1 == Data("mssdk".utf8) }),
              fields.contains(where: { $0.0 == 5 && $0.1 == app }) else { return false }
        var keys = Set<String>()
        for (_, value) in fields.filter({ $0.0 == 8 }) {
            guard let child = try? protobuf(value), let nameData = child.first(where: { $0.0 == 1 })?.1,
                  let name = String(data: nameData, encoding: .utf8), ["common_key", "sign_key"].contains(name),
                  let encoded = child.first(where: { $0.0 == 2 })?.1, let keyText = String(data: encoded, encoding: .utf8),
                  let key = Data(base64Encoded: keyText), key.count == 32 else { return false }
            guard keys.insert(name).inserted else { return false }
        }
        return keys == ["common_key", "sign_key"]
    }
}
