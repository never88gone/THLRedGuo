import Foundation

public struct Episode: Identifiable, Hashable, Codable {
    public let id: String
    public let title: String
    public let number: Int
    public let vip: Bool
    public let raw: Data?

    public init(id: String, title: String, number: Int, vip: Bool = false, raw: Data? = nil) {
        self.id = id
        self.title = title
        self.number = number
        self.vip = vip
        self.raw = raw
    }

    public var rawChapter: [String: Any]? {
        guard let raw else { return nil }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    public var displayTitle: String {
        title.isEmpty ? "第 \(number) 集" : title
    }
}
