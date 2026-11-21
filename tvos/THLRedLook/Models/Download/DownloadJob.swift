import Foundation

public struct DownloadJob: Identifiable, Hashable, Codable {
    public let id: String
    public let drama: Drama
    public let episode: Episode
    public var state: String
    public var bytes: Int
    public var total: Int
    public var progress: Double
    public let quality: Int
    public var actualQuality: Int
    public var error: String
    public let created: Int64
    public var localPath: String?

    public init(
        id: String,
        drama: Drama,
        episode: Episode,
        state: String = "queued",
        bytes: Int = 0,
        total: Int = 0,
        progress: Double = 0,
        quality: Int = 0,
        actualQuality: Int = 0,
        error: String = "",
        created: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        localPath: String? = nil
    ) {
        self.id = id
        self.drama = drama
        self.episode = episode
        self.state = state
        self.bytes = bytes
        self.total = total
        self.progress = progress
        self.quality = quality
        self.actualQuality = actualQuality
        self.error = error
        self.created = created
        self.localPath = localPath
    }

    public var isCompleted: Bool {
        state == "completed"
    }

    public var isActive: Bool {
        state == "queued" || state == "downloading"
    }

    public var isResumable: Bool {
        state == "paused" || state == "failed"
    }

    public var stateLabel: String {
        switch state {
        case "queued": return "等待下载"
        case "downloading": return "正在下载 \(Int(progress * 100))%"
        case "paused": return "已暂停"
        case "failed": return "下载失败"
        case "completed": return "已下载"
        default: return "等待中"
        }
    }
}
