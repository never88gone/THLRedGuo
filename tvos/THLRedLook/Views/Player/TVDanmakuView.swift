import SwiftUI
import UIKit

public struct TVPlannedDanmaku: Identifiable {
    public let id: String
    public let text: String
    public let time: Double
    public let duration: Double
    public let lane: Int
    public let width: CGFloat
}

public enum TVDanmakuPlanner {
    public static func calculateDuration(for id: String, text: String) -> Double {
        let hash = Double(UInt(bitPattern: id.hashValue) % 1000) / 1000.0
        let variance = (hash - 0.5) * 3.1
        return max(6.5, min(9.6, 8.0 + variance))
    }

    public static func plan(danmakus: [DanmakuItem], screenWidth: CGFloat, laneCount: Int = 8) -> [TVPlannedDanmaku] {
        guard screenWidth > 0, !danmakus.isEmpty else { return [] }
        let lanesTotal = max(1, min(10, laneCount))
        var lanes = Array<TVPlannedDanmaku?>(repeating: nil, count: lanesTotal)
        let sorted = danmakus.sorted { $0.timeMs < $1.timeMs }
        var seen = Set<String>()
        var planned = [TVPlannedDanmaku]()
        let font = UIFont.boldSystemFont(ofSize: 26)

        for item in sorted {
            let cleanText = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty, item.timeMs >= 0, seen.insert(item.id).inserted else {
                continue
            }

            let time = Double(item.timeMs) / 1000.0
            let width = (cleanText as NSString).size(withAttributes: [.font: font]).width + 28
            let duration = calculateDuration(for: item.id, text: cleanText)

            var bestLane = -1
            var maxSafetyMargin: CGFloat = -1

            for l in 0..<lanesTotal {
                guard let prev = lanes[l] else {
                    bestLane = l
                    break
                }

                let gap = time - prev.time
                if gap >= prev.duration {
                    bestLane = l
                    break
                }

                // 条件 1: 入场碰撞检查（当前弹幕入场时，前弹幕尾部已完全进入且拉开至少 32pt 间隙）
                let prevSpeed = (screenWidth + prev.width) / prev.duration
                let prevMoved = prevSpeed * gap
                let entryClearance = prevMoved - prev.width
                if entryClearance < 32 {
                    continue
                }

                // 条件 2: 出场追尾检查（在前弹幕离开屏幕左侧时，当前弹幕头部不能追上前弹幕尾部）
                let currSpeed = (screenWidth + width) / duration
                let remaining = prev.duration - gap
                let currMoved = currSpeed * remaining
                let exitClearance = screenWidth - currMoved
                if exitClearance < 32 {
                    continue
                }

                let safety = min(entryClearance, exitClearance)
                if safety > maxSafetyMargin {
                    maxSafetyMargin = safety
                    bestLane = l
                }
            }

            if bestLane >= 0 {
                let flight = TVPlannedDanmaku(
                    id: item.id,
                    text: cleanText,
                    time: time,
                    duration: duration,
                    lane: bestLane,
                    width: width
                )
                lanes[bestLane] = flight
                planned.append(flight)
            }
        }

        return planned
    }
}

public struct TVDanmakuView: View {
    public let danmakus: [DanmakuItem]
    public let position: Double
    public let anchor: Date
    public let rate: Double
    public let moving: Bool

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width > 0 ? proxy.size.width : 1920
            let planned = TVDanmakuPlanner.plan(danmakus: danmakus, screenWidth: w, laneCount: 8)

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                let time = position + (moving ? min(0.75, max(0, timeline.date.timeIntervalSince(anchor))) * rate : 0)
                ZStack(alignment: .topLeading) {
                    ForEach(planned) { item in
                        let age = time - item.time
                        if age >= 0 && age < item.duration {
                            let progress = age / item.duration
                            Text(item.text)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 2, x: 1, y: 1)
                                .fixedSize()
                                .frame(width: item.width)
                                .position(
                                    x: w + item.width / 2 - (w + item.width) * progress,
                                    y: CGFloat(item.lane) * 54 + 60
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
}

public struct TVEpisodeDrawer: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isPresented: Bool

    @FocusState private var focusedEpisode: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 5)

    public var body: some View {
        ZStack(alignment: .trailing) {
            // 全屏一体化深色蒙层（彻底覆盖包含安全区的所有视口，杜绝局部非全屏色块）
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // 右侧抽屉卡片主体
            VStack(alignment: .leading, spacing: 0) {
                // 顶部标题与提示
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("选集播放")
                            .font(.title2)
                            .bold()
                            .foregroundColor(TVTheme.textPrimary)
                        Text("共 \(viewModel.allEpisodes.count) 集 · 当前第 \(viewModel.currentEpisodeIndex) 集")
                            .font(.subheadline)
                            .foregroundColor(TVTheme.textSecondary)
                    }
                    Spacer()
                    Text("按 Menu 返回")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TVTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 20)

                Divider()
                    .background(Color.white.opacity(0.12))

                // 集数网格
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 5), spacing: 20) {
                            ForEach(viewModel.allEpisodes) { ep in
                                let isCurrent = (viewModel.currentEpisodeIndex == ep.number)
                                Button(action: {
                                    let targetNumber = ep.number
                                    NSLog("🎬 [Drawer] 点击 第%d集 按钮", targetNumber)
                                    isPresented = false
                                    Task {
                                        await viewModel.selectEpisode(number: targetNumber)
                                    }
                                }) {
                                    VStack(spacing: 6) {
                                        Text("\(ep.number)")
                                            .font(.system(size: 24, weight: isCurrent ? .black : .bold))
                                        if ep.vip {
                                            Text("VIP")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(TVTheme.vipAccent)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 76)
                                }
                                .buttonStyle(TvButtonStyle(
                                    variant: isCurrent ? .primary : .plain,
                                    cornerRadius: 14,
                                    isFocused: focusedEpisode == ep.number
                                ))
                                .focused($focusedEpisode, equals: ep.number)
                                .accessibilityIdentifier("drawer.episode.\(ep.number)")
                                .id(ep.number)
                                .padding(4)
                            }
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 48)
                        .padding(.horizontal, 28)
                    }
                    .onAppear {
                        scrollProxy.scrollTo(viewModel.currentEpisodeIndex, anchor: .center)
                    }
                }
            }
            .frame(width: 760)
            .frame(maxHeight: .infinity)
            .background(
                Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.96)
            )
            .ignoresSafeArea()
            .defaultFocus($focusedEpisode, viewModel.currentEpisodeIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            let targetEp = viewModel.currentEpisodeIndex
            NSLog("🎬 [Drawer] TVEpisodeDrawer onAppear, targetEp=%d", targetEp)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedEpisode = targetEp
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if focusedEpisode == nil {
                    focusedEpisode = targetEp
                }
            }
        }
    }
}
