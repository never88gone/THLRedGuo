import Foundation

struct HongguoAccountRecord: Codable, Sendable {
    let id: String
    let nickname: String
    var cookies: [HongguoCookie]
    var device: [String: String]? = nil
    var avatar: String? = nil
    var hasSession: Bool { cookies.contains { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) } }
}
