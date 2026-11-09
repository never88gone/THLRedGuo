import Foundation

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
