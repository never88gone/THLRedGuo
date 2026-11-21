import Foundation

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
