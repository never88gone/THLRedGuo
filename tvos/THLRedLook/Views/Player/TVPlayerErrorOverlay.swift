import SwiftUI

struct TVPlayerErrorOverlay: View {
    let errorMessage: String
    let isFeedMode: Bool
    let canGoNextDrama: Bool
    let onBack: () -> Void
    let onRetry: () -> Void
    let onNextDrama: (() -> Void)?

    @FocusState private var errorFocusTarget: PlayerErrorFocusTarget?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            Text("播放失败：\(errorMessage)")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .lineSpacing(6)
                .padding(.horizontal, 24)

            HStack(spacing: 24) {
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.backward.circle.fill")
                        Text(isFeedMode ? "返回推荐" : "返回选集")
                    }
                    .font(.system(size: 18, weight: .bold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(errorFocusTarget == .backToEpisodes ? TVTheme.primaryHover : TVTheme.primary)
                    )
                    .foregroundColor(.white)
                    .tvFocusBorder(isFocused: errorFocusTarget == .backToEpisodes, cornerRadius: 14)
                }
                .buttonStyle(TVZeroHighlightButtonStyle())
                .focused($errorFocusTarget, equals: .backToEpisodes)

                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("重试")
                    }
                    .font(.system(size: 18, weight: .bold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(errorFocusTarget == .retry ? TVTheme.surfaceFocused : TVTheme.surfaceCard)
                    )
                    .foregroundColor(.white)
                    .tvFocusBorder(isFocused: errorFocusTarget == .retry, cornerRadius: 14)
                }
                .buttonStyle(TVZeroHighlightButtonStyle())
                .focused($errorFocusTarget, equals: .retry)

                if canGoNextDrama, let onNextDrama {
                    Button("下一部") { onNextDrama() }
                        .accessibilityIdentifier("player.errorNextDrama")
                }
            }
        }
        .padding(40)
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.8), radius: 30)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                errorFocusTarget = .backToEpisodes
            }
        }
    }
}
