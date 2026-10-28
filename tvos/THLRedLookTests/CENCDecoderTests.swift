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

    private func fixture(subsamples: Bool, paddingBytes: Int = 0) -> Data {
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
        let padding = paddingBytes > 0 ? box("free", Data(repeating: 0, count: paddingBytes)) : Data()
        return ftyp + moov(ftyp.count + moov(0).count + padding.count + 8) + padding + box("mdat", sample)
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
    private func stream(mode: String) async throws -> CENCStreamSession {
        RangeFailureProtocol.configure(data: fixture(subsamples: true, paddingBytes: 1024 * 1024), mode: mode)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RangeFailureProtocol.self]
        let stream = CENCStreamSession(url: URL(string: "https://fixture.invalid/encrypted.mp4")!, headers: [:], key: Array(bytes("2b7e151628aed2a6abf7158809cf4f3c")), configuration: config)
        _ = try await stream.prepare()
        return stream
    }

    func testLaterRangeRetriesTransientFailuresWithoutRestartingStream() async throws {
        for mode in ["503", "timeout", "truncated"] {
            let stream = try await stream(mode: mode)
            let stats = await stream.statistics()
            let tail = try await stream.read(offset: try XCTUnwrap(stats["mediaBytes"]) - 16, count: 16)
            XCTAssertEqual(tail, bytes("6bc1bee22e409f96e93d7e117393172a"))
            XCTAssertEqual(RangeFailureProtocol.starts.filter { $0 == 0 }.count, 1)
            XCTAssertEqual(RangeFailureProtocol.starts.count, 3)
            XCTAssertEqual(RangeFailureProtocol.starts.suffix(2).first, RangeFailureProtocol.starts.last)
            await stream.close()
        }
    }

    func testForbiddenRangeStopsForFreshPlaybackURL() async throws {
        let stream = try await stream(mode: "403")
        let stats = await stream.statistics()
        do {
            _ = try await stream.read(offset: try XCTUnwrap(stats["mediaBytes"]) - 16, count: 16)
            XCTFail("Permanent denial cannot be retried as a transport failure")
        } catch {
            XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "MEDIA_HTTP_403")
        }
        XCTAssertEqual(RangeFailureProtocol.starts.count, 2)
        await stream.close()
    }

    func testPersistentRangeFailuresAreBoundedAndCanBeCancelled() async throws {
        let stream = try await stream(mode: "persistent")
        let stats = await stream.statistics()
        do {
            _ = try await stream.read(offset: try XCTUnwrap(stats["mediaBytes"]) - 16, count: 16)
            XCTFail("Persistent failures must surface")
        } catch { XCTAssertEqual((error as NSError).code, 503) }
        XCTAssertEqual(RangeFailureProtocol.starts.count, 4)
        await stream.close()
        let cancelled = try await self.stream(mode: "persistent")
        let cancelledStats = await cancelled.statistics()
        let length = try XCTUnwrap(cancelledStats["mediaBytes"])
        let pending = Task { try await cancelled.read(offset: length - 16, count: 16) }
        while RangeFailureProtocol.starts.count < 2 { try await Task.sleep(nanoseconds: 10_000_000) }
        await cancelled.close()
        pending.cancel()
        do { _ = try await pending.value; XCTFail("Closed stream must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(RangeFailureProtocol.starts.count, 2)
    }

}


private final class RangeFailureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var data = Data()
    private static var mode = ""
    private static var offsets: [Int64] = []
    static var starts: [Int64] { lock.withLock { offsets } }
    static func configure(data: Data, mode: String) { lock.withLock { self.data = data; self.mode = mode; offsets = [] } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let range = (request.value(forHTTPHeaderField: "Range") ?? "").dropFirst(6).split(separator: "-").compactMap { Int($0) }
        guard range.count == 2 else { return }
        let (data, mode, attempt) = Self.lock.withLock { () -> (Data, String, Int) in
            Self.offsets.append(Int64(range[0]))
            return (Self.data, Self.mode, Self.offsets.count)
        }
        let fail = range[0] > 0 && (attempt == 2 || ["persistent", "403"].contains(mode))
        if fail, mode == "timeout" { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
        let end = min(range[1], data.count - 1)
        let headers = ["Content-Type": "video/mp4", "Content-Range": "bytes \(range[0])-\(end)/\(data.count)", "Content-Length": String(end - range[0] + 1)]
        let status = fail && mode != "truncated" ? (mode == "403" ? 403 : 503) : 206
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        if status == 206 { client?.urlProtocol(self, didLoad: data.subdata(in: range[0]..<(fail ? end : end + 1))) }
        client?.urlProtocolDidFinishLoading(self)
    }
}
