import SwiftUI

// MARK: - 保持向后兼容的官方扫码登录视图包装
public struct TVQrLoginView: View {
    public init() {}
    public var body: some View {
        TVLoginOptionsView(initialMode: .officialQR)
    }
}

#Preview("TVQrLoginView") {
    TVQrLoginView()
}
