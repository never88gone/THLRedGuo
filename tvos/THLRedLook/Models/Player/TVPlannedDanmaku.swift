import Foundation

// MARK: - 规划化弹幕数据结构
public struct TVPlannedDanmaku: Identifiable, Equatable {
    public let id: String
    public let text: String
    public let time: Double
    public let duration: Double
    public let lane: Int
    public let width: CGFloat

    public init(id: String, text: String, time: Double, duration: Double, lane: Int, width: CGFloat) {
        self.id = id
        self.text = text
        self.time = time
        self.duration = duration
        self.lane = lane
        self.width = width
    }
}
