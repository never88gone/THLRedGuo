import SwiftUI

struct DramaCardLabel: View {
    let drama: Drama
    let externalFocused: Bool
    let watchProgress: Double?
    let progressText: String?
    let forceFocused: Bool

    @Environment(\.isFocused) private var envIsFocused

    var effectiveFocused: Bool {
        externalFocused || forceFocused || envIsFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // 高质感海报渲染
                PosterArtworkView(drama: drama, cornerRadius: 12)

                // VIP 徽章
                if drama.isVIP {
                    Text("VIP")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }

                // 底部集数/热度角标
                VStack {
                    Spacer()
                    HStack {
                        Text(drama.displaySubtitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Spacer()
                    }
                    .padding(8)
                }

                // 进度条指示
                if let progress = watchProgress, progress > 0 {
                    VStack {
                        Spacer()
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: TVTheme.primary))
                            .frame(height: 5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 剧集标题与进度文字（完整包裹在卡片边框内）
            VStack(alignment: .leading, spacing: 4) {
                Text(drama.title)
                    .font(.system(size: 16, weight: effectiveFocused ? .bold : .medium))
                    .foregroundColor(effectiveFocused ? .white : Color.white.opacity(0.85))
                    .lineLimit(1)
                    .shadow(color: effectiveFocused ? Color.red.opacity(0.4) : Color.clear, radius: 4)

                if let pt = progressText {
                    Text(pt)
                        .font(.caption2)
                        .foregroundColor(effectiveFocused ? TVTheme.primary.opacity(0.9) : TVTheme.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveFocused ? TVColors.cardOverlayBg.opacity(0.85) : Color.clear)
        )
        .tvFocusBorder(isFocused: effectiveFocused, cornerRadius: 16, scale: TVTheme.cardScale)
    }
}
