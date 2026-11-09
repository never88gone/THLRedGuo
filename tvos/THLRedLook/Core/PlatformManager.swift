import Foundation

/// 统一平台服务入口
public final class PlatformManager {
    public static let shared = PlatformManager()

    public let sourceProvider: DramaSourceProviderProtocol
    public let streamProvider: PlaybackStreamProviderProtocol
    public let danmakuProvider: DanmakuProviderProtocol

    private init() {
        let repo = NativeRepository.shared
        self.sourceProvider = repo
        self.streamProvider = repo
        self.danmakuProvider = repo
    }
}
