import Foundation

public struct EpisodeWrapper: Identifiable {
    public let id: Int
    public var index: Int { id }
    public init(index: Int) { self.id = index }
}
