import SwiftUI
import UIKit

public struct TVDanmakuView: View {
    public let danmakus: [DanmakuItem]
    public let position: Double
    public let anchor: Date
    public let rate: Double
    public let moving: Bool
    public var style: TVDanmakuStyle = TVDanmakuStyle()

    @Environment(\.displayScale) private var displayScale
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
            let width = proxy.size.width
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !moving)) { timeline in
                let time = playbackTime(at: timeline.date)
                ZStack(alignment: .topLeading) {
                    ForEach(sprites, id: \.flight.id) { sprite in
                        let item = sprite.flight
                        let age = time - item.time
                        if age >= 0, age < item.duration {
                            let x = width + item.width / 2 - (width + item.width) * age / item.duration
                            let y = CGFloat(item.lane) * (style.fontSize * 1.85 + 10) + 54
                            sprite.image.opacity(style.opacity).position(x: x, y: y)
                        }
                    }
                }
            }
            .onAppear { refresh(width: width) }
            .onChange(of: danmakus) { _, _ in refresh(width: width) }
            .onChange(of: position) { _, _ in refresh(width: width) }
            .onChange(of: style) { _, _ in rebuild(width: width) }
            .onChange(of: width) { _, _ in rebuild(width: width) }
            .onChange(of: displayScale) { _, _ in rebuild(width: width) }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @State private var sprites: [Sprite] = []

    private struct Sprite {
        let flight: TVPlannedDanmaku
        let image: Image
    }

    func playbackTime(at date: Date) -> Double {
        position + (moving ? min(0.75, max(0, date.timeIntervalSince(anchor))) * rate : 0)
    }

    private func rebuild(width: CGFloat) {
        coordinator.reset()
        sprites = []
        refresh(width: width)
    }

    private func refresh(width: CGFloat) {
        guard !danmakus.isEmpty else {
            coordinator.reset()
            sprites = []
            return
        }
        let flights = coordinator.updateAndGetFlights(
            danmakus: danmakus, currentTime: position, screenWidth: width,
            laneCount: style.laneCount, fontSize: style.fontSize
        )
        let existing = Dictionary(uniqueKeysWithValues: sprites.map { ($0.flight.id, $0) })
        sprites = flights.map { flight in
            if let sprite = existing[flight.id], sprite.flight == flight { return sprite }
            let image = Self.renderText(flight.text, fontSize: style.fontSize, width: flight.width, scale: displayScale)
            return Sprite(flight: flight, image: Image(uiImage: image).renderingMode(.original))
        }
    }

    static func renderText(_ text: String, fontSize: CGFloat, width: CGFloat, scale: CGFloat) -> UIImage {
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        let size = CGSize(width: ceil(width), height: ceil(font.lineHeight) + 8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let origin = CGPoint(x: 8, y: 4)
            let outline = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.black])
            context.cgContext.saveGState()
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.8).cgColor)
            outline.draw(at: origin)
            context.cgContext.restoreGState()
            for offset in [CGPoint(x: 1.5, y: 0), CGPoint(x: -1.5, y: 0),
                           CGPoint(x: 0, y: 1.5), CGPoint(x: 0, y: -1.5),
                           CGPoint(x: 1.2, y: 1.2), CGPoint(x: -1.2, y: -1.2),
                           CGPoint(x: 1.2, y: -1.2), CGPoint(x: -1.2, y: 1.2)] {
                outline.draw(at: CGPoint(x: origin.x + offset.x, y: origin.y + offset.y))
            }
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.white])
                .draw(at: origin)
        }.withRenderingMode(.alwaysOriginal)
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
