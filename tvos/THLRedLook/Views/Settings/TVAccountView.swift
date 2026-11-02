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
