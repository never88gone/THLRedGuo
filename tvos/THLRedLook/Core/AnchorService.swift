import Foundation

/// 主播与创作者数据服务
@MainActor
public final class AnchorService {
    public static let shared = AnchorService()

    public init() {}

    /// 获取短剧关联的主播/创作者列表
    public func fetchAnchors(for drama: Drama) async -> [Anchor] {
        var result: [Anchor] = []

        // 1. 如果登录了官方账号或本地已有社交快照，优先尝试从 HongguoCreator 提取
        if let data = HongguoAccountModel.shared.socialStates[drama.cleanSourceId], !data.creators.isEmpty {
            for c in data.creators {
                let anchor = Anchor(
                    id: c.id,
                    name: c.name,
                    avatar: "",
                    intro: c.relativeType == 3 ? "短剧作者 / 主创" : "短剧主演 / 主播",
                    followerCount: 26800,
                    worksCount: 1,
                    dramas: [drama]
                )
                result.append(anchor)
            }
        }

        // 2. 如果接口没有返回创作者（或用户未登录），从短剧元数据中构建主播
        if result.isEmpty {
            let anchorName = extractAnchorName(from: drama)
            let defaultAnchor = Anchor(
                id: "anchor_\(drama.cleanSourceId)",
                name: anchorName,
                avatar: drama.cover,
                intro: "\(drama.title) 主演／当红短剧主播，深受观众喜爱。",
                followerCount: 58600,
                worksCount: 1,
                dramas: [drama]
            )
            result.append(defaultAnchor)
        }

        return result
    }

    /// 获取主播详情（含其参与的短剧列表）
    public func fetchAnchorDetail(anchorId: String, currentDrama: Drama? = nil) async -> Anchor {
        // 先检查是否已经在关注列表中
        if let existing = AnchorFollowStore.shared.followedAnchors.first(where: { $0.id == anchorId }) {
            if let current = currentDrama, !existing.dramas.contains(where: { $0.id == current.id }) {
                var updatedDramas = existing.dramas
                updatedDramas.append(current)
                return Anchor(
                    id: existing.id,
                    name: existing.name,
                    avatar: existing.avatar,
                    intro: existing.intro,
                    followerCount: existing.followerCount,
                    worksCount: updatedDramas.count,
                    dramas: updatedDramas
                )
            }
            return existing
        }

        if let drama = currentDrama {
            let name = extractAnchorName(from: drama)
            return Anchor(
                id: anchorId,
                name: name,
                avatar: drama.cover,
                intro: "\(drama.title) 领衔主演，代表作品在各大平台收获极高热度。",
                followerCount: 68900,
                worksCount: 1,
                dramas: [drama]
            )
        }

        return Anchor(
            id: anchorId,
            name: "热播短剧主播",
            avatar: "",
            intro: "热播短剧主播，代表作品在各大平台收获极高热度。",
            followerCount: 32000,
            worksCount: 0,
            dramas: []
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
