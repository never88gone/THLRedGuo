import Foundation

public enum TVDanmakuPlanner {
    public static func calculateDuration(for id: String, text: String) -> Double {
        return 8.0
    }

    public static func plan(danmakus: [DanmakuItem], screenWidth: CGFloat, laneCount: Int = 8, fontSize: CGFloat = 26.0) -> [TVPlannedDanmaku] {
        let coordinator = TVDanmakuTrackCoordinator()
        let maxTime = danmakus.map { Double($0.timeMs) / 1000.0 }.max() ?? 0
        return coordinator.updateAndGetFlights(danmakus: danmakus, currentTime: maxTime, screenWidth: screenWidth, laneCount: laneCount, fontSize: fontSize)
    }
}
