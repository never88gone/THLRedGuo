import SwiftUI

// MARK: - 帮助说明卡片（可聚焦，支持遥控器导航与无裁切高亮）
public struct HelpItemCard: View {
    public let title: String
    public let subtitle: String
    public let icon: String
    public var accentColor: Color = .purple
    public let identifier: String
    public let tips: [String]

    @FocusState private var isFocused: Bool

    public init(
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color = .purple,
        identifier: String,
        tips: [String]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accentColor = accentColor
        self.identifier = identifier
        self.tips = tips
    }

    public var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(accentColor.opacity(isFocused ? 0.35 : 0.18))
                            .frame(width: 56, height: 56)

                        Image(systemName: icon)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(isFocused ? .white : accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.68))
                    }

                    Spacer()
                }

                // 指南条目细则
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(isFocused ? accentColor : Color.white.opacity(0.4))
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)

                            Text(tip)
                                .font(.system(size: 15))
                                .foregroundColor(isFocused ? .white.opacity(0.95) : .white.opacity(0.72))
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(.leading, 8)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isFocused ? TVColors.helpFocusedBg : TVColors.helpDefaultBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.06), lineWidth: isFocused ? 2 : 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 20)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityIdentifier(identifier)
    }
}
