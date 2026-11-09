import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
struct SourceDiagnosticsQRSheet: View {
    let report: String
    let onClose: () -> Void
    @StateObject private var server = DiagnosticsShareServer()

    private var image: UIImage? {
        guard let url = server.url else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return UIImage(cgImage: image)
    }

    var body: some View {
        VStack(spacing: 22) {
            Text("手机扫码导出完整日志").font(.system(size: 42, weight: .bold))
            if let image {
                Image(uiImage: image).interpolation(.none).resizable()
                    .scaledToFit().frame(width: 420, height: 420)
                    .padding(24).background(.white)
            } else if server.message.hasPrefix("正在") { ProgressView().frame(height: 260) }
            else { Image(systemName: "wifi.exclamationmark").font(.system(size: 90)).frame(height: 200) }
            Text(server.message).font(.system(size: 27)).multilineTextAlignment(.center)
            if let url = server.url {
                Text(url.absoluteString).font(.system(size: 21, design: .monospaced))
                    .accessibilityIdentifier("sourceDiagnostics.shareURL")
            }
            Text("打开后可复制或下载报告并手动发送。关闭此页即失效，最长有效 10 分钟，不会自动上传。")
                .font(.system(size: 23)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            TVButton(title: "返回诊断", icon: "arrow.backward", isProminent: true) { onClose() }
                .accessibilityIdentifier("sourceDiagnostics.qrBack")
        }
        .padding(48)
        .onAppear { server.start(report: report) }
        .onDisappear { server.stop() }
        .onExitCommand { onClose() }
    }
}
