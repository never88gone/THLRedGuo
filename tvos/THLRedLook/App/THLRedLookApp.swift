import SwiftUI
import Combine

/// DeepLink 搜索请求协调器：彻底解耦视图生命周期与 SwiftUI 状态延迟
@MainActor
public final class DeepLinkSearchCoordinator: ObservableObject {
    public static let shared = DeepLinkSearchCoordinator()

    public struct Request: Identifiable, Equatable {
        public let id = UUID()
        public let keyword: String
        public let episode: Int?
        public let timestamp = Date()
    }

    @Published public private(set) var latestRequest: Request?

    public init() {}

    public func handle(keyword: String, episode: Int? = nil) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSLog("🚀 [DeepLinkCoordinator] Dispatching search request: '%@', episode=%@", trimmed, String(describing: episode))
        self.latestRequest = Request(keyword: trimmed, episode: episode)
    }

    public func clearRequest() {
        self.latestRequest = nil
    }
}

@MainActor
public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()

    public let store = LocalStore.shared
    public let repository = NativeRepository.shared
    public let lanService = LanSyncService.shared
    public let downloadService = DownloadService.shared
    public let jsService = JSSourceService.shared
    public let icloudSync = ICloudSyncService.shared
    public let deepLinkCoordinator = DeepLinkSearchCoordinator.shared

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
                    .environmentObject(env.deepLinkCoordinator)

                if showSplash {
                    TVLaunchSplashView()
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleGlobalDeepLink(url)
            }
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

    private func handleGlobalDeepLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "thlredlook" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let host = components.host?.lowercased() ?? ""
        if host == "search" {
            let kw = components.queryItems?.first(where: { $0.name == "keyword" })?.value ?? ""
            let epStr = components.queryItems?.first(where: { $0.name == "episode" })?.value
            let ep = epStr.flatMap { Int($0) }
            
            NSLog("🎯 [THLRedLookApp] onOpenURL received: keyword='%@', episode=%@", kw, String(describing: ep))
            DeepLinkSearchCoordinator.shared.handle(keyword: kw, episode: ep)
        }
    }
}

