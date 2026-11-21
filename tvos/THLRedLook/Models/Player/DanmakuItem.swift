import Foundation

public struct DanmakuItem: Identifiable, Hashable, Codable {
    public let id: String
    public let text: String
    public let timeMs: Int64
    public let color: String

    public init(id: String = UUID().uuidString, text: String, timeMs: Int64, color: String = "#FFFFFF") {
        self.id = id
        self.text = text
        self.timeMs = timeMs
        self.color = color
    }
}
