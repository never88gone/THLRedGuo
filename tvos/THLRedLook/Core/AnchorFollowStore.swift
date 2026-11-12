import Foundation
import Combine

/// 主播关注持久化管理器
@MainActor
public final class AnchorFollowStore: ObservableObject {
    public static let shared = AnchorFollowStore()

    private let storageKey = "thl_followed_anchors_v1"
    @Published public private(set) var followedAnchors: [Anchor] = []

    public init() {
        loadFromStorage()
    }

    public func isFollowed(anchorId: String) -> Bool {
        followedAnchors.contains { $0.id == anchorId }
    }

    @discardableResult
    public func toggleFollow(anchor: Anchor, drama: Drama? = nil) async -> Bool {
        let currentlyFollowed = isFollowed(anchorId: anchor.id)
        let newFollowState = !currentlyFollowed

        if newFollowState {
            if !followedAnchors.contains(where: { $0.id == anchor.id }) {
                followedAnchors.insert(anchor, at: 0)
            }
        } else {
            followedAnchors.removeAll { $0.id == anchor.id }
        }
        saveToStorage()

        // 如果用户已登录官方账号，尝试协同调用官方创作者关注接口
        if let drama = drama, HongguoAccountModel.shared.loggedIn && drama.source == "hongguo" {
            await syncOfficialCreatorFollow(drama: drama, anchorId: anchor.id, follow: newFollowState)
        }

        return newFollowState
    }

    public func unfollow(anchorId: String) {
        followedAnchors.removeAll { $0.id == anchorId }
        saveToStorage()
    }

    public func clearAll() {
        followedAnchors.removeAll()
        saveToStorage()
    }

    private func syncOfficialCreatorFollow(drama: Drama, anchorId: String, follow: Bool) async {
        guard let data = HongguoAccountModel.shared.socialStates[drama.cleanSourceId],
              let creator = data.creators.first(where: { $0.id == anchorId }) else {
            return
        }
        do {
            try await HongguoAccountModel.shared.setCreatorFollowing(drama, creator: creator, follow: follow)
        } catch {
            NSLog("🎬 [AnchorFollowStore] 同步官方创作者关注状态失败: %@", error.localizedDescription)
        }
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([Anchor].self, from: data)
            self.followedAnchors = decoded
        } catch {
            NSLog("🎬 [AnchorFollowStore] 读取已关注主播失败: %@", error.localizedDescription)
        }
    }

    private func saveToStorage() {
        do {
            let encoded = try JSONEncoder().encode(followedAnchors)
            UserDefaults.standard.set(encoded, forKey: storageKey)
        } catch {
            NSLog("🎬 [AnchorFollowStore] 保存已关注主播失败: %@", error.localizedDescription)
        }
    }
}
