import Foundation

public struct TVDanmakuStyle: Codable, Equatable {
    public var fontSize: CGFloat = 26.0
    public var opacity: Double = 1.0
    public var laneCount: Int = 8

    public init(fontSize: CGFloat = 26.0, opacity: Double = 1.0, laneCount: Int = 8) {
        self.fontSize = fontSize
        self.opacity = opacity
        self.laneCount = laneCount
    }
}
