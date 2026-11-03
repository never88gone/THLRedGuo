import XCTest
import CryptoKit
import Security
@testable import THLRedLook

@MainActor
final class AccountPairingTests: XCTestCase {
    func testProgressReadUsesMatchingServerHistoryAfterSpecificRejection() async throws {
        for matching in [true, false] {
            var actions: [String] = []
            do {
                let rows = try await HongguoAccountModel.progressRows(id: "123") { action, _ in
                    actions.append(action)
                    if action == "progressGet" { throw HongguoAccountError.business(101112) }
                    return ["items": [["id": matching ? "123" : "456", "episode": 2, "positionMs": 12000]]]
                }
                XCTAssertTrue(matching)
                XCTAssertEqual(rows.first?["positionMs"] as? Int, 12000)
            } catch { XCTAssertFalse(matching); XCTAssertEqual(error as? HongguoAccountError, .business(101112)) }
            XCTAssertEqual(actions, ["progressGet", "history"])
        }
        var actions: [String] = []
        do {
            _ = try await HongguoAccountModel.progressRows(id: "123") { action, _ in
                actions.append(action)
                throw HongguoAccountError.business(15)
            }
            XCTFail("Authentication errors must remain failures")
        } catch { XCTAssertEqual(error as? HongguoAccountError, .business(15)) }
        XCTAssertEqual(actions, ["progressGet"])
    }

    func testAccountKeychainRoundTrip() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "THLAccountStorageTest.\(UUID().uuidString)",
            kSecAttrAccount as String: "synthetic"
        ]
        defer { SecItemDelete(query as CFDictionary) }
        let data = Data("synthetic-test-record".utf8)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        var lookup = query
        lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(lookup as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual(result as? Data, data)
    }

    func testAccountWritebackSignedJsonContractsWithoutNetwork() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "THLWritebackProtocol.\(UUID().uuidString)"))
        defaults.set("{\"iid\":\"7345678901234567200\",\"device_id\":\"7345678901234567100\",\"cdid\":\"synthetic-device\"}", forKey: "thl_tv_hongguo_device_session")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WritebackBlockedProtocol.self]
        let bridge = NativeBridge(httpSession: URLSession(configuration: config), deviceDefaults: defaults)
        let id = "7688558312157088793"
        let follow = try await bridge.accountRequest("favoriteUpdate", payload: ["id": id, "follow": "1"])
        XCTAssertEqual(follow["method"] as? String, "POST")
        let body = try XCTUnwrap(follow["body"] as? String)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let row = try XCTUnwrap((parsed["update_bookshelf_video_list"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["book_id"] as? String, id)
        XCTAssertEqual(row["video_shelf_operate_type"] as? Int, 0)
        let request = try await bridge.accountRequest("progressUpdate", payload: ["id":id,"itemId":"7688558312157088794","episode":"4","positionMs":"12345","durationMs":"95678","episodes":"60","updatedAt":"1700000000000"])
        let progressBody = try XCTUnwrap(request["body"] as? String)
        let progress = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(progressBody.utf8)) as? [String: Any])
        XCTAssertEqual(progress["write_mode"] as? Int, 1)
        let book = try XCTUnwrap((progress["books"] as? [[String: Any]])?.first)
        XCTAssertEqual(book["current_play_time"] as? Int, 12345)
        XCTAssertEqual(book["vid_index"] as? Int, 4)
        let lookup = try await bridge.accountRequest("progressGet", payload: ["id":id])
        XCTAssertEqual(lookup["method"] as? String, "POST")
        let readBody = try XCTUnwrap(lookup["body"] as? String)
        let read = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(readBody.utf8)) as? [String: Any])
        XCTAssertEqual((read["book_ids"] as? [String: [NSNumber]])?["2"]?.first?.stringValue, id)
        let accepted = try await bridge.accountParse("progressUpdate", body: "{\"code\":0}")
        XCTAssertEqual(accepted["valid"] as? Bool, true)
    }
    func testExpiredAccountDoesNotExposeTrackingCookiesOrAppearLoggedIn() async throws {
        let expired = HongguoAccountRecord(id: "123", nickname: "synthetic", cookies: [
            HongguoCookie(name: "sessionid", value: "synthetic-expired", domain: "hongguoduanju.com", path: "/", expires: .distantPast),
            HongguoCookie(name: "uid_tt", value: "synthetic-tracking", domain: "hongguoduanju.com", path: "/", expires: nil)
        ], device: ["device_id": "7345678901234567999", "iid": "7345678901234567998", "cdid": "expired-synthetic"])
        XCTAssertFalse(expired.hasSession)
        let url = try XCTUnwrap(URL(string: "https://api5-normal-sinfonlinea.fqnovel.com/reading/user/info/v1/"))
        XCTAssertEqual(HongguoAccountVault.shared.header(for: url, record: expired), "")
        let name = "THLExpiredAccount.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("{\"iid\":\"7345678901234567200\",\"device_id\":\"7345678901234567100\",\"cdid\":\"synthetic-device\"}", forKey: "thl_tv_hongguo_device_session")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WritebackBlockedProtocol.self]
        let bridge = NativeBridge(httpSession: URLSession(configuration: config), deviceDefaults: defaults, accountSnapshot: { (expired, 0) })
        let command = try await bridge.accountRequest("progressGet", payload: ["id": "7688558312157088793"])
        let query = try XCTUnwrap(URLComponents(string: command["url"] as? String ?? "")?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "device_id" })?.value, "7345678901234567100")
    }

    private func vector() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("test/fixtures/account_pairing_vector.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func testIndependentNodeCryptoVectorAndAuthentication() throws {
        let fixture = try vector()
        let cipher = AccountPairCipher(id: try XCTUnwrap(fixture["id"] as? String), key: try AccountPairCipher.decode(fixture["key"], max: 32), expires: Date().addingTimeInterval(60))
        let envelope = try XCTUnwrap(fixture["envelope"] as? [String: Any])
        let payload = try cipher.open(envelope, response: false)
        XCTAssertEqual(payload["action"] as? String, "hello")
        XCTAssertEqual(payload["requestId"] as? String, "abcdef0123456789abcdef0123456789")
        XCTAssertThrowsError(try cipher.open(envelope, response: true))
        var changed = envelope; changed["cipher"] = "AQID"
        XCTAssertThrowsError(try cipher.open(changed, response: false))
        let expired = AccountPairCipher(id: cipher.id, key: cipher.key, expires: .distantPast)
        XCTAssertThrowsError(try expired.open(envelope, response: false))
    }
    private func candidateData() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["v": 1, "id": "1234567890123456789",
            "cookies": [["name": "sessionid", "value": "synthetic-test-session", "domain": "hongguoduanju.com", "path": "/", "expires": NSNull()]],
            "device": ["iid": "7345678901234567200", "device_id": "7345678901234567100", "cdid": "synthetic-device"]])
    }
    func testSessionPayloadScopeAndForbiddenFields() throws {
        let bytes = try candidateData()
        let record = try AccountTransferRecord.decode(bytes)
        XCTAssertEqual(record.id, "1234567890123456789")
        XCTAssertEqual(record.cookies.count, 1)
        var changed = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        changed["material"] = "forbidden"
        XCTAssertThrowsError(try AccountTransferRecord.decode(JSONSerialization.data(withJSONObject: changed)))
        changed.removeValue(forKey: "material")
        changed["cookies"] = [["name": "passport_csrf_token", "value": "synthetic", "domain": "hongguoduanju.com", "path": "/"]]
        XCTAssertThrowsError(try AccountTransferRecord.decode(JSONSerialization.data(withJSONObject: changed)))
    }
    func testPhoneRoutesMixingAndChallengeRemainReadOnly() async throws {
        func mix(_ text: String) -> String { text.utf8.map { String($0 ^ 5, radix: 16) }.joined() }
        for action in ["phoneCode", "phoneSms"] {
            let request = try await NativeBridge.shared.accountRequest(action, payload: ["country": "86", "number": "13800138000", "code": "654321"])
            let url = try XCTUnwrap(URL(string: try XCTUnwrap(request["url"] as? String)))
            XCTAssertEqual(url.host, "hongguoduanju.com")
            XCTAssertEqual(request["method"] as? String, "POST")
            let query = try XCTUnwrap(URLComponents(string: "https://fixture.test/?" + (request["body"] as? String ?? ""))?.queryItems)
            let fields = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(fields["mix_mode"], "1")
            switch action {
            case "phoneCode": XCTAssertEqual(url.path, "/passport/web/send_code"); XCTAssertEqual(fields["type"], mix("24"))
            case "phoneSms": XCTAssertEqual(url.path, "/passport/web/sms_login_only"); XCTAssertEqual(fields["code"], mix("654321"))
            default: XCTFail("Unexpected account action")
            }
        }
        do {
            _ = try await NativeBridge.shared.accountRequest("phonePassword")
            XCTFail("Password login must not be available")
        } catch {}
        do {
            _ = try await NativeBridge.shared.accountParse("phoneCode", body: "{\"message\":\"error\",\"data\":{\"error_code\":1102,\"verify_center_decision_conf\":{}}}")
            XCTFail("Official challenge must remain visible")
        } catch { XCTAssertEqual(error as? HongguoAccountError, .challenge) }
    }
    private func ready(_ server: AccountPairingServer) async throws -> (AccountPairCipher, URL) {
        let end = Date().addingTimeInterval(5)
        while server.qr == nil && Date() < end { try await Task.sleep(for: .milliseconds(20)) }
        let raw = try XCTUnwrap(server.qr)
        let url = try XCTUnwrap(URLComponents(string: raw))
        let q = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let key = try AccountPairCipher.decode(url.fragment?.replacingOccurrences(of: "key=", with: ""), max: 32)
        let cipher = AccountPairCipher(id: try XCTUnwrap(q["id"]), key: key, expires: Date(timeIntervalSince1970: try XCTUnwrap(Double(q["expires"] ?? ""))))
        var endpoint = URLComponents(); endpoint.scheme = "http"; endpoint.host = q["host"]; endpoint.port = Int(q["port"] ?? ""); endpoint.path = "/thl/account-pair/v1"
        return (cipher, try XCTUnwrap(endpoint.url))
    }
    private func send(_ envelope: [String: Any], to url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        let session = URLSession(configuration: config); defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }
    func testHTTPEncryptedHandshakeReplayAndSyntheticAcceptance() async throws {
        var validated = 0, committed = 0
        let original = HongguoAccountVault.shared.snapshot
        let server = AccountPairingServer(validator: { record, revision, current in
            XCTAssertEqual(record.id, "1234567890123456789")
            XCTAssertEqual(revision, original.revision)
            XCTAssertTrue(current()); validated += 1
            return HongguoVerifiedTransfer(record: record, revision: revision, owner: 0)
        }, committer: { _, current in XCTAssertTrue(current()); committed += 1 })
        server.approveReplacement = { _ in true }
        defer { server.stop() }
        server.start()
        let (cipher, endpoint) = try await ready(server)
        let requestID = "0123456789abcdef0123456789abcdef"
        let hello = try cipher.seal(["action": "hello", "requestId": requestID], response: false)
        let (data, response) = try await send(hello, to: endpoint)
        XCTAssertEqual(response.statusCode, 200)
        let helloReply = try cipher.open(XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]), response: true)
        XCTAssertEqual(helloReply["status"] as? String, "ready"); XCTAssertEqual(validated, 0)
        let (_, replay) = try await send(hello, to: endpoint)
        XCTAssertEqual(replay.statusCode, 400)
        let encrypted = try cipher.seal(["action": "session", "requestId": requestID, "session": AccountPairCipher.encode(candidateData())], response: false)
        let (acceptedData, acceptedResponse) = try await send(encrypted, to: endpoint)
        XCTAssertEqual(acceptedResponse.statusCode, 200)
        let result = try cipher.open(XCTUnwrap(JSONSerialization.jsonObject(with: acceptedData) as? [String: Any]), response: true)
        XCTAssertEqual(result["status"] as? String, "validated"); XCTAssertEqual(validated, 1); XCTAssertEqual(committed, 0)
        let commit = try cipher.seal(["action": "commit", "requestId": "abcdef0123456789abcdef0123456789", "transferId": requestID], response: false)
        let (commitData, commitResponse) = try await send(commit, to: endpoint)
        XCTAssertEqual(commitResponse.statusCode, 200)
        let commitResult = try cipher.open(XCTUnwrap(JSONSerialization.jsonObject(with: commitData) as? [String: Any]), response: true)
        XCTAssertEqual(commitResult["status"] as? String, "accepted"); XCTAssertEqual(committed, 1)
        XCTAssertTrue(server.accepted)
        XCTAssertTrue(HongguoAccountVault.shared.snapshot.record?.id == original.record?.id)
        XCTAssertEqual(HongguoAccountVault.shared.snapshot.revision, original.revision)
    }
}

private final class WritebackBlockedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)) }
    override func stopLoading() {}
}
