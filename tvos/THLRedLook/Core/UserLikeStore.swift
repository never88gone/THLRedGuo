import Foundation
import Combine

/// 用户点赞视频持久化管理器
@MainActor
public final class UserLikeStore: ObservableObject {
    public static let shared = UserLikeStore()

    private let storageKey = "thl_user_liked_records_v1"
    @Published public private(set) var likedRecords: [UserLikeRecord] = []

    public init() {
        loadFromStorage()
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
        let key = "\(dramaId)_\(episode)"
        return likedRecords.contains { $0.id == key }
    }

    @discardableResult
    public func toggleLike(drama: Drama, episode: Int = 1) async -> Bool {
        let key = "\(drama.id)_\(episode)"
        let currentlyLiked = isLiked(dramaId: drama.id, episode: episode)
        let newLikedState = !currentlyLiked

        if newLikedState {
            let record = UserLikeRecord(drama: drama, episode: episode, likedAt: Date())
            likedRecords.insert(record, at: 0)
        } else {
            likedRecords.removeAll { $0.id == key }
        }
        saveToStorage()

        // 如果用户已登录官方账号，尝试协同上报官方点赞接口
        if HongguoAccountModel.shared.loggedIn && drama.source == "hongguo" {
            await syncOfficialLike(drama: drama, episodeNumber: episode, liked: newLikedState)
        }

        return newLikedState
    }

    public func removeLike(dramaId: String, episode: Int = 1) {
        let key = "\(dramaId)_\(episode)"
        likedRecords.removeAll { $0.id == key }
        saveToStorage()
    }

    public func clearAll() {
        likedRecords.removeAll()
        saveToStorage()
    }

    private func syncOfficialLike(drama: Drama, episodeNumber: Int, liked: Bool) async {
        guard let data = HongguoAccountModel.shared.socialStates[drama.cleanSourceId],
              let episodeLike = data.episode(episodeNumber) else {
            return
        }
        do {
            try await HongguoAccountModel.shared.setLiked(drama, episode: episodeLike, liked: liked)
        } catch {
            NSLog("🎬 [UserLikeStore] 同步官方点赞失败: %@", error.localizedDescription)
        }
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([UserLikeRecord].self, from: data)
            self.likedRecords = decoded
        } catch {
            NSLog("🎬 [UserLikeStore] 读取点赞记录失败: %@", error.localizedDescription)
        }
    }

    private func saveToStorage() {
        do {
            let encoded = try JSONEncoder().encode(likedRecords)
            UserDefaults.standard.set(encoded, forKey: storageKey)
        } catch {
            NSLog("🎬 [UserLikeStore] 保存点赞记录失败: %@", error.localizedDescription)
        }
    }
}
