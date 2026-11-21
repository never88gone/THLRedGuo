import Foundation

/// 弹幕数据提供协议
public protocol DanmakuProviderProtocol: AnyObject {
    func loadDanmaku(plan: PlaybackPlan, startMs: Int64, durationMs: Int64) async throws -> [DanmakuItem]
}
