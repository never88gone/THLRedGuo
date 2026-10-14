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

public struct LanIncomingPlayback: Hashable, Codable {
    public let drama: Drama
    public let episodeIndex: Int
    public let position: Double
    public let senderName: String

    public init(drama: Drama, episodeIndex: Int, position: Double, senderName: String) {
        self.drama = drama
        self.episodeIndex = episodeIndex
        self.position = position
        self.senderName = senderName
    }
}

public struct ResourceSettings: Hashable, Codable {
    public var proxyMode: String // "auto", "direct", "manual"
    public var proxyUrl: String
    public var catalogConcurrency: Int
    public var catalogIntervalMs: Int
    public var keepScreenOn: Bool

    public init(
        proxyMode: String = "direct",
        proxyUrl: String = "",
        catalogConcurrency: Int = 3,
        catalogIntervalMs: Int = 250,
        keepScreenOn: Bool = true
    ) {
        self.proxyMode = proxyMode
        self.proxyUrl = proxyUrl
        self.catalogConcurrency = catalogConcurrency
        self.catalogIntervalMs = catalogIntervalMs
        self.keepScreenOn = keepScreenOn
    }
}
