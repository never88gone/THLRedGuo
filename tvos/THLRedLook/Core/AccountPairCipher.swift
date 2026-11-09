import Foundation
import CryptoKit
import Security

struct AccountPairCipher {
    let id: String
    let key: Data
    let expires: Date
    static func random(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let result = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard result == errSecSuccess else { throw HongguoAccountError.storage }
        return bytes
    }
    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ value: Any?, max: Int) throws -> Data {
        guard let value = value as? String, value.count <= max * 2,
            value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw HongguoAccountError.invalid }
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        guard let bytes = Data(base64Encoded: padded), bytes.count <= max else { throw HongguoAccountError.invalid }
        return bytes
    }
    private func directionKey(_ response: Bool) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: key), salt: Data(id.utf8),
            info: Data((response ? "THL-HAW/ACCOUNT/v1/server" : "THL-HAW/ACCOUNT/v1/client").utf8), outputByteCount: 32)
    }
    private func aad(_ response: Bool) -> Data { Data("THL-HAW/ACCOUNT/v1/\(id)/\(response ? "response" : "request")".utf8) }
    func seal(_ payload: [String: Any], response: Bool) throws -> [String: Any] {
        guard expires > Date() else { throw HongguoAccountError.expired }
        let bytes = try JSONSerialization.data(withJSONObject: payload)
        guard bytes.count <= 68 * 1024 else { throw HongguoAccountError.invalid }
        let box = try AES.GCM.seal(bytes, using: directionKey(response), authenticating: aad(response))
        return ["v": 1, "id": id, "nonce": Self.encode(Data(box.nonce)), "cipher": Self.encode(box.ciphertext), "tag": Self.encode(box.tag)]
    }
    func open(_ envelope: [String: Any], response: Bool) throws -> [String: Any] {
        guard expires > Date(), envelope["v"] as? Int == 1, envelope["id"] as? String == id,
            Set(envelope.keys) == Set(["v", "id", "nonce", "cipher", "tag"]) else { throw HongguoAccountError.invalid }
        let nonce = try Self.decode(envelope["nonce"], max: 12), tag = try Self.decode(envelope["tag"], max: 16)
        guard nonce.count == 12, tag.count == 16 else { throw HongguoAccountError.invalid }
        let cipher = try Self.decode(envelope["cipher"], max: 68 * 1024)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: cipher, tag: tag)
        let data = try AES.GCM.open(box, using: directionKey(response), authenticating: aad(response))
        guard data.count <= 68 * 1024, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HongguoAccountError.invalid }
        return object
    }
    func qr(host: String, port: UInt16, name: String) -> String? {
        var url = URLComponents()
        url.scheme = "thlhaw"; url.host = "account-pair"
        url.queryItems = [URLQueryItem(name: "v", value: "1"), URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "host", value: host), URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "name", value: String(name.prefix(80))), URLQueryItem(name: "expires", value: String(Int(expires.timeIntervalSince1970)))]
        url.fragment = "key=" + Self.encode(key)
        return url.string
    }
}
