import SwiftUI

/// 播放器设置卡片面板（对应 ATV-Bilibili-demo 播放设置）
public struct TVPlayerSettingsPanel: View {
    @ObservedObject public var viewModel: PlayerViewModel
    @FocusState private var focusedSettingItem: String?

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                // MARK: - 倍速调整群组
                VStack(alignment: .leading, spacing: 8) {
                    Text("播放倍速")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(TVColors.textSecondary)
                        .padding(.leading, 4)

                    HStack(spacing: 10) {
                        ForEach(speedOptions, id: \.self) { rate in
                            speedButton(rate: rate)
                        }
                    }
                }
                .padding(14)
                .background(TVColors.surfaceCard)
                .cornerRadius(18)

                // MARK: - 清晰度调整群组
                if !viewModel.qualityOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("画质清晰度")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(TVColors.textSecondary)
                            .padding(.leading, 4)

                        HStack(spacing: 10) {
                            ForEach(viewModel.qualityOptions, id: \.self) { q in
                                qualityButton(quality: q)
                            }
                        }
                    }
                    .padding(14)
                    .background(TVColors.surfaceCard)
                    .cornerRadius(18)
                }

                // MARK: - 画中画快捷入口
                pipButton
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 12)
        }
        .frame(height: 140)
    }

    private func speedButton(rate: Float) -> some View {
        let isSelected = abs(viewModel.playbackRate - rate) < 0.05
        return Button(action: {
            viewModel.setRate(rate)
            viewModel.showToast("已设置播放速度为 \(String(format: "%.2fx", rate))")
        }) {
            Text(String(format: "%.2fx", rate))
                .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                .foregroundColor(TVColors.white)
                .frame(width: 80, height: 54)
                .background(isSelected ? TVColors.activeRed : TVColors.panelCardBg)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            focusedSettingItem == "speed_\(rate)"
                                ? TVColors.liquidGlassActiveBorder
                                : TVColors.liquidGlassBorder,
                            lineWidth: focusedSettingItem == "speed_\(rate)" ? 2.5 : 1
                        )
                )
                .scaleEffect(focusedSettingItem == "speed_\(rate)" ? 1.08 : 1.0)
        }
        .buttonStyle(.card)
        .focused($focusedSettingItem, equals: "speed_\(rate)")
    }

    private func qualityButton(quality: Int) -> some View {
        let isSelected = viewModel.selectedQuality == quality
        return Button(action: {
            Task {
                await viewModel.changeQuality(quality)
            }
        }) {
            Text(PlaybackPlan.qualityLabel(quality))
                .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                .foregroundColor(TVColors.white)
                .frame(width: 100, height: 54)
                .background(isSelected ? TVColors.activeRed : TVColors.panelCardBg)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            focusedSettingItem == "quality_\(quality)"
                                ? TVColors.liquidGlassActiveBorder
                                : TVColors.liquidGlassBorder,
                            lineWidth: focusedSettingItem == "quality_\(quality)" ? 2.5 : 1
                        )
                )
                .scaleEffect(focusedSettingItem == "quality_\(quality)" ? 1.08 : 1.0)
        }
        .buttonStyle(.card)
        .focused($focusedSettingItem, equals: "quality_\(quality)")
    }

    private var pipButton: some View {
        Button(action: {
            viewModel.startPictureInPicture()
        }) {
            VStack(spacing: 6) {
                Image(systemName: "pip.enter")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(TVColors.white)
                Text("开启画中画")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(TVColors.white)
            }
            .frame(width: 120, height: 86)
            .background(TVColors.panelCardBg)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        focusedSettingItem == "pip"
                            ? TVColors.liquidGlassActiveBorder
                            : TVColors.liquidGlassBorder,
                        lineWidth: focusedSettingItem == "pip" ? 2.5 : 1
                    )
            )
            .scaleEffect(focusedSettingItem == "pip" ? 1.08 : 1.0)
        }
        .buttonStyle(.card)
        .focused($focusedSettingItem, equals: "pip")
    }
}

// MARK: - 预览
#Preview("TVPlayerSettingsPanel") {
    struct PreviewContainer: View {
        var body: some View {
            let drama = Drama(id: "preview_1", title: "逆天龙皇", cover: "", episodes: 80)
            let vm = PlayerViewModel(drama: drama, allEpisodes: [])
            TVPlayerSettingsPanel(viewModel: vm)
                .padding(.vertical, 40)
                .background(TVColors.transportBarBg)
        }
    }
    return PreviewContainer()
}
