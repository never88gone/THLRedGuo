import SwiftUI

// MARK: - 免责说明与合规声明卡片
public struct AboutDisclaimerCard: View {
    @FocusState private var isFocused: Bool

    public init() {}

    public var body: some View {
        Button(action: {}) {
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 26))
                    .foregroundColor(isFocused ? TVTheme.primary : .white.opacity(0.65))
                    .frame(width: 32)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("免责声明")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    Text("1. 本项目为独立 Apple tvOS 客户端系统，仅供大屏原生开发技术学习与非商业研究使用；\n2. 短剧及流媒体数据均来源于网络公开接口，开发者不搭建中转服务、不存储任何音视频内容；版权归原版权方所有；\n3. 视频解析与播放均在 Apple TV 设备本地沙箱闭环执行，零隐私数据上报，使用者需对自配内容自行承担法律责任。")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.65))
                        .lineSpacing(5)
                }
                Spacer()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isFocused ? TVColors.aboutCardFocused : TVColors.aboutCardDefault)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.06), lineWidth: 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 18)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityIdentifier("settings.about.disclaimer")
    }
}
