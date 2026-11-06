import SwiftUI

// MARK: - 播放倍速调节大屏抽屉
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

    public init(viewModel: PlayerViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }

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
                            .foregroundColor(TVColors.textPrimary)
                        Text("选择当前视频的播放速率")
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
                                    .foregroundColor(TVColors.textPrimary)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(TVColors.textPrimary)
                                    .opacity(isSelected ? 1.0 : 0.0)
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isSelected
                                          ? (isFocused ? TVColors.primaryHover : TVColors.primary)
                                          : (isFocused ? TVColors.surfaceFocused : TVColors.surfaceCard))
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
            .background(TVColors.drawerBackground)
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

#Preview("TVSpeedSelectionDrawer") {
    TVSpeedSelectionDrawer(
        viewModel: PlayerViewModel(drama: Drama(id: "1", title: "测试"), allEpisodes: [Episode(id: "1", title: "第 1 集", number: 1)]),
        isPresented: .constant(true)
    )
}
