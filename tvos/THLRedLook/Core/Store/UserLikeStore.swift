import Foundation
import Combine

/// 用户点赞状态内存协调器（纯接口请求驱动，不进行任何本地持久化存储）
@MainActor
public final class UserLikeStore: ObservableObject {
    public static let shared = UserLikeStore()

    @Published public private(set) var likedRecords: [UserLikeRecord] = []

    public init() {
        UserDefaults.standard.removeObject(forKey: "thl_user_liked_records_v1")
    }

    public var likedDramas: [Drama] {
        var seen = Set<String>()
        var result: [Drama] = []
        for record in likedRecords.sorted(by: { $0.likedAt > $1.likedAt }) {
            if !seen.contains(record.drama.id) {
                seen.insert(record.drama.id)
                result.append(record.drama)
            }
        }
        return result
    }

    public func isLiked(dramaId: String, episode: Int = 1) -> Bool {
        if let state = HongguoAccountModel.shared.socialStates[dramaId],
           let ep = state.episode(episode) {
            return ep.liked
        }
        let key = "\(dramaId)_\(episode)"
        return likedRecords.contains { $0.id == key }
    }

    @discardableResult
    public func toggleLike(drama: Drama, episode: Int = 1) async -> Bool {
        guard HongguoAccountModel.shared.loggedIn else { return false }
        let key = "\(drama.id)_\(episode)"
        let currentlyLiked = isLiked(dramaId: drama.cleanSourceId, episode: episode)
        let newLikedState = !currentlyLiked

        await syncOfficialLike(drama: drama, episodeNumber: episode, liked: newLikedState)

        if newLikedState {
            let record = UserLikeRecord(drama: drama, episode: episode, likedAt: Date())
            likedRecords.insert(record, at: 0)
        } else {
            likedRecords.removeAll { $0.id == key }
        }

        return newLikedState
    }

    public func removeLike(dramaId: String, episode: Int = 1) {
        let key = "\(dramaId)_\(episode)"
        likedRecords.removeAll { $0.id == key }
    }

    public func clearAll() {
        likedRecords.removeAll()
    }

    private func syncOfficialLike(drama: Drama, episodeNumber: Int, liked: Bool) async {
        if let data = HongguoAccountModel.shared.socialStates[drama.cleanSourceId],
           let episodeLike = data.episode(episodeNumber) {
            do {
                try await HongguoAccountModel.shared.setLiked(drama, episode: episodeLike, liked: liked)
            } catch {
                NSLog("🎬 [UserLikeStore] 接口请求点赞失败: %@", error.localizedDescription)
            }
        }
    }
}
