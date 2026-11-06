import SwiftUI

// MARK: - 弹幕偏好与参数调节大屏抽屉
public struct TVDanmakuSettingsDrawer: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isPresented: Bool

    @FocusState private var focusedButton: String?

    public init(viewModel: PlayerViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }

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
                            .foregroundColor(TVColors.textPrimary)
                        Text("个性化调整弹幕大小、透明度与展示区域")
                            .font(.subheadline)
                            .foregroundColor(TVColors.textSecondary)
                    }
                    Spacer()
                    Text("按 Menu 返回")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TVColors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .padding(.bottom, 8)

                Divider()
                    .background(TVColors.borderSubtle)

                // 1. 弹幕总开关
                VStack(alignment: .leading, spacing: 12) {
                    Text("弹幕显示")
                        .font(.headline)
                        .foregroundColor(TVColors.textSecondary)
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
                        .foregroundColor(TVColors.textSecondary)
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
                        .foregroundColor(TVColors.textSecondary)
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
                        .foregroundColor(TVColors.textSecondary)
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
                                .fill(focusedButton == "danmaku.close" ? TVColors.primaryHover : TVColors.primary)
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
            .background(TVColors.drawerBackground)
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
                          ? (isFocused ? TVColors.primaryHover : TVColors.primary)
                          : (isFocused ? TVColors.surfaceFocused : TVColors.surfaceCard))
            )
            .foregroundColor(TVColors.textPrimary)
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

#Preview("TVDanmakuSettingsDrawer") {
    TVDanmakuSettingsDrawer(
        viewModel: PlayerViewModel(drama: Drama(id: "1", title: "测试"), allEpisodes: [Episode(id: "1", title: "第 1 集", number: 1)]),
        isPresented: .constant(true)
    )
}
