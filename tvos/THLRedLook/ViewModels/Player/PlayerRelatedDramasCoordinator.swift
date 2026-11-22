import Foundation

/// 播放器关联推荐短剧协调器
/// 负责在短剧起播后异步加载同类别或热门关联推荐短剧
@MainActor
public final class PlayerRelatedDramasCoordinator {
    private let repository: NativeRepository
    private var loadTask: Task<Void, Never>?

    public init(repository: NativeRepository = .shared) {
        self.repository = repository
    }

    deinit {
        loadTask?.cancel()
    }

    /// 根据当前短剧异步拉取关联推荐
    public func loadRelatedDramas(for drama: Drama, completion: @escaping ([Drama]) -> Void) {
        if drama.id.hasPrefix("test_") {
            let fixtureDramas = [
                Drama(id: "test_rel_1", title: "战神归来当赘婿", cover: "", episodes: 80),
                Drama(id: "test_rel_2", title: "我有九个绝色师姐", cover: "", episodes: 95),
                Drama(id: "test_rel_3", title: "重返1990当首富", cover: "", episodes: 100),
                Drama(id: "test_rel_4", title: "千金归来之真假名媛", cover: "", episodes: 88)
            ]
            completion(fixtureDramas)
            return
        }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let category = drama.category.isEmpty ? "推荐" : drama.category
                let dramas = try await self.repository.loadRecommendations(category: category)
                guard !Task.isCancelled else { return }
                let filtered = dramas.filter { $0.id != drama.id }
                if !filtered.isEmpty {
                    completion(Array(filtered.prefix(12)))
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
            }

            // 备用兜底策略：拉取排行榜热播短剧
            do {
                let hotDramas = try await self.repository.loadRankings(board: "hot", page: 1)
                guard !Task.isCancelled else { return }
                let filtered = hotDramas.filter { $0.id != drama.id }
                completion(Array(filtered.prefix(12)))
            } catch {
                guard !Task.isCancelled else { return }
            }
        }
    }

    public func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }
}
