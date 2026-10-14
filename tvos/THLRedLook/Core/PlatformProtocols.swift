import Foundation

// MARK: - 跨平台统一服务协议 (参考 thldytv 架构规范)

public enum SourceAPIError: Error, LocalizedError {
    case networkError(Error)
    case parseError(String)
    case sourceUnavailable(String)
    case playbackUrlEmpty
    case coreUninitialized

    public var errorDescription: String? {
        switch self {
        case .networkError(let err): return "网络请求异常: \(err.localizedDescription)"
        case .parseError(let msg): return "数据解析失败: \(msg)"
        case .sourceUnavailable(let s): return "站源不可用: \(s)"
        case .playbackUrlEmpty: return "站源未返回播放地址"
        case .coreUninitialized: return "核心服务未初始化"
        }
    }
}

/// 剧集元数据与列表提供协议
public protocol DramaSourceProviderProtocol: AnyObject {
    func loadCategories(source: String) async throws -> [CatalogCategory]
    func loadCatalog(source: String, category: String, page: Int, query: String, force: Bool) async throws -> (items: [Drama], hasMore: Bool, page: Int)
    func loadSuggestions(query: String) async throws -> [String]
    func loadDetail(drama: Drama) async throws -> DramaDetail
    func loadRankingBoards() async throws -> [RankingBoard]
    func loadRankings(board: String, page: Int) async throws -> [Drama]
    func loadRecommendations(category: String) async throws -> [Drama]
}

public extension DramaSourceProviderProtocol {
    func loadRankings(board: String) async throws -> [Drama] {
        try await loadRankings(board: board, page: 1)
    }
}

/// 媒体流与解析服务协议
public protocol PlaybackStreamProviderProtocol: AnyObject {
    func resolvePlayback(drama: Drama, episode: Episode?, episodeIndex: Int, quality: Int) async throws -> PlaybackPlan
}

/// 弹幕数据提供协议
public protocol DanmakuProviderProtocol: AnyObject {
    func loadDanmaku(plan: PlaybackPlan, startMs: Int64, durationMs: Int64) async throws -> [DanmakuItem]
}

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
