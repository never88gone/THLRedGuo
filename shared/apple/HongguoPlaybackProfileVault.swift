import Foundation
import Security

enum HongguoProfileStorageError: Error, LocalizedError {
    case unavailable(OSStatus)
    case invalidProfile

    var errorDescription: String? {
        switch self {
        case .unavailable: return "无法访问本机播放配置，请解锁设备后重试"
        case .invalidProfile: return "播放配置无效，请重新导入官方 APK"
        }
    }
}

enum HongguoPlaybackProfileVault {
    private static let service = "THLRedGuo.OfficialPlaybackProfile"
    private static let account = "userImportedAPK"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    static func load() throws -> HongguoApkProfile? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw HongguoProfileStorageError.unavailable(status) }
        guard let profile = try? JSONDecoder().decode(HongguoApkProfile.self, from: data),
              profile.sdkVersion == "v04.10.03-ml-android",
              HongguoApkImporter.compatibleConfiguration(profile.configuration) else { throw HongguoProfileStorageError.invalidProfile }
        return profile
    }

    static func save(_ profile: HongguoApkProfile) throws {
        guard profile.sdkVersion == "v04.10.03-ml-android", HongguoApkImporter.compatibleConfiguration(profile.configuration) else {
            throw HongguoProfileStorageError.invalidProfile
        }
        let data = try JSONEncoder().encode(profile)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw HongguoProfileStorageError.unavailable(update) }
        var request = query
        attributes.forEach { request[$0.key] = $0.value }
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else { throw HongguoProfileStorageError.unavailable(status) }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw HongguoProfileStorageError.unavailable(status) }
    }

    static func metadata() throws -> [String: Any] {
        guard let profile = try load() else { return ["imported": false] }
        return ["imported": true, "appVersion": profile.appVersion, "sdkVersion": profile.sdkVersion,
                "importedAt": ISO8601DateFormatter().string(from: profile.importedAt), "storage": "deviceOnly"]
    }
}
