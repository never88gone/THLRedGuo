import SwiftUI
import Combine

@MainActor
public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()

    public let store = LocalStore.shared
    public let repository = NativeRepository.shared
    public let lanService = LanSyncService.shared
    public let downloadService = DownloadService.shared
    public let jsService = JSSourceService.shared
    public let icloudSync = ICloudSyncService.shared

    public init() {}
}

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

@main
struct THLRedLookApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var env = AppEnvironment.shared
    @State private var showSplash: Bool = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .environmentObject(env)
                    .environmentObject(env.store)
                    .environmentObject(env.lanService)
                    .environmentObject(env.downloadService)
                    .environmentObject(env.jsService)
                    .environmentObject(env.icloudSync)

                if showSplash {
                    TVLaunchSplashView()
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = env.store.resourceSettings.keepScreenOn
                if ICloudSyncService.shared.isSyncEnabled {
                    ICloudSyncService.shared.syncWithCloud()
                }
                Task {
                    await env.jsService.initialize()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && ICloudSyncService.shared.isSyncEnabled {
                    ICloudSyncService.shared.syncWithCloud()
                }
            }
        }
    }
}

