import Foundation
import Combine

/// 主播关注内存协调器（纯接口请求驱动，不进行任何本地持久化存储）
@MainActor
public final class AnchorFollowStore: ObservableObject {
    public static let shared = AnchorFollowStore()

    @Published public private(set) var followedAnchors: [Anchor] = []

    public init() {
        UserDefaults.standard.removeObject(forKey: "thl_followed_anchors_v1")
    }

    public func isFollowed(anchorId: String) -> Bool {
        followedAnchors.contains { $0.id == anchorId }
    }

    @discardableResult
    public func toggleFollow(anchor: Anchor, drama: Drama? = nil) async -> Bool {
        guard HongguoAccountModel.shared.loggedIn else { return false }
        let currentlyFollowed = anchor.following ?? isFollowed(anchorId: anchor.id)
        let newFollowState = !currentlyFollowed

        do {
            try await HongguoAccountModel.shared.setProfileFollowing(anchor, follow: newFollowState)
        } catch {
            NSLog("🎬 [AnchorFollowStore] 接口请求关注失败: %@", error.localizedDescription)
        }

        if newFollowState {
            if !followedAnchors.contains(where: { $0.id == anchor.id }) {
                followedAnchors.insert(anchor, at: 0)
            }
        } else {
            followedAnchors.removeAll { $0.id == anchor.id }
        }

        return newFollowState
    }

    public func unfollow(anchorId: String) {
        followedAnchors.removeAll { $0.id == anchorId }
    }

    public func clearAll() {
        followedAnchors.removeAll()
    }
}
