import Foundation

/// 媒体流与解析服务协议
public protocol PlaybackStreamProviderProtocol: AnyObject {
    func resolvePlayback(drama: Drama, episode: Episode?, episodeIndex: Int, quality: Int) async throws -> PlaybackPlan
}
