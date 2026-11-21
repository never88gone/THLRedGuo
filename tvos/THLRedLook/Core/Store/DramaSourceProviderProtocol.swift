import Foundation

/// 剧集元数据与列表提供协议
public protocol DramaSourceProviderProtocol: AnyObject {
    func loadCategories(source: String) async throws -> [CatalogCategory]
    func loadCatalog(source: String, category: String, page: Int, query: String, force: Bool) async throws -> (items: [Drama], hasMore: Bool, page: Int)
    func loadSuggestions(query: String) async throws -> [String]
    func loadDetail(drama: Drama) async throws -> DramaDetail
    func loadRankingBoards() async throws -> [RankingBoard]
    func loadRankings(board: String, page: Int) async throws -> [Drama]
    func loadRecommendations(category: String) async throws -> [Drama]
}

public extension DramaSourceProviderProtocol {
    func loadRankings(board: String) async throws -> [Drama] {
        try await loadRankings(board: board, page: 1)
    }
}
