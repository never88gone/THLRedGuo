import SwiftUI
import CoreImage.CIFilterBuiltins

struct TVQrLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var model = HongguoAccountModel.shared
    @FocusState private var focus: String?
    @State private var qrImage: UIImage?
    private func image(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return UIImage(cgImage: cg)
    }
    var body: some View {
        VStack(spacing: 30) {
            Text("红果 App 扫码登录").font(.system(size: 42, weight: .bold))
            Text("打开手机红果 App 的“扫一扫”，扫描后在手机确认").font(.system(size: 29))
            Group {
                if let qr = qrImage {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().padding(24).background(.white)
                        .accessibilityLabel("红果登录二维码")
                } else if model.busy { ProgressView() }
                else { Image(systemName: "clock").font(.system(size: 120)).foregroundStyle(.secondary) }
            }.frame(width: 370, height: 370)
            Text(model.message).font(.system(size: 29))
            if model.qrURL != nil { Text("剩余 \(model.remaining) 秒").font(.system(size: 25)) }
            HStack(spacing: 36) {
                Button("刷新二维码") { model.begin() }.disabled(model.busy).focused($focus, equals: "refresh")
                Button("取消登录") { model.cancel(); dismiss() }.focused($focus, equals: "cancel")
            }
        }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity).background(TVTheme.backgroundGradient)
        .defaultFocus($focus, "cancel")
        .onAppear { focus = "cancel"; model.begin() }
        .onDisappear { qrImage = nil; if !model.loggedIn || !model.verified { model.cancel() } }
        .onExitCommand { model.cancel(); dismiss() }
        .onChange(of: model.verified) { _, value in if value && model.qrURL == nil { dismiss() } }
        .onChange(of: model.qrURL) { _, value in
            qrImage = value.flatMap(image)
            if value == nil && model.message == "红果账号已登录" { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.cancel() } }
    }
}

struct TVLoginOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = HongguoAccountModel.shared
    @State private var method: Method?
    @State private var loginRevision: UInt64?
    @FocusState private var focus: Method?
    enum Method: String, Identifiable { case sms, password, officialQR, hawQR; var id: String { rawValue } }
    var body: some View {
        VStack(spacing: 30) {
            Text("登录红果账号").font(.system(size: 48, weight: .bold))
            Button("手机号与验证码") { method = .sms }.focused($focus, equals: .sms).accessibilityIdentifier("hongguo-login-sms")
            Button("手机号与密码") { method = .password }.focused($focus, equals: .password).accessibilityIdentifier("hongguo-login-password")
            Button("红果 App 扫码") { method = .officialQR }.focused($focus, equals: .officialQR).accessibilityIdentifier("hongguo-login-qr")
            Button("手机糖葫芦 Haw 扫码") { method = .hawQR }.focused($focus, equals: .hawQR).accessibilityIdentifier("hongguo-login-haw-pair")
            Text("手机糖葫芦 Haw 登录后，可通过同一局域网授权此设备。").font(.system(size: 29)).foregroundStyle(.secondary)
            Button("返回") { dismiss() }
        }.padding(60).frame(maxWidth: .infinity, maxHeight: .infinity).background(TVTheme.backgroundGradient)
        .defaultFocus($focus, .officialQR)
        .onAppear { if loginRevision == nil { focus = .officialQR; loginRevision = HongguoAccountVault.shared.snapshot.revision } }
        .onExitCommand { dismiss() }
        .fullScreenCover(item: $method, onDismiss: {
            if model.loggedIn && model.verified && HongguoAccountVault.shared.snapshot.revision != loginRevision { dismiss() }
        }) { selection in
            switch selection {
            case .officialQR: TVQrLoginView()
            case .sms: TVPhoneLoginView(passwordMode: false)
            case .password: TVPhoneLoginView(passwordMode: true)
            case .hawQR: TVHawPairLoginView()
            }
        }
    }
}

struct TVPhoneLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = HongguoAccountModel.shared
    @State var passwordMode: Bool
    @State private var country = "86"
    @State private var number = ""
    @State private var secret = ""
    @State private var working = false
    @State private var error: String?
    @State private var remaining = 0
    @FocusState private var focus: String?
    private func run(_ sending: Bool) {
        guard !working else { return }
        let cc = country.replacingOccurrences(of: "+", with: ""), digits = number.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        guard cc.range(of: "^[1-9][0-9]{0,2}$", options: .regularExpression) != nil,
            digits.range(of: cc == "86" ? "^1[0-9]{10}$" : "^[0-9]{4,14}$", options: .regularExpression) != nil else { error = "手机号格式无效"; return }
        if !sending && (secret.isEmpty || !passwordMode && secret.range(of: "^[0-9]{4,8}$", options: .regularExpression) == nil) { error = passwordMode ? "请输入密码" : "请输入正确的验证码"; return }
        working = true; error = nil
        Task {
            do {
                if sending { try await model.sendPhoneCode(country: cc, number: digits); remaining = max(0, Int(ceil(model.phoneRetryAt.timeIntervalSinceNow))) }
                else { try await model.loginPhone(country: cc, number: digits, secret: secret, password: passwordMode); secret = ""; dismiss() }
            } catch {
                if let issue = error as? HongguoAccountError { self.error = issue.localizedDescription }
                else { self.error = "登录请求暂时失败，请稍后再试" }
            }
            working = false
        }
    }
    var body: some View {
        VStack(spacing: 24) {
            Text(passwordMode ? "手机号与密码登录" : "手机号与验证码登录").font(.system(size: 44, weight: .bold))
            HStack(spacing: 24) {
                HStack { Text("+"); TextField("区号", text: $country).focused($focus, equals: "country").accessibilityIdentifier("login-country") }.frame(width: 190)
                TextField("手机号", text: $number).textContentType(.telephoneNumber).focused($focus, equals: "phone").accessibilityIdentifier("login-phone")
            }.disabled(working)
            if passwordMode { SecureField("密码", text: $secret).textContentType(.password).focused($focus, equals: "secret").accessibilityIdentifier("login-secret").disabled(working) }
            else { TextField("短信验证码", text: $secret).textContentType(.oneTimeCode).focused($focus, equals: "secret").accessibilityIdentifier("login-secret").disabled(working) }
            if !passwordMode {
                Button(remaining > 0 ? "\(remaining)s 后重新获取" : "获取验证码") { run(true) }.disabled(working || remaining > 0).focused($focus, equals: "send").accessibilityIdentifier("phone-send-code")
            }
            if let error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("phone-login-error") }
            HStack(spacing: 40) {
                Button(working ? "正在处理" : "登录") { run(false) }.disabled(working).focused($focus, equals: "submit").accessibilityIdentifier("phone-login-submit")
                Button(passwordMode ? "使用验证码" : "使用密码") { passwordMode.toggle(); secret = ""; error = nil }.disabled(working)
                Button("返回") { model.cancel(); dismiss() }
            }
            Text("验证码由你点击后发送。糖葫芦 Haw 不保存密码或验证码。").font(.system(size: 29)).foregroundStyle(.secondary)
        }.font(.system(size: 29)).frame(maxWidth: 1000).padding(60).frame(maxWidth: .infinity, maxHeight: .infinity).background(TVTheme.backgroundGradient)
        .defaultFocus($focus, "phone")
        .onAppear { focus = "phone"; remaining = max(0, Int(ceil(model.phoneRetryAt.timeIntervalSinceNow))) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in remaining = max(0, Int(ceil(model.phoneRetryAt.timeIntervalSinceNow))) }
        .onExitCommand { model.cancel(); dismiss() }
        .onDisappear { secret = ""; if !model.loggedIn || !model.verified { model.cancel() } }
    }
}

struct TVHawPairLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var server = AccountPairingServer()
    @State private var qrImage: UIImage?
    @State private var replacementID: String?
    @State private var replacementDecision: CheckedContinuation<Bool, Never>?
    @FocusState private var focus: String?
    private func completeReplacement(_ accepted: Bool) {
        let decision = replacementDecision; replacementDecision = nil; replacementID = nil; decision?.resume(returning: accepted)
    }
    private func image(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(value.utf8)
        guard let output = filter.outputImage,
            let cg = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return UIImage(cgImage: cg)
    }
    var body: some View {
        VStack(spacing: 30) {
            Text("手机糖葫芦 Haw 扫码登录").font(.system(size: 44, weight: .bold))
            Text("两端连接同一局域网，在已登录的手机 Haw 中选择“扫一扫登录其他设备”").font(.system(size: 29))
            Group {
                if let qrImage { Image(uiImage: qrImage).interpolation(.none).resizable().scaledToFit().padding(24).background(.white).accessibilityLabel("糖葫芦 Haw 设备登录配对码") }
                else { Image(systemName: "qrcode").font(.system(size: 100)) }
            }.frame(width: 370, height: 370)
            Text(server.message).font(.system(size: 29))
            HStack(spacing: 40) {
                Button("重新生成配对码") { server.start() }.focused($focus, equals: "refresh").accessibilityIdentifier("haw-account-pair-refresh")
                Button("返回") { server.stop(); dismiss() }.focused($focus, equals: "cancel")
            }
            Text("只有手机逐次确认后才传递当前账号，会话通过局域网加密传输。").font(.system(size: 29)).foregroundStyle(.secondary)
        }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity).background(TVTheme.backgroundGradient)
        .defaultFocus($focus, "cancel")
        .onAppear {
            focus = "cancel"; server.onAccepted = { [dismiss] in dismiss() }
            server.approveReplacement = { id in await withCheckedContinuation { decision in replacementID = id; replacementDecision = decision } }
            server.start()
        }
        .onDisappear { completeReplacement(false); qrImage = nil; server.stop(); server.approveReplacement = nil }
        .confirmationDialog("切换红果账号？", isPresented: Binding(get: { replacementID != nil }, set: { if !$0 { completeReplacement(false) } }), titleVisibility: .visible) {
            Button("切换账号") { completeReplacement(true) }
            Button("取消", role: .cancel) { completeReplacement(false) }
        } message: { Text("是否使用手机确认的红果账号替换本设备当前账号？本地追剧、历史和进度会保留。") }
        .onChange(of: server.qr) { _, value in qrImage = value.flatMap(image); if value == nil { completeReplacement(false) } }
        .onChange(of: scenePhase) { _, value in if value != .active { completeReplacement(false); server.stop() } }
        .onExitCommand { completeReplacement(false); server.stop(); dismiss() }
    }
}
