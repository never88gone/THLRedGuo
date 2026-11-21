import SwiftUI

// MARK: - 存储信息卡片（全宽沉浸式大屏设计）
public struct StorageInfoCard: View {
    public let title: String
    public let value: String
    public let icon: String
    @FocusState private var isFocused: Bool

    public init(title: String, value: String, icon: String) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    public var body: some View {
        Button(action: {}) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(isFocused ? TVTheme.primary.opacity(0.3) : TVColors.white.opacity(0.08))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(isFocused ? TVColors.white : TVTheme.primary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TVColors.white.opacity(0.6))
                    Text(value)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(TVColors.white)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isFocused ? TVColors.storageFocusedBg : TVColors.storageDefaultBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isFocused ? TVColors.white : TVColors.white.opacity(0.08),
                        lineWidth: isFocused ? 3.0 : 1.0
                    )
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .shadow(
                color: isFocused ? TVTheme.primary.opacity(0.4) : TVColors.clear,
                radius: isFocused ? 14 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

#Preview {
    StorageInfoCard(title: "缓存大小", value: "128 MB", icon: "internaldrive")
        .padding()
        .background(TVColors.background)
}
