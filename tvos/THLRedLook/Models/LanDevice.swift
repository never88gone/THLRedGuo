import Foundation

public struct LanDevice: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int
    public let version: String

    public init(id: String, name: String, host: String, port: Int, version: String = "0.2.51") {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.version = version
    }
}
