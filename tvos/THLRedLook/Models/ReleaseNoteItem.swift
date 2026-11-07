import Foundation

/// 版本更新日志条目模型
public struct ReleaseNoteItem: Identifiable, Equatable {
    public let id: String
    public let version: String
    public let date: String
    public let items: [String]
    public let isLatest: Bool

    public init(
        id: String = UUID().uuidString,
        version: String,
        date: String,
        items: [String],
        isLatest: Bool = false
    ) {
        self.id = id
        self.version = version
        self.date = date
        self.items = items
        self.isLatest = isLatest
    }
}
