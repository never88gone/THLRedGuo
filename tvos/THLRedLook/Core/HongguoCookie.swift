import Foundation

struct HongguoCookie: Codable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    var valid: Bool { domain == "hongguoduanju.com" && (expires == nil || expires! > Date()) }
}
