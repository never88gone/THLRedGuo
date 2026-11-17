import Foundation

struct HongguoCookie: Codable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?

    static func isValidDomain(_ domain: String) -> Bool {
        if domain.isEmpty { return true }
        let clean = domain.hasPrefix(".") ? String(domain.dropFirst()).lowercased() : domain.lowercased()
        return clean == "hongguoduanju.com" || clean.hasSuffix(".hongguoduanju.com") ||
               clean == "snssdk.com" || clean.hasSuffix(".snssdk.com") ||
               clean == "fqnovel.com" || clean.hasSuffix(".fqnovel.com")
    }

    var valid: Bool {
        Self.isValidDomain(domain) && (expires == nil || expires! > Date())
    }
}
