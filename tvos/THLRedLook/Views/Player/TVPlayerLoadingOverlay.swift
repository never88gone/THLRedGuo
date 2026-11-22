import SwiftUI

struct TVPlayerLoadingOverlay: View {
    let isLoading: Bool
    let isBuffering: Bool
    let isSwitchingFeed: Bool
    let isActuallyPlaying: Bool
    let isSeamlessTransitioning: Bool

    var body: some View {
        let shouldShowLoading = isLoading && !isActuallyPlaying
        let shouldShowBuffering = isBuffering && !isActuallyPlaying
        let shouldShowSwitching = isSwitchingFeed && !isActuallyPlaying

        if (shouldShowLoading || shouldShowBuffering || shouldShowSwitching) && !isSeamlessTransitioning {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.8)
                Text(shouldShowSwitching ? "正在切换推荐…" : shouldShowLoading ? "正在准备视频流..." : "正在缓冲...")
                    .font(.headline)
                    .foregroundColor(TVColors.white)
            }
            .padding(32)
            .background(TVColors.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    TVPlayerLoadingOverlay(
        isLoading: true,
        isBuffering: false,
        isSwitchingFeed: false,
        isActuallyPlaying: false,
        isSeamlessTransitioning: false
    )
    .background(TVColors.black)
}
