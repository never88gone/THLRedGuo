import Foundation

public final class NativeRepository: DramaSourceProviderProtocol, PlaybackStreamProviderProtocol, DanmakuProviderProtocol {
    public static let shared = NativeRepository()
    private let bridge = NativeBridge.shared

    public init() {}

    public func loadCategories(source: String) async throws -> [CatalogCategory] {
        let resp = try await bridge.request(action: "categories", payload: ["source": source])
        guard let items = resp["items"] as? [[String: Any]] else { return [CatalogCategory.all] }
        var list = [CatalogCategory.all]
        for item in items {
            let id = item["id"] as? String ?? ""
            let name = item["name"] as? String ?? "全部"
            if !id.isEmpty {
                list.append(CatalogCategory(id: id, name: name))
            }
        }
        return list
    }

    public func loadCatalog(
        source: String,
        category: String = "",
        page: Int = 1,
        query: String = "",
        force: Bool = false
    ) async throws -> (items: [Drama], hasMore: Bool, page: Int) {
        let payload: [String: Any] = [
            "source": source,
            "category": category,
            "page": page,
            "query": query,
            "force": force
        ]
        let resp = try await bridge.request(action: "catalog", payload: payload)
        guard let rawItems = resp["items"] as? [[String: Any]] else {
            return ([], false, page)
        }

        let data = try JSONSerialization.data(withJSONObject: rawItems)
        let dramas = try JSONDecoder().decode([Drama].self, from: data)
        let hasMore = resp["hasMore"] as? Bool ?? false
        let returnedPage = resp["page"] as? Int ?? page
        return (dramas, hasMore, returnedPage)
    }

    public func loadSuggestions(query: String) async throws -> [String] {
        guard !query.isEmpty else { return [] }
        let resp = try await bridge.request(action: "suggestions", payload: ["query": query])
        return resp["items"] as? [String] ?? []
    }

    public func loadDetail(drama: Drama) async throws -> DramaDetail {
        let resp = try await bridge.request(action: "detail", payload: ["drama": dramaPayload(drama)])
        let chaptersRaw = (resp["chapters"] as? [[String: Any]]) ?? (resp["episodes"] as? [[String: Any]]) ?? []

        var freshDrama = drama
        if let dict = resp["drama"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let decoded = try? JSONDecoder().decode(Drama.self, from: data) {
            freshDrama = drama.merge(with: decoded)
        }

        var episodes = [Episode]()
        for (i, row) in chaptersRaw.enumerated() {
            let id = row["id"] as? String ?? "\(drama.id)_\(i + 1)"
            let title = row["title"] as? String ?? "第 \(i + 1) 集"
            let num = row["currentEpisode"] as? Int ?? (row["index"] as? Int) ?? (i + 1)
            let vip = row["vip"] as? Bool ?? false
            let raw = try? JSONSerialization.data(withJSONObject: row)
            episodes.append(Episode(id: id, title: title, number: num, vip: vip, raw: raw))
        }

        if episodes.isEmpty {
            let total = max(1, freshDrama.episodes > 0 ? freshDrama.episodes : 20)
            for i in 1...total {
                episodes.append(Episode(id: "\(freshDrama.id)_\(i)", title: "第 \(i) 集", number: i))
            }
        }

        let warning = resp["warning"] as? String ?? ""
        return DramaDetail(drama: freshDrama, episodes: episodes, warning: warning)
    }

    private var playbackSequence = Int64(Date().timeIntervalSince1970 * 1_000_000)
    private let sequenceLock = NSLock()

    private func nextPlaybackSequence() -> Int64 {
        sequenceLock.lock()
        defer { sequenceLock.unlock() }
        playbackSequence += 1
        return playbackSequence
    }

    private func dramaPayload(_ drama: Drama) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(drama),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ["id": drama.id, "source": drama.source, "title": drama.title]
        }
        return dict
    }

    public func resolvePlayback(drama: Drama, episode: Episode?, episodeIndex: Int, quality: Int = 0) async throws -> PlaybackPlan {
        var payload: [String: Any] = [
            "drama": dramaPayload(drama),
            "index": episodeIndex,
            "quality": quality,
            "sequence": nextPlaybackSequence()
        ]
        if let chapter = episode?.rawChapter {
            payload["chapter"] = chapter
        }
        let resp = try await bridge.request(action: "resolve", payload: payload)
        let data = try JSONSerialization.data(withJSONObject: resp)
        let plan = try JSONDecoder().decode(PlaybackPlan.self, from: data)
        guard !plan.url.isEmpty else {
            throw NSError(domain: "THLRedLook.Playback", code: -1, userInfo: [NSLocalizedDescriptionKey: "站源没有返回播放地址"])
        }
        return plan
    }

    public func resolvePlayback(drama: Drama, episodeIndex: Int, quality: Int = 0) async throws -> PlaybackPlan {
        try await resolvePlayback(drama: drama, episode: nil, episodeIndex: episodeIndex, quality: quality)
    }

    public func loadRankingBoards() async throws -> [RankingBoard] {
        do {
            let resp = try await bridge.request(action: "rankingBoards", payload: [:])
            if let items = resp["items"] as? [[String: Any]] {
                let data = try JSONSerialization.data(withJSONObject: items)
                let allBoards = (try? JSONDecoder().decode([RankingBoard].self, from: data)) ?? []
                // tvOS 平台安全防护：严格过滤 18 禁/黄果等不适合客厅大屏的榜单
                let boards = RankingBoard.filterForTV(allBoards)
                if !boards.isEmpty {
                    return boards
                }
            }
        } catch {
            // 失败时回退到默认有效榜单
        }
        return RankingBoard.filterForTV(RankingBoard.defaults)
    }

    public func loadRankings(board: String, page: Int = 1) async throws -> [Drama] {
        let lowerBoard = board.lowercased()
        let blockedTokens = ["huangguo", "huangju", "guipian", "sorani", "cloudfront"]
        if blockedTokens.contains(where: { lowerBoard.contains($0) }) {
            return []
        }

        let resp = try await bridge.request(action: "rankings", payload: [
            "board": board,
            "page": max(1, page)
        ])
        guard let items = resp["items"] as? [[String: Any]] else { return [] }
        let data = try JSONSerialization.data(withJSONObject: items)
        
        func sanitize(_ list: [Drama]) -> [Drama] {
            list.filter { drama in
                let src = drama.source.lowercased()
                return !blockedTokens.contains(where: { src.contains($0) })
            }
        }

        // 尝试从嵌套结构 [{ "rank": 1, "drama": Drama, ... }] 中提取真实剧集
        struct RankingRowResponse: Decodable {
            let rank: Int?
            let drama: Drama?
            let metric: String?
        }
        if let rows = try? JSONDecoder().decode([RankingRowResponse].self, from: data) {
            let dramas = rows.compactMap { $0.drama }
            if !dramas.isEmpty {
                return sanitize(dramas)
            }
        }
        
        // 兜底直接解析剧集列表
        let rawDramas = (try? JSONDecoder().decode([Drama].self, from: data)) ?? []
        return sanitize(rawDramas)
    }

    public func loadRecommendations(category: String) async throws -> [Drama] {
        // 将界面分类文案映射为 CatPawOpen Spider 真实分类键值
        let genreKey: String
        switch category {
        case "真人剧", "short_play", "real-drama", "全部":
            genreKey = "real-drama"
        case "漫剧", "comic_series", "comic-drama":
            genreKey = "comic-drama"
        case "AI 剧", "AI剧", "ai_series", "ai-drama":
            genreKey = "ai-drama"
        default:
            genreKey = "real-drama"
        }
        let resp = try await bridge.request(action: "recommendations", payload: ["category": genreKey])
        guard let items = resp["items"] as? [[String: Any]] else { return [] }
        let data = try JSONSerialization.data(withJSONObject: items)
        return (try? JSONDecoder().decode([Drama].self, from: data)) ?? []
    }

    public func loadDanmaku(plan: PlaybackPlan, startMs: Int64, durationMs: Int64) async throws -> [DanmakuItem] {
        if plan.local || plan.session.isEmpty || plan.danmakuId.isEmpty {
            return []
        }
        let resp = try? await bridge.request(
            action: "danmaku",
            payload: [
                "playbackSession": plan.session,
                "startMs": startMs,
                "durationMs": durationMs
            ]
        )
        guard let resp = resp, let items = resp["items"] as? [[String: Any]] else {
            return []
        }
        let data = try JSONSerialization.data(withJSONObject: items)
        return (try? JSONDecoder().decode([DanmakuItem].self, from: data)) ?? []
    }

    public func storage() async throws -> [String: Any] {
        return try await bridge.request(action: "storage", payload: [:])
    }

    // MARK: - JS Plugins
    public func jsSourceList() async throws -> [[String: Any]] {
        let resp = try await bridge.request(action: "jsSource.list", payload: [:])
        return resp["items"] as? [[String: Any]] ?? []
    }

    public func jsSourceSetActive(sourceId: String) async throws -> Bool {
        let resp = try await bridge.request(action: "jsSource.setActive", payload: ["source": sourceId])
        return resp["ok"] as? Bool ?? false
    }

    public func jsSourceGetActive() async throws -> String {
        let resp = try await bridge.request(action: "jsSource.getActive", payload: [:])
        return resp["active"] as? String ?? ""
    }

    public func jsSourceSaveAndLoad(script: String, fileName: String) async throws -> Bool {
        let resp = try await bridge.request(action: "jsSource.saveAndLoad", payload: ["script": script, "fileName": fileName])
        return resp["ok"] as? Bool ?? false
    }

    public func jsSourceRemove(sourceId: String) async throws -> Bool {
        let resp = try await bridge.request(action: "jsSource.remove", payload: ["source": sourceId])
        return resp["ok"] as? Bool ?? false
    }

    public func jsSourceScan() async throws -> Int {
        let resp = try await bridge.request(action: "jsSource.scan", payload: [:])
        return resp["count"] as? Int ?? 0
    }
}
