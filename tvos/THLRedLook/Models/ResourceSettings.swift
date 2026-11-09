import Foundation

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
