import SwiftUI

public struct SourceCardButton: View {
    public let source: SourceSite
    public let isSelected: Bool
    public let action: () -> Void

    @FocusState private var isFocused: Bool

    public init(source: SourceSite, isSelected: Bool, action: @escaping () -> Void) {
        self.source = source
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? TVTheme.primary.opacity(0.3) : TVColors.white.opacity(0.08))
                        .frame(width: 48, height: 48)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? TVTheme.primary : TVColors.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(TVColors.white)
                    Text(source.description)
                        .font(.caption)
                        .foregroundColor(TVColors.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? TVColors.sourceCardSelected : (isFocused ? TVColors.surfaceFocused : TVColors.sourceCardDefault))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? TVTheme.primary : TVColors.clear, lineWidth: 2)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 16)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

#Preview {
    SourceCardButton(
        source: SourceSite(
            id: "src1",
            name: "红果官方源",
            description: "内置稳定高清播放源"
        ),
        isSelected: true,
        action: {}
    )
    .padding(40)
    .background(TVColors.background)
}
