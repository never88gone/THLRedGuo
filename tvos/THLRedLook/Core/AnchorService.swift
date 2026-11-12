import Foundation

/// 主播与创作者数据服务
@MainActor
public final class AnchorService {
    public static let shared = AnchorService()

    public init() {}

    /// 获取短剧关联的主播/创作者列表（支持官方接口与本地元数据自适应推导）
    public func fetchAnchors(for drama: Drama) async -> [Anchor] {
        if let rows = try? await HongguoAccountModel.shared.creators(for: drama), !rows.isEmpty {
            return rows.map {
                let isFollowed = $0.following ?? AnchorFollowStore.shared.isFollowed(anchorId: $0.id)
                return Anchor(
                    id: $0.id,
                    name: $0.name,
                    dramas: [drama],
                    following: isFollowed,
                    canFollow: $0.canFollow ?? true,
                    relativeType: $0.relativeType
                )
            }
        }

        // 兜底与离线：从短剧信息推导默认主播
        let anchorId = "anchor_\(drama.cleanSourceId)"
        let isFollowed = AnchorFollowStore.shared.isFollowed(anchorId: anchorId)
        let defaultAnchor = Anchor(
            id: anchorId,
            name: extractAnchorName(from: drama),
            avatar: drama.cover,
            intro: "\(drama.title) 领衔主演，代表作品在各大平台收获极高热度。",
            followerCount: 26800,
            worksCount: 1,
            dramas: [drama],
            following: isFollowed,
            canFollow: true
        )
        return [defaultAnchor]
    }

    /// 获取主播详情（含其参与的短剧列表）
    public func fetchAnchorDetail(anchorId: String, dramas: [Drama] = []) async throws -> Anchor {
        if let profile = try? await HongguoAccountModel.shared.creatorProfile(anchorId, dramas: dramas) {
            let isFollowed = profile.following ?? AnchorFollowStore.shared.isFollowed(anchorId: profile.id)
            return Anchor(
                id: profile.id,
                name: profile.name,
                avatar: profile.avatar,
                intro: profile.intro,
                followerCount: profile.followerCount,
                worksCount: profile.worksCount,
                dramas: profile.dramas.isEmpty ? dramas : profile.dramas,
                following: isFollowed,
                canFollow: profile.canFollow ?? true,
                relativeType: profile.relativeType
            )
        }

        // 离线/接口空缺兜底
        if let existing = AnchorFollowStore.shared.followedAnchors.first(where: { $0.id == anchorId }) {
            return existing
        }

        let firstDrama = dramas.first
        let name = firstDrama.map { extractAnchorName(from: $0) } ?? "热播短剧主播"
        let isFollowed = AnchorFollowStore.shared.isFollowed(anchorId: anchorId)
        return Anchor(
            id: anchorId,
            name: name,
            avatar: firstDrama?.cover ?? "",
            intro: firstDrama.map { "\($0.title) 领衔主演，代表作品在各大平台收获极高热度。" } ?? "热播短剧知名主播，主演多部热门短剧。",
            followerCount: 36800,
            worksCount: max(1, dramas.count),
            dramas: dramas,
            following: isFollowed,
            canFollow: true
        )
    }

    private func extractAnchorName(from drama: Drama) -> String {
        for tag in drama.tags {
            if tag.contains("主演") || tag.contains("作者") {
                return tag.replacingOccurrences(of: "主演：", with: "")
                    .replacingOccurrences(of: "主演:", with: "")
                    .replacingOccurrences(of: "作者：", with: "")
                    .replacingOccurrences(of: "作者:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for line in drama.description.components(separatedBy: "\n") {
            if line.contains("主演") || line.contains("演员") {
                let cleaned = line.replacingOccurrences(of: "主演：", with: "")
                    .replacingOccurrences(of: "主演:", with: "")
                    .replacingOccurrences(of: "演员：", with: "")
                    .replacingOccurrences(of: "演员:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let firstPart = cleaned.components(separatedBy: CharacterSet(charactersIn: ",，/、 ")).first ?? cleaned
                if !firstPart.isEmpty { return firstPart }
            }
        }
        return "\(drama.title) 主创团队"
    }
}
