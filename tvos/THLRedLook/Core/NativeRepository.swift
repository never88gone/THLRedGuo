import Foundation

public final class NativeRepository: DramaSourceProviderProtocol, PlaybackStreamProviderProtocol, DanmakuProviderProtocol {
    public static let shared = NativeRepository()
    static let preloading = NativeRepository(bridge: NativeBridge())
    private let bridge: NativeBridge
    private let playbackBridge = NativeBridge()
    private let danmakuBridge = NativeBridge()
    private let feedBridge = NativeBridge()

    public init(bridge: NativeBridge = .shared) { self.bridge = bridge }

    public func loadVideoFeed(page: Int, session: String) async throws -> VideoFeedPage {
        let result = try await feedBridge.request(action: "feed", payload: ["source": "hongguo", "page": page, "session": session])
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(VideoFeedPage.self, from: data)
    }

    public func loadCategories(source: String) async throws -> [CatalogCategory] {
        let resp = try await bridge.request(action: "categories", payload: ["source": source])
        guard let items = resp["items"] as? [[String: Any]] else { return [CatalogCategory.all] }
        var list: [CatalogCategory] = []
        var seen = Set<String>()
        for item in items {
            let id = item["id"] as? String ?? ""
            let name = item["name"] as? String ?? "全部"
            if seen.insert(id).inserted {
                list.append(CatalogCategory(id: id, name: name))
            }
        }
        return list.isEmpty ? [CatalogCategory.all] : list
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

    public func loadSeriesSeasons(drama: Drama) async throws -> [SeriesSeason] {
        guard drama.source == "hongguo" else { return [] }
        let response = try await bridge.request(action: "seriesSeasons", payload: ["source": drama.source, "id": drama.cleanSourceId])
        let data = try JSONSerialization.data(withJSONObject: response["items"] as? [[String: Any]] ?? [])
        return try JSONDecoder().decode([SeriesSeason].self, from: data)
    }

    public func loadSuggestions(query: String) async throws -> [String] {
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

        let isHongguo = drama.source == "hongguo" || drama.id.hasPrefix("hongguo:") || freshDrama.source == "hongguo" || freshDrama.id.hasPrefix("hongguo:")
        var episodes = [Episode]()
        for (i, row) in chaptersRaw.enumerated() {
            let id = row["id"] as? String ?? "\(drama.id)_\(i + 1)"
            let title = row["title"] as? String ?? "第 \(i + 1) 集"
            let num = row["currentEpisode"] as? Int ?? (row["index"] as? Int) ?? (i + 1)
            let vip = isHongguo ? false : (row["vip"] as? Bool ?? false)
            let raw = try? JSONSerialization.data(withJSONObject: row)
            episodes.append(Episode(id: id, title: title, number: num, vip: vip, raw: raw))
        }

        guard !episodes.isEmpty else {
            throw NSError(domain: "THLRedLook.Detail", code: -1, userInfo: [NSLocalizedDescriptionKey: "站源未返回可播放的分集，请重试"])
        }

        let warning = resp["warning"] as? String ?? ""
        return DramaDetail(drama: freshDrama, episodes: episodes, warning: warning)
    }

    public func loadDetail(drama: Drama, store: LocalStore) async throws -> DramaDetail {
        var target = drama
        if HongguoSeriesIdentity.isRounded(drama) {
            let result = try? await loadCatalog(source: drama.source, query: HongguoSeriesIdentity.baseTitle(drama.title), force: true)
            try Task.checkCancellation()
            if let items = result?.items {
                if let same = items.first(where: { $0.source == drama.source && $0.cleanSourceId == drama.cleanSourceId }) {
                    target = drama.merge(with: same)
                } else if let corrected = HongguoSeriesIdentity.replacements(previous: [drama], fresh: items)[drama.id] {
                    target = HongguoSeriesIdentity.merge(drama, with: corrected)
                }
                await store.refreshDramas(items)
            }
        }
        try Task.checkCancellation()
        let detail = try await loadDetail(drama: target)
        try Task.checkCancellation()
        if HongguoSeriesIdentity.isRounded(detail.drama) {
            let escaped = NSRegularExpression.escapedPattern(for: detail.drama.cleanSourceId)
            let pattern = "(?:/player/\(escaped)/|^\(escaped)[_/])\\d{10,30}(?:[/?#]|$)"
            guard detail.episodes.allSatisfy({ episode in
                let raw = episode.rawChapter
                let value = (raw?["url"] as? String) ?? (raw?["raw"] as? String) ?? episode.id
                return value.range(of: pattern, options: .regularExpression) != nil
            }) else {
                throw SourceAPIError.parseError("旧剧集编号需要更新，请重新搜索该季后重试")
            }
        }
        await store.refreshDramas([detail.drama])
        return detail
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

    public func resolvePlayback(drama: Drama, episode: Episode?, episodeIndex: Int, quality: Int = 0, avoidURL: String) async throws -> PlaybackPlan {
        var payload: [String: Any] = [
            "drama": dramaPayload(drama),
            "index": episodeIndex,
            "quality": quality,
            "sequence": nextPlaybackSequence(),
            "avoidUrl": avoidURL
        ]
        if let chapter = episode?.rawChapter {
            payload["chapter"] = chapter
        }
        let resp = try await playbackBridge.request(action: "resolve", payload: payload)
        let data = try JSONSerialization.data(withJSONObject: resp)
        let plan = try JSONDecoder().decode(PlaybackPlan.self, from: data)
        guard !plan.url.isEmpty else {
            throw NSError(domain: "THLRedLook.Playback", code: -1, userInfo: [NSLocalizedDescriptionKey: "站源没有返回播放地址"])
        }
        return plan
    }

    public func resolvePlayback(drama: Drama, episode: Episode?, episodeIndex: Int, quality: Int = 0) async throws -> PlaybackPlan {
        try await resolvePlayback(drama: drama, episode: episode, episodeIndex: episodeIndex, quality: quality, avoidURL: "")
    }

    public func resolvePlayback(drama: Drama, episodeIndex: Int, quality: Int = 0) async throws -> PlaybackPlan {
        try await resolvePlayback(drama: drama, episode: nil, episodeIndex: episodeIndex, quality: quality)
    }

    public func loadRankingBoards() async throws -> [RankingBoard] {
        let response = try await bridge.request(action: "rankingBoards", payload: [:])
        guard let items = response["items"] as? [[String: Any]] else { return [] }
        let data = try JSONSerialization.data(withJSONObject: items)
        return RankingBoard.filterForTV(try JSONDecoder().decode([RankingBoard].self, from: data))
    }

    public func loadRankings(board: String, page: Int = 1) async throws -> [Drama] {
        try await loadRankingRows(board: board, page: page).map(\.drama)
    }

    public func loadRankingRows(board: String, page: Int = 1) async throws -> [RankedDrama] {
        try await loadRankingPage(board: board, page: page).items
    }

    public func loadRankingPage(board: String, page: Int = 1) async throws -> DiscoveryPage<RankedDrama> {
        let lowerBoard = board.lowercased()
        if !lowerBoard.hasPrefix("hongguo") {
            return DiscoveryPage(items: [], page: page, hasMore: false)
        }

        let resp = try await bridge.request(action: "rankings", payload: [
            "board": board,
            "page": max(1, page)
        ])
        guard let items = resp["items"] as? [[String: Any]] else {
            throw NSError(domain: "THLRedLook.Source", code: -1, userInfo: [NSLocalizedDescriptionKey: "官方榜单数据无效"])
        }
        let data = try JSONSerialization.data(withJSONObject: items)
        
        let rows = try JSONDecoder().decode([RankedDrama].self, from: data).filter {
            $0.drama.source.isEmpty || $0.drama.source.lowercased() == "hongguo"
        }
        return DiscoveryPage(items: rows, page: resp["page"] as? Int ?? page, hasMore: resp["hasMore"] as? Bool ?? false)
    }

    public func loadRecommendations(category: String) async throws -> [Drama] {
        try await loadRecommendationPage(category: category).items
    }

    public func loadRecommendationPage(category: String, page: Int = 1) async throws -> DiscoveryPage<Drama> {
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
        let resp = try await bridge.request(action: "recommendations", payload: ["category": genreKey, "page": max(1, page)])
        guard let items = resp["items"] as? [[String: Any]] else {
            throw NSError(domain: "THLRedLook.Source", code: -1, userInfo: [NSLocalizedDescriptionKey: "官方推荐数据无效"])
        }
        let data = try JSONSerialization.data(withJSONObject: items)
        let dramas = try JSONDecoder().decode([Drama].self, from: data)
        return DiscoveryPage(items: dramas, page: resp["page"] as? Int ?? page, hasMore: resp["hasMore"] as? Bool ?? false)
    }

    public func loadDanmaku(plan: PlaybackPlan, startMs: Int64, durationMs: Int64) async throws -> [DanmakuItem] {
        if plan.local || plan.session.isEmpty || plan.danmakuId.isEmpty { return [] }
        let response = try await danmakuBridge.request(action: "danmaku", payload: [
            "episodeId": plan.danmakuId, "startMs": startMs, "durationMs": durationMs
        ])
        guard response["episodeId"] as? String == plan.danmakuId,
              response["startMs"] as? Int64 == startMs,
              let next = response["nextMs"] as? Int64, next > startMs, next <= durationMs,
              let rows = response["items"] as? [[String: Any]] else {
            throw NSError(domain: "THLRedLook.Danmaku", code: -3, userInfo: [NSLocalizedDescriptionKey: "弹幕分集或时间范围不符"])
        }
        let data = try JSONSerialization.data(withJSONObject: rows)
        return try JSONDecoder().decode([DanmakuItem].self, from: data).filter { $0.timeMs >= startMs && $0.timeMs < next }
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

    public func jsSourceSaveAndLoad(script: String, fileName: String, autoSelect: Bool = true) async throws -> Bool {
        let resp = try await bridge.request(action: "jsSource.saveAndLoad", payload: ["script": script, "fileName": fileName, "autoSelect": autoSelect])
        return resp["ok"] as? Bool ?? false
    }

    public func jsSourceRemove(sourceId: String) async throws -> Bool {
        let resp = try await bridge.request(action: "jsSource.remove", payload: ["source": sourceId])
        return resp["ok"] as? Bool ?? false
    }

    public func jsSourceClearAll() async throws -> Bool {
        let resp = try await bridge.request(action: "jsSource.clearAll", payload: [:])
        return resp["ok"] as? Bool ?? false
    }

    public func jsSourceResetOfficial() async throws -> Bool {
        let resp = try await bridge.request(action: "jsSource.resetOfficial", payload: [:])
        return resp["ok"] as? Bool ?? false
    }

    public func jsSourceScan() async throws -> Int {
        let resp = try await bridge.request(action: "jsSource.scan", payload: [:])
        return resp["count"] as? Int ?? 0
    }
}
