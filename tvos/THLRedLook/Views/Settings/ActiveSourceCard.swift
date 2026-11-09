import SwiftUI

public struct ActiveSourceCard: View {
    public let source: SourceSite
    public var forceFocused: Bool = false
    public let action: () -> Void

    @FocusState private var isFocused: Bool

    public init(source: SourceSite, forceFocused: Bool = false, action: @escaping () -> Void) {
        self.source = source
        self.forceFocused = forceFocused
        self.action = action
    }

    public var body: some View {
        let effectiveFocused = isFocused || forceFocused
        Button(action: action) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(TVTheme.primary.opacity(0.25))
                        .frame(width: 60, height: 60)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(TVTheme.primary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text(source.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text("当前活跃源")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(TVTheme.primary)
                            .clipShape(Capsule())
                    }
                    Text(source.description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                }
                Spacer()

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(effectiveFocused ? TVColors.sourceCardFocused : TVColors.sourceCardActive)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(effectiveFocused ? Color.white : TVTheme.primary.opacity(0.45), lineWidth: effectiveFocused ? 3.0 : 1.5)
            )
            .scaleEffect(effectiveFocused ? 1.02 : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: effectiveFocused)
            .tvFocusBorder(isFocused: effectiveFocused, cornerRadius: 18)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}
