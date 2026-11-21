import Foundation
import Security

final class HongguoAccountVault: @unchecked Sendable {
    static let shared = HongguoAccountVault()
    private let lock = NSLock()
    private var value: HongguoAccountRecord?
    private var generation: UInt64 = 0
    private let service = "THLRedLook.hongguo.account"
    static let credentialNames: Set<String> = ["sessionid", "sessionid_ss", "sid_guard", "sid_tt", "uid_tt", "uid_tt_ss", "sid_ucp_v1", "ssid_ucp_v1", "passport_auth_status", "passport_auth_status_ss"]

    init() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            value = try? JSONDecoder().decode(HongguoAccountRecord.self, from: data)
        }
    }

    var snapshot: (record: HongguoAccountRecord?, revision: UInt64) {
        lock.withLock { (value, generation) }
    }

    static func businessURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.port == nil else { return false }
        let host = url.host ?? ""
        return (host == "reading.snssdk.com" || host == "api5-normal.fqnovel.com" || host.range(of: "^api[0-9]+-normal-sinfonline[a-z]\\.fqnovel\\.com$", options: .regularExpression) != nil) &&
            (url.path.hasPrefix("/reading/") || url.path.hasPrefix("/novel/"))
    }

    func header(for url: URL, record: HongguoAccountRecord? = nil) -> String {
        guard Self.businessURL(url) else { return "" }
        let account = record ?? snapshot.record
        guard account?.hasSession == true else { return "" }
        return account?.cookies.filter { $0.valid && Self.credentialNames.contains($0.name) }
            .map { "\($0.name)=\($0.value)" }.joined(separator: "; ") ?? ""
    }

    func save(_ record: HongguoAccountRecord, expectedRevision: UInt64) throws {
        try lock.withLock {
            guard expectedRevision == generation else { throw HongguoAccountError.cancelled }
            let data = try JSONEncoder().encode(record)
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "default"]
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw HongguoAccountError.storage }
            } else if status != errSecSuccess {
                throw HongguoAccountError.storage
            }
            value = record
            generation += 1
        }
    }

    func logout() throws {
        try lock.withLock {
            value = nil
            generation += 1
            let status = SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "default"
            ] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw HongguoAccountError.storage }
        }
    }
}
