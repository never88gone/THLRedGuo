import SwiftUI
import UIKit

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

/// 弹幕轨道生命周期管理器：
/// 1. 严格锁定分配轨道：弹幕一旦被分配轨道，在飞行生命周期内 Y 轴坐标与 lane 绝不改变，彻底消灭上下跳行乱窜；
/// 2. 统一飞行航速：全屏弹幕采用恒定 8.0 秒匀速跨屏，同一车道内车距固定，消除同轨追尾碰撞穿模；
/// 3. 基于安全车距的平滑排队与轮询：空闲车道优先、繁忙车道按安全尾随间距分配；
/// 4. 支持进度条 Seek / 快进快退检测，清空陈旧轨道分配。
public final class TVDanmakuTrackCoordinator {
    private var flightsById: [String: TVPlannedDanmaku] = [:]
    private var laneTailInTimes: [Int: Double] = [:]
    private var lastObservedTime: Double = 0

    public init() {}

    public func updateAndGetFlights(
        danmakus: [DanmakuItem],
        currentTime: Double,
        screenWidth: CGFloat,
        laneCount: Int,
        fontSize: CGFloat
    ) -> [TVPlannedDanmaku] {
        guard screenWidth > 0 else { return [] }
        let lanesTotal = max(1, min(10, laneCount))
        let width = screenWidth > 0 ? screenWidth : 1920
        let standardDuration: Double = 8.0 // 恒定 8.0 秒匀速跨屏

        // 1. 若发生快进/快退/大幅跳转（跳变超过 2.5 秒，或时间倒退），清空历史缓存
        if abs(currentTime - lastObservedTime) > 2.5 || currentTime < lastObservedTime - 0.5 {
            flightsById.removeAll(keepingCapacity: true)
            laneTailInTimes.removeAll(keepingCapacity: true)
        }
        lastObservedTime = currentTime

        // 2. 清除已完全离开屏幕左侧的过期弹幕
        flightsById = flightsById.filter { _, flight in
            let age = currentTime - flight.time
            return age >= 0 && age < flight.duration + 0.3
        }

        // 3. 处理当前有效时间窗口 [0, standardDuration) 的弹幕
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        let sorted = danmakus.sorted { $0.timeMs < $1.timeMs }

        for item in sorted {
            let cleanText = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty, item.timeMs >= 0 else { continue }

            let itemTime = Double(item.timeMs) / 1000.0
            let age = currentTime - itemTime

            // 仅纳入正在屏幕上或即将入场的弹幕
            guard age >= 0 && age < standardDuration else { continue }

            // 关键：若已分配过轨道，严格锁定原轨道不变！
            if flightsById[item.id] != nil {
                continue
            }

            let textWidth = (cleanText as NSString).size(withAttributes: [.font: font]).width + 16

            // 为新入场弹幕挑选最佳轨道
            var bestLane = -1
            var minTailTime = Double.greatestFiniteMagnitude

            // 优先轮询完全空闲轨道（上一条弹幕尾部已入场且已拉开 1.2 秒车距）
            for l in 0..<lanesTotal {
                let tailTime = laneTailInTimes[l] ?? 0
                if itemTime >= tailTime + 1.2 {
                    bestLane = l
                    break
                }
            }

            // 若所有轨道都有弹幕在飞，寻找最早入场的轨道
            if bestLane < 0 {
                for l in 0..<lanesTotal {
                    let tailTime = laneTailInTimes[l] ?? 0
                    if tailTime < minTailTime {
                        minTailTime = tailTime
                        bestLane = l
                    }
                }
                // 碰撞保护：若前车尾部甚至还未进入屏幕右侧（车距为负且风险大），放弃该条以防叠字穿模
                if itemTime < (laneTailInTimes[bestLane] ?? 0) - 0.4 {
                    continue
                }
            }

            guard bestLane >= 0 && bestLane < lanesTotal else { continue }

            // 计算尾部完全进入屏幕所需时间：标准时长 * 弹幕宽度 / (屏幕宽 + 弹幕宽)
            let tailEntryDuration = standardDuration * Double(textWidth / (width + textWidth))
            laneTailInTimes[bestLane] = itemTime + tailEntryDuration

            let flight = TVPlannedDanmaku(
                id: item.id,
                text: cleanText,
                time: itemTime,
                duration: standardDuration,
                lane: bestLane,
                width: textWidth
            )
            flightsById[item.id] = flight
        }

        return Array(flightsById.values)
    }

    public func reset() {
        flightsById.removeAll()
        laneTailInTimes.removeAll()
        lastObservedTime = 0
    }
}

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
