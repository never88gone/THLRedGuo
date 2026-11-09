import SwiftUI

// MARK: - 极简关于信息卡片（只放图标、版本号、编译号）
public struct AboutCompactInfoCard: View {
    public let appVersion: String
    public let appBuild: String

    @FocusState private var isFocused: Bool

    public init(appVersion: String, appBuild: String) {
        self.appVersion = appVersion
        self.appBuild = appBuild
    }

    public var body: some View {
        Button(action: {}) {
            HStack(spacing: 32) {
                // 应用图标
                ZStack {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 120, height: 120)

                    Image("applogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                        .shadow(color: TVTheme.primary.opacity(0.4), radius: 16, x: 0, y: 8)
                }

                // 版本号与编译号
                VStack(alignment: .leading, spacing: 10) {
                    Text("糖葫芦Haw")
                        .font(.system(size: 38, weight: .heavy))
                        .foregroundColor(.white)

                    HStack(spacing: 20) {
                        HStack(spacing: 8) {
                            Text("版本号:")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                            Text("v\(appVersion)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 8) {
                            Text("编译号:")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                            Text(appBuild)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(TVTheme.primaryHover)
                        }
                    }
                }

                Spacer()
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                isFocused ? TVColors.aboutGradStart : TVColors.aboutGradEnd,
                                isFocused ? TVColors.aboutCardFocused : TVColors.aboutCardDefault
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.08), lineWidth: isFocused ? 2 : 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 22)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityIdentifier("settings.about.compact_info")
    }
}
