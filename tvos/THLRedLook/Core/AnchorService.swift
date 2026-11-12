import Foundation

@MainActor
public final class AnchorService {
    public static let shared = AnchorService()
    public init() {}

    public func fetchAnchors(for drama: Drama) async -> [Anchor] {
        guard let rows = try? await HongguoAccountModel.shared.creators(for: drama) else { return [] }
        return rows.map { Anchor(id: $0.id, name: $0.name, dramas: [drama], following: $0.following,
                                 canFollow: $0.canFollow, relativeType: $0.relativeType) }
    }

    public func fetchAnchorDetail(anchorId: String, dramas: [Drama] = []) async throws -> Anchor {
        try await HongguoAccountModel.shared.creatorProfile(anchorId, dramas: dramas)
    }
}
