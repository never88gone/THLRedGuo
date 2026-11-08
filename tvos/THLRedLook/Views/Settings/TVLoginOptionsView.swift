import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - 现代化电视大屏一体化扫码登录中心
public struct TVLoginOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var model = HongguoAccountModel.shared
    @StateObject private var pairingServer = AccountPairingServer()

    @State private var selectedMode: TVLoginMode = .officialQR
    @State private var qrImage: UIImage?
    @State private var loginRevision: UInt64?
    @State private var isSuccess = false

    // 账号切换决策支持（局域网配对）
    @State private var replacementID: String?
    @State private var replacementDecision: CheckedContinuation<Bool, Never>?

    public enum Method: String, Identifiable {
        case officialQR
        case hawQR
        case refresh
        case dismiss
        public var id: String { rawValue }
    }
    @FocusState private var focus: Method?

    public init(initialMode: TVLoginMode = .officialQR) {
        _selectedMode = State(initialValue: initialMode)
    }

    private func completeReplacement(_ accepted: Bool) {
        let decision = replacementDecision
        replacementDecision = nil
        replacementID = nil
        decision?.resume(returning: accepted)
    }

    private static func generateQRCode(from value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaled = output.transformed(by: transform)
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    public var body: some View {
        HStack(spacing: 50) {
            // 左侧：品牌信息、模式切换与操作指引
            VStack(alignment: .leading, spacing: 24) {
                // Header 区域
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "tv.badge.wifi")
                            .font(.system(size: 32))
                            .foregroundColor(TVColors.primary)
                        Text("红果账号大屏登录")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(TVColors.textPrimary)
                    }
                    Text("扫码快速同步手机端追剧书架、观看历史与播放进度，享受无缝大屏观影。")
                        .font(.system(size: 19))
                        .foregroundColor(TVColors.textSecondary)
                }

                // 扫码模式切换卡片（大屏纯扫码，沉浸精致焦点与红果品牌高光）
                VStack(spacing: 16) {
                    let isOfficialFocused = (focus == .officialQR)
                    Button {
                        switchMode(.officialQR)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(isOfficialFocused ? .white : (selectedMode == .officialQR ? TVColors.primary : Color.white.opacity(0.8)))
                                .frame(width: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("红果 App 扫码")
                                    .font(.system(size: 22, weight: isOfficialFocused || selectedMode == .officialQR ? .bold : .semibold))
                                    .foregroundColor(isOfficialFocused ? .white : TVColors.textPrimary)
                                Text("官方推荐 · 手机红果扫一扫")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(isOfficialFocused ? Color.white.opacity(0.85) : TVColors.textSecondary)
                            }
                            Spacer()
                            if selectedMode == .officialQR {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(isOfficialFocused ? .white : TVColors.primaryHover)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(
                                    isOfficialFocused
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [TVColors.buttonFocusedGradStart, TVColors.buttonFocusedGradEnd],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        : (selectedMode == .officialQR ? AnyShapeStyle(Color.white.opacity(0.10)) : AnyShapeStyle(Color.white.opacity(0.04)))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(
                                    isOfficialFocused ? Color.white : (selectedMode == .officialQR ? TVTheme.primary.opacity(0.6) : Color.white.opacity(0.08)),
                                    lineWidth: isOfficialFocused ? 2.5 : 1.0
                                )
                        )
                        .scaleEffect(isOfficialFocused ? 1.04 : 1.0)
                        .shadow(
                            color: isOfficialFocused ? TVColors.focusedShadowStrong : Color.clear,
                            radius: isOfficialFocused ? 14 : 0,
                            x: 0,
                            y: isOfficialFocused ? 4 : 0
                        )
                        .animation(TVTheme.focusSpringAnimation, value: isOfficialFocused)
                    }
                    .buttonStyle(TVZeroHighlightButtonStyle())
                    .focusEffectDisabled()
                    .focused($focus, equals: .officialQR)
                    .accessibilityIdentifier("hongguo-login-qr")

                    let isHawFocused = (focus == .hawQR)
                    Button {
                        switchMode(.hawQR)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "iphone.and.arrow.forward")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(isHawFocused ? .white : (selectedMode == .hawQR ? TVColors.primary : Color.white.opacity(0.8)))
                                .frame(width: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("手机糖葫芦 Haw 扫码")
                                    .font(.system(size: 22, weight: isHawFocused || selectedMode == .hawQR ? .bold : .semibold))
                                    .foregroundColor(isHawFocused ? .white : TVColors.textPrimary)
                                Text("同一局域网内手机 Haw 快速授权")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(isHawFocused ? Color.white.opacity(0.85) : TVColors.textSecondary)
                            }
                            Spacer()
                            if selectedMode == .hawQR {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(isHawFocused ? .white : TVColors.primaryHover)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(
                                    isHawFocused
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [TVColors.buttonFocusedGradStart, TVColors.buttonFocusedGradEnd],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        : (selectedMode == .hawQR ? AnyShapeStyle(Color.white.opacity(0.10)) : AnyShapeStyle(Color.white.opacity(0.04)))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(
                                    isHawFocused ? Color.white : (selectedMode == .hawQR ? TVTheme.primary.opacity(0.6) : Color.white.opacity(0.08)),
                                    lineWidth: isHawFocused ? 2.5 : 1.0
                                )
                        )
                        .scaleEffect(isHawFocused ? 1.04 : 1.0)
                        .shadow(
                            color: isHawFocused ? TVColors.focusedShadowStrong : Color.clear,
                            radius: isHawFocused ? 14 : 0,
                            x: 0,
                            y: isHawFocused ? 4 : 0
                        )
                        .animation(TVTheme.focusSpringAnimation, value: isHawFocused)
                    }
                    .buttonStyle(TVZeroHighlightButtonStyle())
                    .focusEffectDisabled()
                    .focused($focus, equals: .hawQR)
                    .accessibilityIdentifier("hongguo-login-haw-pair")
                }

                // 步骤指引卡片
                VStack(alignment: .leading, spacing: 10) {
                    Text("操作指引")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))

                    if selectedMode == .officialQR {
                        stepRow(number: "1", title: "打开手机【红果短剧】App")
                        stepRow(number: "2", title: "点击顶部或「我的」页面右上角的【扫一扫】")
                        stepRow(number: "3", title: "对准右侧大屏二维码，在手机端点击【确认登录】")
                    } else {
                        stepRow(number: "1", title: "确保手机与电视连接至同一 Wi-Fi 局域网")
                        stepRow(number: "2", title: "打开已登录的手机端【糖葫芦 Haw】App")
                        stepRow(number: "3", title: "在我的页面选择【扫一扫授权】，扫描右侧配对码")
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer()

                // 底部操作按钮（采用全局统一高奢焦点按钮）
                HStack(spacing: 24) {
                    let isRefreshFocused = (focus == .refresh)
                    Button {
                        refreshCode()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .bold))
                            Text(selectedMode == .officialQR && model.remaining > 0 ? "刷新 (\(model.remaining)s)" : "刷新二维码")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(isRefreshFocused ? .white : TVColors.textPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    isRefreshFocused
                                        ? AnyShapeStyle(LinearGradient(colors: [TVColors.buttonFocusedGradStart, TVColors.buttonFocusedGradEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Color.white.opacity(0.08))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    isRefreshFocused ? Color.white : Color.white.opacity(0.14),
                                    lineWidth: isRefreshFocused ? 2.5 : 1.0
                                )
                        )
                        .scaleEffect(isRefreshFocused ? 1.06 : 1.0)
                        .shadow(
                            color: isRefreshFocused ? TVColors.focusedShadowStrong : Color.clear,
                            radius: isRefreshFocused ? 12 : 0,
                            x: 0,
                            y: isRefreshFocused ? 3 : 0
                        )
                        .animation(TVTheme.focusSpringAnimation, value: isRefreshFocused)
                    }
                    .buttonStyle(TVZeroHighlightButtonStyle())
                    .focusEffectDisabled()
                    .focused($focus, equals: .refresh)
                    .accessibilityIdentifier(selectedMode == .officialQR ? "hongguo-qr-refresh" : "haw-account-pair-refresh")

                    let isDismissFocused = (focus == .dismiss)
                    Button {
                        cleanupAndDismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                            Text("返回")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(isDismissFocused ? .white : TVColors.textPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    isDismissFocused
                                        ? AnyShapeStyle(LinearGradient(colors: [TVColors.buttonFocusedGradStart, TVColors.buttonFocusedGradEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Color.white.opacity(0.08))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    isDismissFocused ? Color.white : Color.white.opacity(0.14),
                                    lineWidth: isDismissFocused ? 2.5 : 1.0
                                )
                        )
                        .scaleEffect(isDismissFocused ? 1.06 : 1.0)
                        .shadow(
                            color: isDismissFocused ? TVColors.focusedShadowStrong : Color.clear,
                            radius: isDismissFocused ? 12 : 0,
                            x: 0,
                            y: isDismissFocused ? 3 : 0
                        )
                        .animation(TVTheme.focusSpringAnimation, value: isDismissFocused)
                    }
                    .buttonStyle(TVZeroHighlightButtonStyle())
                    .focusEffectDisabled()
                    .focused($focus, equals: .dismiss)
                    .accessibilityIdentifier("hongguo-login-cancel")
                }
            }
            .frame(width: 580)
            .focusSection()

            // 右侧：高清白底大二维码展示卡片与动态状态
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
                    } else if (selectedMode == .officialQR && model.busy) {
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
                    Text(currentStatusMessage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(TVColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    if selectedMode == .officialQR && model.qrURL != nil && model.remaining > 0 && !isSuccess {
                        Text("有效期剩余 \(model.remaining) 秒")
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
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TVColors.backgroundGradient.ignoresSafeArea())
        .defaultFocus($focus, .officialQR)
        .onAppear {
            if loginRevision == nil {
                loginRevision = HongguoAccountVault.shared.snapshot.revision
            }
            focus = .officialQR
            startCurrentMode()
        }
        .onDisappear {
            cleanup()
        }
        .onExitCommand {
            cleanupAndDismiss()
        }
        .confirmationDialog("切换红果账号？", isPresented: Binding(get: { replacementID != nil }, set: { if !$0 { completeReplacement(false) } }), titleVisibility: .visible) {
            Button("切换账号") { completeReplacement(true) }
            Button("取消", role: .cancel) { completeReplacement(false) }
        } message: {
            Text("是否使用手机确认的红果账号替换本设备当前账号？本地追剧、历史和进度会完整保留。")
        }
        .onChange(of: model.verified) { _, value in
            if value && model.qrURL == nil {
                triggerSuccessAndDismiss()
            }
        }
        .onChange(of: model.qrURL) { _, value in
            if selectedMode == .officialQR {
                qrImage = value.flatMap(Self.generateQRCode)
                if value == nil && model.message == "红果账号已登录" {
                    triggerSuccessAndDismiss()
                }
            }
        }
        .onChange(of: pairingServer.qr) { _, value in
            if selectedMode == .hawQR {
                qrImage = value.flatMap(Self.generateQRCode)
                if value == nil {
                    completeReplacement(false)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cleanup()
            }
        }
    }

    private var currentStatusMessage: String {
        if isSuccess {
            return "登录验证成功，正在同步账号数据..."
        }
        if selectedMode == .officialQR {
            return model.message.isEmpty ? "请使用手机红果 App 扫码登录" : model.message
        } else {
            return pairingServer.message.isEmpty ? "请用已登录的手机糖葫芦 Haw 扫码并确认" : pairingServer.message
        }
    }

    private func switchMode(_ mode: TVLoginMode) {
        guard selectedMode != mode else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            selectedMode = mode
        }
        startCurrentMode()
    }

    private func stepRow(number: String, title: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 24, height: 24)
                Text(number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TVColors.textPrimary)
            }
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(TVColors.textSecondary)
        }
    }

    private func startCurrentMode() {
        qrImage = nil
        if selectedMode == .officialQR {
            pairingServer.stop()
            pairingServer.approveReplacement = nil
            model.begin()
            if let existing = model.qrURL {
                qrImage = Self.generateQRCode(from: existing)
            }
        } else {
            model.cancel()
            pairingServer.onAccepted = { [dismiss] in
                triggerSuccessAndDismiss()
            }
            pairingServer.approveReplacement = { id in
                await withCheckedContinuation { decision in
                    replacementID = id
                    replacementDecision = decision
                }
            }
            pairingServer.start()
            if let existing = pairingServer.qr {
                qrImage = Self.generateQRCode(from: existing)
            }
        }
    }

    private func refreshCode() {
        if selectedMode == .officialQR {
            model.begin()
        } else {
            pairingServer.start()
        }
    }

    private func triggerSuccessAndDismiss() {
        withAnimation {
            isSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dismiss()
        }
    }

    private func cleanup() {
        completeReplacement(false)
        qrImage = nil
        model.cancel()
        pairingServer.stop()
        pairingServer.approveReplacement = nil
    }

    private func cleanupAndDismiss() {
        cleanup()
        dismiss()
    }
}

#Preview("TVLoginOptionsView") {
    TVLoginOptionsView()
}
