import SwiftUI

public struct TVLoginQRCodeCard: View {
    public let qrImage: UIImage?
    public let isSuccess: Bool
    public let selectedMode: TVLoginMode
    public let isBusy: Bool
    public let statusMessage: String
    public let remainingSeconds: Int
    public let hasQrURL: Bool

    public init(
        qrImage: UIImage?,
        isSuccess: Bool,
        selectedMode: TVLoginMode,
        isBusy: Bool,
        statusMessage: String,
        remainingSeconds: Int,
        hasQrURL: Bool
    ) {
        self.qrImage = qrImage
        self.isSuccess = isSuccess
        self.selectedMode = selectedMode
        self.isBusy = isBusy
        self.statusMessage = statusMessage
        self.remainingSeconds = remainingSeconds
        self.hasQrURL = hasQrURL
    }

    public var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .frame(width: 380, height: 380)
                    .shadow(color: TVColors.focusedShadowColor, radius: 30, x: 0, y: 12)

                if let qr = qrImage, !isSuccess {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .frame(width: 380, height: 380)
                        .accessibilityLabel("登录二维码")
                } else if isSuccess {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 96))
                            .foregroundColor(TVColors.successGreen)
                        Text("登录成功")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .frame(width: 380, height: 380)
                } else if selectedMode == .officialQR && isBusy {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.4)
                        Text("正在生成安全登录码...")
                            .font(.system(size: 18))
                            .foregroundColor(TVColors.textMuted)
                    }
                    .frame(width: 380, height: 380)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 100))
                            .foregroundColor(TVColors.textMuted)
                        Text("等待获取二维码...")
                            .font(.system(size: 18))
                            .foregroundColor(TVColors.textMuted)
                    }
                    .frame(width: 380, height: 380)
                }
            }

            // 状态提示与倒计时胶囊
            VStack(spacing: 10) {
                Text(statusMessage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(TVColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                if selectedMode == .officialQR && hasQrURL && remainingSeconds > 0 && !isSuccess {
                    Text("有效期剩余 \(remainingSeconds) 秒")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TVColors.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(width: 440)
        .focusSection()
    }
}
