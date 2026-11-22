import UIKit
import AVKit

/// 构建 tvOS 系统播放器 Transport Bar 菜单项构建器（对齐 ATV-Bilibili-demo）
public final class TVSystemPlayerMenuBuilder {
    public static func buildMenus(
        playbackRate: Float,
        currentQuality: Int,
        availableQualities: [Int],
        danmakuEnabled: Bool,
        danmakuLanes: Int,
        onSelectRate: @escaping (Float) -> Void,
        onSelectQuality: @escaping (Int) -> Void,
        onToggleDanmaku: @escaping (Bool) -> Void,
        onSelectDanmakuLanes: @escaping (Int) -> Void
    ) -> [UIMenuElement] {
        var menuElements: [UIMenuElement] = []

        // MARK: - 1. 播放速度设置菜单
        let speedRates: [(String, Float)] = [
            ("0.5x", 0.5),
            ("0.75x", 0.75),
            ("1.0x (正常)", 1.0),
            ("1.25x", 1.25),
            ("1.5x", 1.5),
            ("2.0x", 2.0)
        ]
        let speedActions = speedRates.map { title, rate in
            UIAction(
                title: title,
                state: abs(playbackRate - rate) < 0.05 ? .on : .off
            ) { _ in
                onSelectRate(rate)
            }
        }
        let speedMenu = UIMenu(
            title: "播放倍速",
            image: UIImage(systemName: "speedometer"),
            options: [.displayInline, .singleSelection],
            children: speedActions
        )

        // MARK: - 2. 画质清晰度设置菜单
        let qualities = availableQualities.isEmpty ? [1080, 720, 0] : availableQualities
        let qualityActions = qualities.map { q in
            let label = PlaybackPlan.qualityLabel(q)
            return UIAction(
                title: label,
                state: currentQuality == q ? .on : .off
            ) { _ in
                onSelectQuality(q)
            }
        }
        let qualityMenu = UIMenu(
            title: "画质清晰度",
            image: UIImage(systemName: "sparkles.tv"),
            options: [.displayInline, .singleSelection],
            children: qualityActions
        )

        // 整合为播放设置总菜单
        let settingsMenu = UIMenu(
            title: "播放设置",
            image: UIImage(systemName: "gearshape"),
            children: [speedMenu, qualityMenu]
        )
        menuElements.append(settingsMenu)

        // MARK: - 3. 弹幕控制菜单
        let danmakuToggleAction = UIAction(
            title: danmakuEnabled ? "弹幕已开启" : "弹幕已关闭",
            image: UIImage(systemName: danmakuEnabled ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"),
            state: danmakuEnabled ? .on : .off
        ) { action in
            let newState = !danmakuEnabled
            onToggleDanmaku(newState)
        }

        let laneActions = [4, 8, 12].map { lanes in
            UIAction(
                title: "\(lanes) 条轨道",
                state: danmakuLanes == lanes ? .on : .off
            ) { _ in
                onSelectDanmakuLanes(lanes)
            }
        }
        let lanesMenu = UIMenu(
            title: "弹幕轨道数量",
            options: [.displayInline, .singleSelection],
            children: laneActions
        )

        let danmakuMenu = UIMenu(
            title: "弹幕",
            image: UIImage(systemName: "bubble.left.and.bubble.right"),
            children: [danmakuToggleAction, lanesMenu]
        )
        menuElements.append(danmakuMenu)

        return menuElements
    }
}
