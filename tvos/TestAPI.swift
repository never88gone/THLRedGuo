import Foundation
@testable import THLRedLook

Task {
    do {
        let repo = NativeRepository()
        let boards = try await repo.loadRankingBoards()
        print("Boards:", boards.map { $0.name })
        if let first = boards.first {
            let rankings = try await repo.loadRankings(board: first.id)
            print("Rankings count:", rankings.count)
        }
        let recs = try await repo.loadRecommendations(category: "short_play")
        print("Recs count:", recs.count)
        exit(0)
    } catch {
        print("Error:", error)
        exit(1)
    }
}
RunLoop.main.run()
