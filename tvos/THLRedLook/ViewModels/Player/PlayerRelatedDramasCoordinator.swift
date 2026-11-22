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
