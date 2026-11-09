import SwiftUI

/// tvOS 启动开屏视图：无缝深色背景 → 发光 Logo 弹出 (scale 1.15) → 缩回正常大小 (scale 1.0)
public struct TVLaunchSplashView: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0

    public init() {}

    public var body: some View {
        ZStack {
            // 纯净深色冷启动背景（与系统 UILaunchScreen 一致，零闪烁、零位移、无任何残留静态图）
            Image("LaunchBackground", bundle: .main)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            // 独立透明发光 Logo：无文字、无黑块，由中心 Spring 弹性弹出并回弹
            Image("LaunchLogo", bundle: .main)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 760, height: 760)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.interpolatingSpring(stiffness: 220, damping: 13)) {
                    logoScale = 1.15
                    logoOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        logoScale = 1.0
                    }
                }
            }
        }
    }
}
