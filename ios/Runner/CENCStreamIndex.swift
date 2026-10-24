import Foundation
import CommonCrypto

struct CENCStreamIndex {
    struct Region {
        let offset: Int64
        let count: Int
        let iv: [UInt8]
        let cipherOffset: Int
        var end: Int64 { offset + Int64(count) }
    }

    private struct Box {
        let type: String
        let start: Int
        let size: Int
        let header: Int
        var payload: Int { start + header }
        var end: Int { start + size }
    }

    let moovOffset: Int64
    let moov: Data
    private let regions: [Region]

    init(data: Data, offset: Int64, fileSize: Int64) throws {
        var patched = data
        let roots = try Self.boxes(data, 0, data.count)
        guard roots.count == 1, let root = roots.first, root.type == "moov" else { throw Self.invalid() }
        var regions = [Region]()
        let children = try Self.boxes(data, root.payload, root.end)
        for track in children where track.type == "trak" {
            regions += try Self.track(data, track, fileSize, &patched)
        }
        guard !regions.isEmpty else { throw Self.invalid() }
        for child in children where child.type == "pssh" { Self.free(&patched, child) }
        regions.sort { $0.offset < $1.offset }
        for index in regions.indices.dropFirst() {
            guard regions[index - 1].end <= regions[index].offset else { throw Self.invalid() }
        }
        self.moovOffset = offset
        self.moov = patched
        self.regions = regions
    }

    func decrypt(_ encrypted: Data, offset: Int64, key: [UInt8]) throws -> Data {
        guard key.count == 16, offset >= 0, encrypted.count <= 1024 * 1024 else { throw Self.invalid() }
        var result = encrypted
        let end = offset + Int64(result.count)
        let overlapStart = max(offset, moovOffset)
        let overlapEnd = min(end, moovOffset + Int64(moov.count))
        if overlapStart < overlapEnd {
            let local = Int(overlapStart - offset)..<Int(overlapEnd - offset)
            let source = Int(overlapStart - moovOffset)..<Int(overlapEnd - moovOffset)
            result.replaceSubrange(local, with: moov[source])
        }
        var low = 0
        var high = regions.count
        while low < high {
            let middle = (low + high) / 2
            if regions[middle].end <= offset { low = middle + 1 } else { high = middle }
        }
        var index = low
        try result.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            while index < regions.count, regions[index].offset < end {
                let region = regions[index]
                let start = max(offset, region.offset)
                let finish = min(end, region.end)
                if start < finish {
                    let cipherOffset = region.cipherOffset + Int(start - region.offset)
                    var iv = region.iv
                    var blocks = UInt64(cipherOffset / 16)
                    for byte in stride(from: 15, through: 8, by: -1) {
                        let value = UInt64(iv[byte]) + (blocks & 255)
                        iv[byte] = UInt8(value & 255)
                        blocks = (blocks >> 8) + (value >> 8)
                    }
                    var cryptor: CCCryptorRef?
                    let status = CCCryptorCreateWithMode(CCOperation(kCCDecrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), iv, key, key.count, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
                    guard status == kCCSuccess, let cryptor else { throw Self.invalid() }
                    defer { CCCryptorRelease(cryptor) }
                    let skip = cipherOffset % 16
                    if skip > 0 {
                        let zeros = [UInt8](repeating: 0, count: skip)
                        var discarded = [UInt8](repeating: 0, count: skip)
                        var moved = 0
                        guard CCCryptorUpdate(cryptor, zeros, skip, &discarded, skip, &moved) == kCCSuccess, moved == skip else { throw Self.invalid() }
                    }
                    let pointer = base.advanced(by: Int(start - offset))
                    let count = Int(finish - start)
                    var moved = 0
                    guard CCCryptorUpdate(cryptor, pointer, count, pointer, count, &moved) == kCCSuccess, moved == count else { throw Self.invalid() }
                }
                index += 1
            }
        }
        return result
    }

    private static func track(_ data: Data, _ track: Box, _ fileSize: Int64, _ patched: inout Data) throws -> [Region] {
        guard let mdia = try child(data, track, "mdia"), let minf = try child(data, mdia, "minf"), let stbl = try child(data, minf, "stbl") else { return [] }
        let boxes = try boxes(data, stbl.payload, stbl.end)
        guard let stsd = boxes.first(where: { $0.type == "stsd" }) else { return [] }
        for box in boxes where ["sgpd", "sbgp"].contains(box.type) {
            guard box.payload + 8 <= box.end, fourCC(data, box.payload + 4) != "seig" else { throw invalid() }
        }
        guard stsd.payload + 8 <= stsd.end else { throw invalid() }
        let descriptions = try Self.boxes(data, stsd.payload + 8, stsd.end)
        guard let entry = descriptions.first else { throw invalid() }
        guard entry.type == "encv" || entry.type == "enca" else { return [] }
        guard read32(data, stsd.payload + 4) == 1, descriptions.count == 1 else { throw invalid() }
        let start = entry.start + (entry.type == "encv" ? 86 : 36)
        guard start <= entry.end else { throw invalid() }
        let extensions = try Self.boxes(data, start, entry.end)
        guard let sinf = extensions.first(where: { $0.type == "sinf" }), let frma = try child(data, sinf, "frma"), let schm = try child(data, sinf, "schm"), let schi = try child(data, sinf, "schi"), let tenc = try child(data, schi, "tenc") else { throw invalid() }
        guard frma.payload + 4 <= frma.end, schm.payload + 8 <= schm.end, fourCC(data, schm.payload + 4) == "cenc", tenc.payload + 24 <= tenc.end, data[tenc.payload] == 0 else { throw invalid() }
        var ivSize = Int(data[tenc.payload + 7])
        guard [8, 16].contains(ivSize), data[tenc.payload + 6] == 1 else { throw invalid() }
        patched.replaceSubrange(entry.start + 4..<entry.start + 8, with: data[frma.payload..<frma.payload + 4])
        free(&patched, sinf)
        guard let stsz = boxes.first(where: { $0.type == "stsz" }), let stsc = boxes.first(where: { $0.type == "stsc" }), let offsets = boxes.first(where: { $0.type == "stco" || $0.type == "co64" }), let senc = boxes.first(where: { $0.type == "senc" }) else { throw invalid() }
        guard stsz.payload + 12 <= stsz.end else { throw invalid() }
        let uniform = Int(read32(data, stsz.payload + 4))
        let count = Int(read32(data, stsz.payload + 8))
        guard count > 0, count <= 2_000_000, uniform > 0 || count <= (stsz.end - stsz.payload - 12) / 4 else { throw invalid() }
        let sizes = (0..<count).map { uniform > 0 ? uniform : Int(read32(data, stsz.payload + 12 + $0 * 4)) }
        guard stsc.payload + 8 <= stsc.end else { throw invalid() }
        let mappingCount = Int(read32(data, stsc.payload + 4))
        guard mappingCount > 0, mappingCount <= (stsc.end - stsc.payload - 8) / 12 else { throw invalid() }
        var mappings = [(chunk: Int, count: Int)]()
        for i in 0..<mappingCount {
            let p = stsc.payload + 8 + i * 12
            let first = Int(read32(data, p))
            let samples = Int(read32(data, p + 4))
            guard first > (mappings.last?.chunk ?? 0), samples > 0, samples <= count, read32(data, p + 8) == 1 else { throw invalid() }
            mappings.append((first, samples))
        }
        guard mappings.first?.chunk == 1, offsets.payload + 8 <= offsets.end else { throw invalid() }
        let width = offsets.type == "co64" ? 8 : 4
        let chunks = Int(read32(data, offsets.payload + 4))
        guard chunks > 0, chunks <= (offsets.end - offsets.payload - 8) / width else { throw invalid() }
        var sampleOffsets = [Int64]()
        sampleOffsets.reserveCapacity(count)
        var mapIndex = 0
        for chunk in 1...chunks {
            while mapIndex + 1 < mappings.count, mappings[mapIndex + 1].chunk <= chunk { mapIndex += 1 }
            let p = offsets.payload + 8 + (chunk - 1) * width
            let raw = width == 8 ? read64(data, p) : UInt64(read32(data, p))
            guard raw <= UInt64(fileSize) else { throw invalid() }
            var offset = Int64(raw)
            for _ in 0..<mappings[mapIndex].count {
                guard sampleOffsets.count < count else { throw invalid() }
                let size = sizes[sampleOffsets.count]
                guard size > 0, offset <= fileSize - Int64(size) else { throw invalid() }
                sampleOffsets.append(offset)
                offset += Int64(size)
            }
        }
        guard sampleOffsets.count == count, senc.payload + 8 <= senc.end else { throw invalid() }
        let flags = read32(data, senc.payload) & 0x00ff_ffff
        guard data[senc.payload] == 0, flags & ~UInt32(3) == 0 else { throw invalid() }
        var cursor = senc.payload + 4
        if flags & 1 != 0 {
            guard cursor + 20 <= senc.end else { throw invalid() }
            ivSize = Int(data[cursor + 3])
            guard [8, 16].contains(ivSize) else { throw invalid() }
            cursor += 20
        }
        guard cursor + 4 <= senc.end, Int(read32(data, cursor)) == count else { throw invalid() }
        cursor += 4
        var regions = [Region]()
        for sample in 0..<count {
            guard cursor + ivSize <= senc.end else { throw invalid() }
            var iv = [UInt8](repeating: 0, count: 16)
            for b in 0..<ivSize { iv[b] = data[cursor + b] }
            cursor += ivSize
            if flags & 2 == 0 {
                regions.append(Region(offset: sampleOffsets[sample], count: sizes[sample], iv: iv, cipherOffset: 0))
                continue
            }
            guard cursor + 2 <= senc.end else { throw invalid() }
            let subsamples = Int(read16(data, cursor))
            cursor += 2
            guard subsamples <= (senc.end - cursor) / 6 else { throw invalid() }
            var total = 0
            var cipher = 0
            for _ in 0..<subsamples {
                let clear = Int(read16(data, cursor))
                let encrypted = Int(read32(data, cursor + 2))
                cursor += 6
                guard clear <= sizes[sample] - total, encrypted <= sizes[sample] - total - clear else { throw invalid() }
                total += clear
                if encrypted > 0 {
                    regions.append(Region(offset: sampleOffsets[sample] + Int64(total), count: encrypted, iv: iv, cipherOffset: cipher))
                    total += encrypted
                    cipher += encrypted
                }
            }
        }
        guard cursor == senc.end else { throw invalid() }
        for box in boxes where ["senc", "saio", "saiz"].contains(box.type) { free(&patched, box) }
        return regions
    }

    private static func child(_ data: Data, _ parent: Box, _ type: String) throws -> Box? {
        try boxes(data, parent.payload, parent.end).first { $0.type == type }
    }

    private static func boxes(_ data: Data, _ start: Int, _ end: Int) throws -> [Box] {
        guard start >= 0, end <= data.count, start <= end else { throw invalid() }
        var result = [Box]()
        var cursor = start
        while cursor < end {
            guard cursor + 8 <= end else { throw invalid() }
            let size = read32(data, cursor)
            let header = size == 1 ? 16 : 8
            guard cursor + header <= end else { throw invalid() }
            let length = size == 1 ? read64(data, cursor + 8) : size == 0 ? UInt64(end - cursor) : UInt64(size)
            guard length >= UInt64(header), length <= UInt64(end - cursor) else { throw invalid() }
            result.append(Box(type: fourCC(data, cursor + 4), start: cursor, size: Int(length), header: header))
            cursor += Int(length)
        }
        return result
    }

    private static func free(_ data: inout Data, _ box: Box) {
        data.replaceSubrange(box.start + 4..<box.start + 8, with: Data("free".utf8))
    }

    static func read16(_ data: Data, _ index: Int) -> UInt16 {
        UInt16(data[index]) << 8 | UInt16(data[index + 1])
    }

    static func read32(_ data: Data, _ index: Int) -> UInt32 {
        UInt32(data[index]) << 24 | UInt32(data[index + 1]) << 16 | UInt32(data[index + 2]) << 8 | UInt32(data[index + 3])
    }

    static func read64(_ data: Data, _ index: Int) -> UInt64 {
        UInt64(read32(data, index)) << 32 | UInt64(read32(data, index + 4))
    }

    static func fourCC(_ data: Data, _ index: Int) -> String {
        String(decoding: data[index..<index + 4], as: UTF8.self)
    }

    static func invalid() -> NSError {
        NSError(domain: "THLEncryptedStream", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前媒体暂不支持按需解密"])
    }
}
