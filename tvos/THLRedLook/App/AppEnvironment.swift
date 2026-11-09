import Foundation

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
