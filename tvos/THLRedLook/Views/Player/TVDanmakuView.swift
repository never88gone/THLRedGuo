import SwiftUI

// MARK: - 大屏弹幕渲染主视图
public struct TVDanmakuView: View {
    public let danmakus: [DanmakuItem]
    public let position: Double
    public let anchor: Date
    public let rate: Double
    public let moving: Bool
    public var style: TVDanmakuStyle = TVDanmakuStyle()

    @State private var coordinator = TVDanmakuTrackCoordinator()

    public init(
        danmakus: [DanmakuItem],
        position: Double,
        anchor: Date,
        rate: Double,
        moving: Bool,
        style: TVDanmakuStyle = TVDanmakuStyle()
    ) {
        self.danmakus = danmakus
        self.position = position
        self.anchor = anchor
        self.rate = rate
        self.moving = moving
        self.style = style
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width > 0 ? proxy.size.width : 1920

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                let time = position + (moving ? min(0.75, max(0, timeline.date.timeIntervalSince(anchor))) * rate : 0)
                let flights = coordinator.updateAndGetFlights(
                    danmakus: danmakus,
                    currentTime: time,
                    screenWidth: w,
                    laneCount: style.laneCount,
                    fontSize: style.fontSize
                )

                ZStack(alignment: .topLeading) {
                    ForEach(flights) { item in
                        let age = time - item.time
                        if age >= 0 && age < item.duration {
                            let progress = age / item.duration
                            let trackHeight = style.fontSize * 1.85 + 10
                            let yPosition = CGFloat(item.lane) * trackHeight + 54

                            danmakuItemView(item: item)
                                .position(
                                    x: w + item.width / 2 - (w + item.width) * progress,
                                    y: yPosition
                                )
                        }
                    }
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func danmakuItemView(item: TVPlannedDanmaku) -> some View {
        Text(item.text)
            .font(.system(size: style.fontSize, weight: .bold))
            .foregroundColor(TVColors.textPrimary.opacity(style.opacity))
            // 8 方向 1.5pt 高对比度深黑描边（强光、白底、复杂背景下字体轮廓极其锐利清爽）
            .shadow(color: .black.opacity(style.opacity), radius: 0, x: 1.5, y: 0)
            .shadow(color: .black.opacity(style.opacity), radius: 0, x: -1.5, y: 0)
            .shadow(color: .black.opacity(style.opacity), radius: 0, x: 0, y: 1.5)
            .shadow(color: .black.opacity(style.opacity), radius: 0, x: 0, y: -1.5)
            .shadow(color: .black.opacity(style.opacity * 0.95), radius: 0, x: 1.2, y: 1.2)
            .shadow(color: .black.opacity(style.opacity * 0.95), radius: 0, x: -1.2, y: -1.2)
            .shadow(color: .black.opacity(style.opacity * 0.95), radius: 0, x: 1.2, y: -1.2)
            .shadow(color: .black.opacity(style.opacity * 0.95), radius: 0, x: -1.2, y: 1.2)
            // 外部柔和深影增强大屏立体感
            .shadow(color: .black.opacity(style.opacity * 0.8), radius: 3, x: 0, y: 1.5)
            .fixedSize()
            .frame(width: item.width)
    }
}

#Preview("TVDanmakuView") {
    TVDanmakuView(
        danmakus: [
            DanmakuItem(id: "1", text: "前方高能！", timeMs: 1000),
            DanmakuItem(id: "2", text: "太刺激了这剧！", timeMs: 2500)
        ],
        position: 2.0,
        anchor: Date(),
        rate: 1.0,
        moving: true
    )
    .background(TVColors.background)
}
