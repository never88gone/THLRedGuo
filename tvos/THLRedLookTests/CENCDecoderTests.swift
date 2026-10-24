import XCTest
@testable import THLRedLook

final class CENCDecoderTests: XCTestCase {
    private func bytes(_ hex: String) -> Data {
        var result = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            result.append(UInt8(hex[index..<end], radix: 16)!)
            index = end
        }
        return result
    }

    private func number(_ value: Int) -> Data {
        var big = UInt32(value).bigEndian
        return withUnsafeBytes(of: &big) { Data($0) }
    }

    private func box(_ type: String, _ contents: Data) -> Data {
        number(contents.count + 8) + Data(type.utf8) + contents
    }

    private func fixture(subsamples: Bool) -> Data {
        let encrypted = bytes("874d6191b620e3261bef6864990db6ce")
        let sample = (subsamples ? Data("THL!".utf8) : Data()) + encrypted
        let tenc = box("tenc", Data(repeating: 0, count: 6) + Data([1, 16]) + Data(repeating: 0, count: 16))
        let sinf = box("sinf", box("frma", Data("avc1".utf8)) + box("schm", number(0) + Data("cenc".utf8) + number(65536)) + box("schi", tenc))
        let entry = box("encv", Data(repeating: 0, count: 78) + sinf)
        let stsd = box("stsd", number(0) + number(1) + entry)
        let stsz = box("stsz", number(0) + number(0) + number(1) + number(sample.count))
        let stsc = box("stsc", number(0) + number(1) + number(1) + number(1) + number(1))
        let sub = subsamples ? Data([0, 1, 0, 4]) + number(16) : Data()
        let senc = box("senc", number(subsamples ? 2 : 0) + number(1) + bytes("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff") + sub)
        func moov(_ offset: Int) -> Data {
            let stco = box("stco", number(0) + number(1) + number(offset))
            return box("moov", box("trak", box("mdia", box("minf", box("stbl", stsd + stsz + stsc + stco + senc)))))
        }
        let ftyp = box("ftyp", Data("isom".utf8) + number(0) + Data("isom".utf8))
        return ftyp + moov(ftyp.count + moov(0).count + 8) + box("mdat", sample)
    }

    func testNISTCTRWith16ByteIVAndSubsampleFlag() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for subsamples in [false, true] {
            let input = directory.appendingPathComponent("input.mp4")
            let output = directory.appendingPathComponent("output.mp4")
            try fixture(subsamples: subsamples).write(to: input)
            try CENCMP4Decryptor.shared.decryptDownloadedFile(at: input, hexKey: "2b7e151628aed2a6abf7158809cf4f3c", destinationURL: output)
            let data = try Data(contentsOf: output)
            XCTAssertEqual(data.suffix(16), bytes("6bc1bee22e409f96e93d7e117393172a"))
            if subsamples { XCTAssertEqual(data.suffix(20).prefix(4), Data("THL!".utf8)) }
        }
    }

    func testTruncatedMediaRejectsWithoutWritingOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = fixture(subsamples: true)
        for length in [0, 4, data.count - 1, data.count - 20] {
            let input = directory.appendingPathComponent("input.mp4")
            let output = directory.appendingPathComponent("output.mp4")
            try data.prefix(length).write(to: input)
            XCTAssertThrowsError(try CENCMP4Decryptor.shared.decryptDownloadedFile(at: input, hexKey: "2b7e151628aed2a6abf7158809cf4f3c", destinationURL: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }
}
