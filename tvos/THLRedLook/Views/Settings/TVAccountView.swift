import SwiftUI
import CoreImage.CIFilterBuiltins

struct TVAccountView: View {
    @ObservedObject private var model = HongguoAccountModel.shared
    @State private var showingLogin = false
    @State private var showingSettings = false
    @State private var confirmingLogout = false
    @State private var openedDebugLogin = false
    @FocusState private var focus: String?
    var initialCategory: SettingsCategory = .sources
    var forceFocusActiveSource = false
    var focusSidebarTrigger = 0
    var onRequestFocusTopNav: (() -> Void)?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Label("我的", systemImage: "person.crop.circle").font(.system(size: 42, weight: .bold))
                VStack(alignment: .leading, spacing: 22) {
                    Text(model.loggedIn ? model.account?.nickname ?? "红果用户" : "登录红果账号").font(.system(size: 36, weight: .semibold))
                    Text(model.loggedIn ? model.verified ? "红果账号已登录" : "登录状态待确认" : "用手机红果 App 扫码，在手机上确认登录").font(.system(size: 29))
                    if let account = model.account, model.loggedIn { Text("账号尾号：" + account.id.suffix(4)).font(.system(size: 25)) }
                    HStack(spacing: 28) {
                        Button(model.loggedIn ? "重新扫码 / 切换账号" : "红果 App 扫码登录") { showingLogin = true }
                            .focused($focus, equals: "login")
                            .accessibilityIdentifier("hongguo-account-login")
                        if model.loggedIn {
                            Button("确认账号") { Task { await model.verify(force: true) } }.disabled(model.busy)
                            Button("退出登录") { confirmingLogout = true }
                        }
                    }
                    if !model.message.isEmpty { Text(model.message).font(.system(size: 25)).foregroundStyle(.secondary) }
                }.padding(36).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.07)))
                Button("应用设置") { showingSettings = true }.focused($focus, equals: "settings")
                Text("本地追剧、观看历史和下载可从主导航进入，退出账号会保留这些资料。").font(.system(size: 29)).foregroundStyle(.secondary)
                Text("官方账号收藏、历史、点赞与预约同步尚未接入。").font(.system(size: 25)).foregroundStyle(.secondary)
            }.padding(40)
        }
        .defaultFocus($focus, "login")
        .onAppear {
            focus = "login"
            Task { await model.verify() }
            #if DEBUG
            if !openedDebugLogin && CommandLine.arguments.contains("-openAccountLogin") {
                openedDebugLogin = true
                showingLogin = true
            }
            #endif
        }
        .onChange(of: focusSidebarTrigger) { _, _ in focus = "login" }
        .onExitCommand { onRequestFocusTopNav?() }
        .fullScreenCover(isPresented: $showingLogin, onDismiss: { model.cancel(); focus = "login" }) { TVQrLoginView() }
        .sheet(isPresented: $showingSettings, onDismiss: { focus = "settings" }) {
            SettingsView(initialCategory: initialCategory, forceFocusActiveSource: forceFocusActiveSource,
                onRequestFocusTopNav: { showingSettings = false }).padding(40)
        }
        .onChange(of: initialCategory) { _, _ in showingSettings = true }
        .onAppear { if forceFocusActiveSource || initialCategory != .sources { showingSettings = true } }
        .confirmationDialog("退出红果账号？本地收藏、历史和进度会保留。", isPresented: $confirmingLogout) {
            Button("退出登录", role: .destructive) { model.logout() }
            Button("取消", role: .cancel) {}
        }
    }
}

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
                else { Image(systemName: "qrcode").font(.system(size: 180)).foregroundStyle(.secondary) }
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
        .onDisappear { qrImage = nil; model.cancel() }
        .onExitCommand { model.cancel(); dismiss() }
        .onChange(of: model.verified) { _, value in if value && model.qrURL == nil { dismiss() } }
        .onChange(of: model.qrURL) { _, value in
            qrImage = value.flatMap(image)
            if value == nil && model.message == "红果账号已登录" { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.cancel() } }
    }
}
