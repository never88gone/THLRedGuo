import Foundation

final class HongguoFixtureProtocol: URLProtocol {
    static var rejectPlayback = false
    static var queries: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        var status = 200
        var value: [String: Any] = [:]
        switch url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
        case "novel/player/video_detail/v1":
            value = ["data": ["video_data": [
                "series_title": "合成原生剧集",
                "video_list": [["vid": "7345678901234568000"], ["vid": "7345678901234568001"]]
            ]]]
        case "incent_resource/suggestion":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "query" }?.value ?? ""
            Self.queries.append(query)
            value = ["suggest_list": [[
                "series_id": "7345678901234567000", "name": "合成搜索结果",
                "video_data": ["cover_url": "https://images.example.test/never-requested.jpg"]
            ]]]
        case "novel/player/video_model/v1":
            if !Self.rejectPlayback {
                let address = Data("https://media.example.test/720p.mp4".utf8).base64EncodedString()
                value = ["data": ["video_model": ["video_list": ["video_1": ["main_url": address, "video_meta": ["codec_type": "h264"]]]]]]
            } else { status = 403 }
        default:
            status = 404
        }
        if url.path.range(of: "\\.(jpg|jpeg|png|webp)$", options: .regularExpression) != nil {
            fatalError("禁止请求站源图片")
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: value))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct VerifyTVOSBridge {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HongguoFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let bridge = NativeBridge(baseDirectory: directory, httpSession: session)
        try await bridge.ensureInitialized()

        let categories = try await bridge.request(action: "categories", payload: ["source": "hongguo"])
        precondition((categories["items"] as? [[String: Any]])?.count == 4)
        print("PASS native categories")

        let query = "合成\"关键词\\换行\n"
        let search = try await bridge.request(action: "search", payload: ["source": "hongguo", "query": query])
        precondition((search["items"] as? [[String: Any]])?.count == 1)
        precondition(HongguoFixtureProtocol.queries.last == query)
        let found = (search["items"] as! [[String: Any]])[0]
        precondition(found["id"] as? String == "hongguo:7345678901234567000")
        precondition(found["sourceId"] as? String == "7345678901234567000")
        print("PASS native quoted search")

        let drama: [String: Any] = ["id": "hongguo:7345678901234567000", "source": "hongguo", "sourceId": "7345678901234567000", "title": "合成剧集"]
        let detail = try await bridge.request(action: "detail", payload: ["drama": drama])
        let episodes = detail["chapters"] as! [[String: Any]]
        precondition(episodes.count == 2)
        precondition((episodes[0]["url"] as? String)?.hasSuffix("7345678901234568000") == true)
        print("PASS native exact episode IDs")

        let payload: [String: Any] = ["drama": drama, "index": 2, "chapter": episodes[1], "quality": 1080]
        let plan = try await bridge.request(action: "resolve", payload: payload)
        precondition(plan["url"] as? String == "https://media.example.test/720p.mp4")
        precondition(plan["quality"] as? Int == 720)
        precondition(plan["qualities"] as? [Int] == [720])
        print("PASS native base64 model and actual quality")

        HongguoFixtureProtocol.rejectPlayback = true
        do {
            _ = try await bridge.request(action: "resolve", payload: payload)
            fatalError("取流失败必须报错")
        } catch {
            print("PASS native failed playback rejects fabricated URL")
        }
        print("5 native bridge checks passed")
    }
}
