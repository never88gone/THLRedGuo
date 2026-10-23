import SwiftUI
import UIKit

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

            let textWidth = (cleanText as NSString).size(withAttributes: [.font: font]).width + 36

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

public struct TVDanmakuView: View {
    public let danmakus: [DanmakuItem]
    public let position: Double
    public let anchor: Date
    public let rate: Double
    public let moving: Bool
    public var style: TVDanmakuStyle = TVDanmakuStyle()

    @State private var coordinator = TVDanmakuTrackCoordinator()

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
            .font(.system(size: style.fontSize, weight: .heavy, design: .rounded))
            .foregroundColor(.white.opacity(style.opacity))
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
            .shadow(color: .black.opacity(style.opacity * 0.8), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.32 * style.opacity))
            )
            .fixedSize()
            .frame(width: item.width)
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
        .onExitCommand {
            isPresented = false
        }
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

public struct TVDanmakuSettingsDrawer: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isPresented: Bool

    @FocusState private var focusedButton: String?

    public var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("弹幕设置")
                            .font(.title2)
                            .bold()
                            .foregroundColor(TVTheme.textPrimary)
                        Text("个性化调整弹幕大小、透明度与展示区域")
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
                .padding(.bottom, 8)

                Divider()
                    .background(Color.white.opacity(0.12))

                // 1. 弹幕总开关
                VStack(alignment: .leading, spacing: 12) {
                    Text("弹幕显示")
                        .font(.headline)
                        .foregroundColor(TVTheme.textSecondary)
                    HStack(spacing: 16) {
                        settingOptionButton(
                            title: "开启",
                            isSelected: viewModel.danmakuEnabled,
                            id: "danmaku.switch.on",
                            down: "danmaku.font.small",
                            right: "danmaku.switch.off"
                        ) {
                            if !viewModel.danmakuEnabled { viewModel.toggleDanmaku() }
                        }
                        settingOptionButton(
                            title: "关闭",
                            isSelected: !viewModel.danmakuEnabled,
                            id: "danmaku.switch.off",
                            down: "danmaku.font.large",
                            left: "danmaku.switch.on"
                        ) {
                            if viewModel.danmakuEnabled { viewModel.toggleDanmaku() }
                        }
                    }
                }

                // 2. 字体大小
                VStack(alignment: .leading, spacing: 12) {
                    Text("字体大小")
                        .font(.headline)
                        .foregroundColor(TVTheme.textSecondary)
                    HStack(spacing: 16) {
                        settingOptionButton(
                            title: "小 (20pt)",
                            isSelected: viewModel.danmakuStyle.fontSize == 20.0,
                            id: "danmaku.font.small",
                            up: "danmaku.switch.on",
                            down: "danmaku.opacity.50",
                            right: "danmaku.font.standard"
                        ) {
                            viewModel.setDanmakuFontSize(20.0)
                        }
                        settingOptionButton(
                            title: "标准 (26pt)",
                            isSelected: viewModel.danmakuStyle.fontSize == 26.0,
                            id: "danmaku.font.standard",
                            up: "danmaku.switch.on",
                            down: "danmaku.opacity.75",
                            left: "danmaku.font.small",
                            right: "danmaku.font.large"
                        ) {
                            viewModel.setDanmakuFontSize(26.0)
                        }
                        settingOptionButton(
                            title: "大 (34pt)",
                            isSelected: viewModel.danmakuStyle.fontSize == 34.0,
                            id: "danmaku.font.large",
                            up: "danmaku.switch.off",
                            down: "danmaku.opacity.100",
                            left: "danmaku.font.standard"
                        ) {
                            viewModel.setDanmakuFontSize(34.0)
                        }
                    }
                }

                // 3. 不透明度
                VStack(alignment: .leading, spacing: 12) {
                    Text("不透明度")
                        .font(.headline)
                        .foregroundColor(TVTheme.textSecondary)
                    HStack(spacing: 16) {
                        settingOptionButton(
                            title: "50%",
                            isSelected: viewModel.danmakuStyle.opacity == 0.5,
                            id: "danmaku.opacity.50",
                            up: "danmaku.font.small",
                            down: "danmaku.area.half",
                            right: "danmaku.opacity.75"
                        ) {
                            viewModel.setDanmakuOpacity(0.5)
                        }
                        settingOptionButton(
                            title: "75%",
                            isSelected: viewModel.danmakuStyle.opacity == 0.75,
                            id: "danmaku.opacity.75",
                            up: "danmaku.font.standard",
                            down: "danmaku.area.half",
                            left: "danmaku.opacity.50",
                            right: "danmaku.opacity.100"
                        ) {
                            viewModel.setDanmakuOpacity(0.75)
                        }
                        settingOptionButton(
                            title: "100%",
                            isSelected: viewModel.danmakuStyle.opacity == 1.0,
                            id: "danmaku.opacity.100",
                            up: "danmaku.font.large",
                            down: "danmaku.area.full",
                            left: "danmaku.opacity.75"
                        ) {
                            viewModel.setDanmakuOpacity(1.0)
                        }
                    }
                }

                // 4. 显示区域
                VStack(alignment: .leading, spacing: 12) {
                    Text("显示区域")
                        .font(.headline)
                        .foregroundColor(TVTheme.textSecondary)
                    HStack(spacing: 16) {
                        settingOptionButton(
                            title: "半屏 (4轨)",
                            isSelected: viewModel.danmakuStyle.laneCount == 4,
                            id: "danmaku.area.half",
                            up: "danmaku.opacity.50",
                            down: "danmaku.close",
                            right: "danmaku.area.full"
                        ) {
                            viewModel.setDanmakuLaneCount(4)
                        }
                        settingOptionButton(
                            title: "全屏 (8轨)",
                            isSelected: viewModel.danmakuStyle.laneCount == 8,
                            id: "danmaku.area.full",
                            up: "danmaku.opacity.100",
                            down: "danmaku.close",
                            left: "danmaku.area.half"
                        ) {
                            viewModel.setDanmakuLaneCount(8)
                        }
                    }
                }

                Spacer()

                Button(action: {
                    isPresented = false
                }) {
                    Text("完成设置")
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(focusedButton == "danmaku.close" ? TVTheme.primaryHover : TVTheme.primary)
                        )
                        .foregroundColor(.white)
                        .tvFocusBorder(isFocused: focusedButton == "danmaku.close", cornerRadius: 14)
                }
                .buttonStyle(TVZeroHighlightButtonStyle())
                .focused($focusedButton, equals: "danmaku.close")
                .accessibilityIdentifier("danmaku.close")
                .focusEffectDisabled()
                .onMoveCommand { dir in
                    if dir == .up { focusedButton = "danmaku.area.half" }
                }
            }
            .padding(40)
            .frame(width: 720)
            .frame(maxHeight: .infinity)
            .background(
                Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.96)
            )
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onExitCommand {
            isPresented = false
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedButton = viewModel.danmakuEnabled ? "danmaku.switch.on" : "danmaku.switch.off"
            }
        }
    }

    @ViewBuilder
    private func settingOptionButton(
        title: String,
        isSelected: Bool,
        id: String,
        up: String? = nil,
        down: String? = nil,
        left: String? = nil,
        right: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = (focusedButton == id)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .opacity(isSelected ? 1.0 : 0.0)
                Text(title)
                    .font(.system(size: 18, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                          ? (isFocused ? TVTheme.primaryHover : TVTheme.primary)
                          : (isFocused ? TVTheme.surfaceFocused : TVTheme.surfaceCard))
            )
            .foregroundColor(TVTheme.textPrimary)
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 12)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($focusedButton, equals: id)
        .accessibilityIdentifier(id)
        .focusEffectDisabled()
        .onMoveCommand { dir in
            switch dir {
            case .up:
                if let up { focusedButton = up }
            case .down:
                if let down { focusedButton = down }
            case .left:
                if let left { focusedButton = left }
            case .right:
                if let right { focusedButton = right }
            default: break
            }
        }
    }
}

public struct TVSpeedSelectionDrawer: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isPresented: Bool

    @FocusState private var focusedSpeed: Float?

    private let speedOptions: [(label: String, rate: Float, id: String)] = [
        ("0.75x", 0.75, "player.speed.0.75"),
        ("1.0x (正常)", 1.0, "player.speed.1.0"),
        ("1.25x", 1.25, "player.speed.1.25"),
        ("1.5x", 1.5, "player.speed.1.5"),
        ("2.0x", 2.0, "player.speed.2.0")
    ]

    public var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("播放倍速")
                            .font(.title2)
                            .bold()
                            .foregroundColor(TVTheme.textPrimary)
                        Text("选择当前视频的播放速率")
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
                .padding(.bottom, 8)

                Divider()
                    .background(Color.white.opacity(0.12))

                VStack(spacing: 16) {
                    ForEach(speedOptions, id: \.rate) { opt in
                        let isSelected = abs(viewModel.playbackRate - opt.rate) < 0.05
                        let isFocused = (focusedSpeed == opt.rate)

                        Button(action: {
                            NSLog("🎬 [SpeedSheet] 选择倍速: %.2fx", opt.rate)
                            viewModel.setRate(opt.rate)
                            viewModel.showToast("已切换至 \(opt.label) 倍速")
                            isPresented = false
                        }) {
                            HStack {
                                Text(opt.label)
                                    .font(.system(size: 22, weight: isSelected ? .black : .bold))
                                    .foregroundColor(TVTheme.textPrimary)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(TVTheme.textPrimary)
                                    .opacity(isSelected ? 1.0 : 0.0)
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isSelected
                                          ? (isFocused ? TVTheme.primaryHover : TVTheme.primary)
                                          : (isFocused ? TVTheme.surfaceFocused : TVTheme.surfaceCard))
                            )
                            .tvFocusBorder(isFocused: isFocused, cornerRadius: 14)
                        }
                        .buttonStyle(TVZeroHighlightButtonStyle())
                        .focused($focusedSpeed, equals: opt.rate)
                        .accessibilityIdentifier(opt.id)
                        .focusEffectDisabled()
                        .onMoveCommand { dir in
                            guard let idx = speedOptions.firstIndex(where: { abs($0.rate - opt.rate) < 0.05 }) else { return }
                            if dir == .up && idx > 0 {
                                focusedSpeed = speedOptions[idx - 1].rate
                            } else if dir == .down && idx < speedOptions.count - 1 {
                                focusedSpeed = speedOptions[idx + 1].rate
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(40)
            .frame(width: 640)
            .frame(maxHeight: .infinity)
            .background(
                Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.96)
            )
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onExitCommand {
            isPresented = false
        }
        .onAppear {
            let currentRate = viewModel.playbackRate
            let matched = speedOptions.first { abs($0.rate - currentRate) < 0.05 }?.rate ?? 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedSpeed = matched
            }
        }
    }
}
