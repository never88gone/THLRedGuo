import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
struct ApkProfileImportSheet: View {
    let onClose: () -> Void
    let onImported: () async -> Void
    @StateObject private var server = ApkProfileImportServer()
    @FocusState private var backFocused: Bool

    private var image: UIImage? {
        guard let url = server.url else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        let transform = CGAffineTransform(scaleX: 8, y: 8)
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output.transformed(by: transform), from: output.extent.applying(transform)) else { return nil }
        return UIImage(cgImage: image)
    }

    var body: some View {
        VStack(spacing: 26) {
            Text("手机导入红果官方 APK").font(.system(size: 48, weight: .bold))
            if let version = server.importedVersion {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 110)).foregroundStyle(.green)
                    .frame(height: 300)
                Text("已导入红果 \(version)").font(.system(size: 35, weight: .semibold))
                    .accessibilityIdentifier("apkImport.success")
            } else if let image {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 360, height: 360).padding(22).background(.white)
            } else if server.message.hasPrefix("正在") { ProgressView().frame(height: 280) }
            else { Image(systemName: "wifi.exclamationmark").font(.system(size: 100)).frame(height: 260) }
            Text(server.message).font(.system(size: 29)).multilineTextAlignment(.center)
                .accessibilityIdentifier("apkImport.status")
            if let progress = server.progress, server.importedVersion == nil {
                ProgressView(value: progress).frame(maxWidth: 780)
                    .accessibilityIdentifier("apkImport.progress")
            }
            if let url = server.url, server.importedVersion == nil {
                Text(url.absoluteString).font(.system(size: 25, design: .monospaced))
                    .accessibilityIdentifier("apkImport.url")
            }
            Text("配置只保存在这台电视，APK 校验后自动删除。关闭此页，手机导入地址立即失效。")
                .font(.system(size: 27)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 1050)
            TVButton(title: "返回设置", icon: "arrow.backward", isProminent: true, isExternalFocused: backFocused) { onClose() }
                .focused($backFocused)
                .accessibilityIdentifier("apkImport.back")
        }
        .padding(56)
        .onAppear {
            backFocused = true
            server.start(onImported: onImported)
        }
        .onDisappear { server.stop() }
        .onExitCommand { onClose() }
    }
}
