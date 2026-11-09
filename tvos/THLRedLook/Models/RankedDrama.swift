import Foundation

public struct RankedDrama: Decodable {
    public let rank: Int
    public let drama: Drama
    public let metric: String

    public init(rank: Int, drama: Drama, metric: String = "") {
        self.rank = rank
        self.drama = drama
        self.metric = metric
    }
}
