import SwiftUI

/// 播放器弹幕控制面板（对应 ATV-Bilibili-demo 弹幕设置）
public struct TVPlayerDanmakuPanel: View {
    @ObservedObject public var viewModel: PlayerViewModel
    @FocusState private var focusedDanmakuItem: String?

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                // 1. 弹幕总开关
                Button(action: {
                    viewModel.toggleDanmaku()
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: viewModel.danmakuEnabled ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(viewModel.danmakuEnabled ? TVColors.activeRed : TVColors.white)
                        Text(viewModel.danmakuEnabled ? "弹幕已开启" : "弹幕已关闭")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(TVColors.white)
                    }
                    .frame(width: 130, height: 86)
                    .background(viewModel.danmakuEnabled ? TVColors.surfaceFocused : TVColors.panelCardBg)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                focusedDanmakuItem == "danmaku_toggle"
                                    ? TVColors.liquidGlassActiveBorder
                                    : TVColors.liquidGlassBorder,
                                lineWidth: focusedDanmakuItem == "danmaku_toggle" ? 2.5 : 1
                            )
                    )
                    .scaleEffect(focusedDanmakuItem == "danmaku_toggle" ? 1.08 : 1.0)
                }
                .buttonStyle(.card)
                .focused($focusedDanmakuItem, equals: "danmaku_toggle")

                // 2. 弹幕轨道数量 (相当于显示区域)
                VStack(alignment: .leading, spacing: 8) {
                    Text("弹幕轨道")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(TVColors.textSecondary)
                        .padding(.leading, 4)

                    HStack(spacing: 10) {
                        laneButton(title: "4条", count: 4)
                        laneButton(title: "8条", count: 8)
                        laneButton(title: "12条", count: 12)
                    }
                }
                .padding(14)
                .background(TVColors.surfaceCard)
                .cornerRadius(18)

                // 3. 弹幕不透明度
                VStack(alignment: .leading, spacing: 8) {
                    Text("不透明度")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(TVColors.textSecondary)
                        .padding(.leading, 4)

                    HStack(spacing: 10) {
                        opacityButton(title: "100%", value: 1.0)
                        opacityButton(title: "75%", value: 0.75)
                        opacityButton(title: "50%", value: 0.5)
                    }
                }
                .padding(14)
                .background(TVColors.surfaceCard)
                .cornerRadius(18)

                // 4. 弹幕字体大小
                VStack(alignment: .leading, spacing: 8) {
                    Text("字号大小")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(TVColors.textSecondary)
                        .padding(.leading, 4)

                    HStack(spacing: 10) {
                        fontButton(title: "标准", size: 26.0)
                        fontButton(title: "大号", size: 32.0)
                        fontButton(title: "精简", size: 22.0)
                    }
                }
                .padding(14)
                .background(TVColors.surfaceCard)
                .cornerRadius(18)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 12)
        }
        .frame(height: 140)
    }

    private func laneButton(title: String, count: Int) -> some View {
        let isSelected = viewModel.danmakuStyle.laneCount == count
        return Button(action: {
            var updated = viewModel.danmakuStyle
            updated.laneCount = count
            viewModel.danmakuStyle = updated
        }) {
            Text(title)
                .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                .foregroundColor(TVColors.white)
                .frame(width: 80, height: 54)
                .background(isSelected ? TVColors.activeRed : TVColors.panelCardBg)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            focusedDanmakuItem == "lane_\(count)"
                                ? TVColors.liquidGlassActiveBorder
                                : TVColors.liquidGlassBorder,
                            lineWidth: focusedDanmakuItem == "lane_\(count)" ? 2.5 : 1
                        )
                )
                .scaleEffect(focusedDanmakuItem == "lane_\(count)" ? 1.08 : 1.0)
        }
        .buttonStyle(.card)
        .focused($focusedDanmakuItem, equals: "lane_\(count)")
    }

    private func opacityButton(title: String, value: Double) -> some View {
        let isSelected = abs(viewModel.danmakuStyle.opacity - value) < 0.05
        return Button(action: {
            var updated = viewModel.danmakuStyle
            updated.opacity = value
            viewModel.danmakuStyle = updated
        }) {
            Text(title)
                .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                .foregroundColor(TVColors.white)
                .frame(width: 80, height: 54)
                .background(isSelected ? TVColors.activeRed : TVColors.panelCardBg)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            focusedDanmakuItem == "opacity_\(value)"
                                ? TVColors.liquidGlassActiveBorder
                                : TVColors.liquidGlassBorder,
                            lineWidth: focusedDanmakuItem == "opacity_\(value)" ? 2.5 : 1
                        )
                )
                .scaleEffect(focusedDanmakuItem == "opacity_\(value)" ? 1.08 : 1.0)
        }
        .buttonStyle(.card)
        .focused($focusedDanmakuItem, equals: "opacity_\(value)")
    }

    private func fontButton(title: String, size: CGFloat) -> some View {
        let isSelected = abs(viewModel.danmakuStyle.fontSize - size) < 0.5
        return Button(action: {
            var updated = viewModel.danmakuStyle
            updated.fontSize = size
            viewModel.danmakuStyle = updated
        }) {
            Text(title)
                .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                .foregroundColor(TVColors.white)
                .frame(width: 80, height: 54)
                .background(isSelected ? TVColors.activeRed : TVColors.panelCardBg)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            focusedDanmakuItem == "font_\(Int(size))"
                                ? TVColors.liquidGlassActiveBorder
                                : TVColors.liquidGlassBorder,
                            lineWidth: focusedDanmakuItem == "font_\(Int(size))" ? 2.5 : 1
                        )
                )
                .scaleEffect(focusedDanmakuItem == "font_\(Int(size))" ? 1.08 : 1.0)
        }
        .buttonStyle(.card)
        .focused($focusedDanmakuItem, equals: "font_\(Int(size))")
    }
}

// MARK: - 预览
#Preview("TVPlayerDanmakuPanel") {
    struct PreviewContainer: View {
        var body: some View {
            let drama = Drama(id: "preview_1", title: "逆天龙皇", cover: "", episodes: 80)
            let vm = PlayerViewModel(drama: drama, allEpisodes: [])
            TVPlayerDanmakuPanel(viewModel: vm)
                .padding(.vertical, 40)
                .background(TVColors.transportBarBg)
        }
    }
    return PreviewContainer()
}
