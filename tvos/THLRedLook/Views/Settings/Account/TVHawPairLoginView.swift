import SwiftUI

// MARK: - 保持向后兼容的手机 Haw 配对登录视图包装
public struct TVHawPairLoginView: View {
    public init() {}
    public var body: some View {
        TVLoginOptionsView(initialMode: .hawQR)
    }
}

#Preview("TVHawPairLoginView") {
    TVHawPairLoginView()
}
