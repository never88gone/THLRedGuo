import SwiftUI

public struct TVQuickSeekIndicatorView: View {
    public let targetTime: Double
    public let duration: Double
    public let delta: Double
    public let isScrubbing: Bool

    public init(
        targetTime: Double,
        duration: Double,
        delta: Double,
        isScrubbing: Bool
    ) {
        self.targetTime = targetTime
        self.duration = duration
        self.delta = delta
        self.isScrubbing = isScrubbing
    }

    public var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: delta >= 0 ? "goforward" : "gobackward")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(TVTheme.primary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formatTime(targetTime))
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("/ \(formatTime(duration))")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(TVTheme.textSecondary)
                    }

                    Text(delta >= 0 ? (isScrubbing ? "滑动快进 +\(Int(delta))s" : "快进 +\(Int(delta))s") : (isScrubbing ? "滑动快退 \(Int(delta))s" : "快退 \(Int(delta))s"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(TVTheme.primary)
                }
            }

            // 微缩高精进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)

                    let progress = duration > 0 ? max(0, min(targetTime / duration, 1.0)) : 0
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [TVTheme.primary, TVTheme.primaryHover],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * CGFloat(progress)), height: 6)
                }
            }
            .frame(width: 300, height: 6)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 22)
        .background(
            Material.regular
        )
        .background(
            TVColors.playerOverlayBg.opacity(0.92)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.85), radius: 28, x: 0, y: 10)
        .accessibilityIdentifier("player.quickSeek")
    }

    private func formatTime(_ sec: Double) -> String {
        guard !sec.isNaN && sec >= 0 else { return "00:00" }
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
