import SwiftUI

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
