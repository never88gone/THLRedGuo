import Foundation
import Combine

public struct SeasonItem: Identifiable, Hashable {
    public var id: String { drama.id }
    public let drama: Drama
    public let seasonNumber: Int
    public let title: String
    public let isCurrent: Bool

    public init(drama: Drama, seasonNumber: Int, title: String, isCurrent: Bool) {
        self.drama = drama
        self.seasonNumber = seasonNumber
        self.title = title
        self.isCurrent = isCurrent
    }
}

@MainActor
public final class DetailViewModel: ObservableObject {
    @Published public var detail: DramaDetail?
    @Published public var selectedChunkIndex: Int = 0
    @Published public var isLoading = false
    @Published public var followState: FollowState = .none
    @Published public var lastWatchEntry: WatchEntry?
    @Published public var errorMessage: String?
    @Published public var relatedSeasons: [Drama] = []
    @Published public var seasonItems: [SeasonItem] = []

    public let drama: Drama
    private let repository: NativeRepository
    private let store: LocalStore
    private let downloadService: DownloadService

    public init(
        drama: Drama,
        repository: NativeRepository = .shared,
        store: LocalStore = .shared,
        downloadService: DownloadService = .shared
    ) {
        self.drama = drama
        self.repository = repository
        self.store = store
        self.downloadService = downloadService
        self.followState = store.followState(for: drama.id)
        self.lastWatchEntry = store.getWatchEntry(dramaId: drama.id)
        let total = max(20, drama.episodes)
        let eps = (1...total).map { Episode(id: "\(drama.id)_\($0)", title: "第 \($0) 集", number: $0) }
        self.detail = DramaDetail(drama: drama, episodes: eps, warning: "")
    }

    public func loadDetail() async {
        if detail == nil {
            isLoading = true
        }
        errorMessage = nil
        if drama.id.starts(with: "test_") {
            isLoading = false
            return
        }
        do {
            let loaded = try await repository.loadDetail(drama: drama)
            self.detail = loaded
            // 如果有历史记录，自动切换到对应集所属的 chunk
            if let entry = lastWatchEntry, !loaded.episodeChunks.isEmpty {
                for (index, chunk) in loaded.episodeChunks.enumerated() {
                    if chunk.episodes.contains(where: { $0.number == entry.episode }) {
                        selectedChunkIndex = index
                        break
                    }
                }
            }
            await loadSeasons()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func parseSeasonNumber(title: String, baseName: String) -> Int {
        let suffix = title.replacingOccurrences(of: baseName, with: "").trimmingCharacters(in: .whitespaces)
        let cnMap: [Character: Int] = ["一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        if let match = suffix.range(of: "第\\s*([0-9零一二两三四五六七八九十百]+)\\s*[季部]", options: .regularExpression) {
            let sub = String(suffix[match])
            if let numMatch = sub.range(of: "[0-9]+", options: .regularExpression), let n = Int(sub[numMatch]) {
                return n
            }
            for (ch, val) in cnMap {
                if sub.contains(ch) { return val }
            }
        }
        if let numMatch = suffix.range(of: "[0-9]+", options: .regularExpression), let n = Int(suffix[numMatch]) {
            return n
        }
        return 1
    }

    private func loadSeasons() async {
        let pattern = "第\\s*[0-9零一二两三四五六七八九十百]+\\s*[季部].*$"
        var baseName = drama.title.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if baseName.isEmpty { baseName = drama.title }

        let targetSource = drama.source.lowercased()
        do {
            let result = try await repository.loadCatalog(source: drama.source, query: baseName)
            var candidates = result.items.filter {
                $0.source.lowercased() == targetSource && $0.title.contains(baseName)
            }
            if !candidates.contains(where: { $0.id == drama.id }) {
                candidates.append(drama)
            }

            if candidates.count <= 1 {
                self.seasonItems = []
                self.relatedSeasons = []
                return
            }

            let parsed = candidates.map { d -> (drama: Drama, seasonNum: Int) in
                let sNum = self.parseSeasonNumber(title: d.title, baseName: baseName)
                return (d, sNum)
            }.sorted { a, b in
                if a.seasonNum != b.seasonNum {
                    return a.seasonNum < b.seasonNum
                }
                return a.drama.title < b.drama.title
            }

            var items: [SeasonItem] = []
            var seenIds = Set<String>()
            for (idx, entry) in parsed.enumerated() {
                if seenIds.contains(entry.drama.id) { continue }
                seenIds.insert(entry.drama.id)
                let actualSeason = entry.seasonNum > 0 ? entry.seasonNum : (idx + 1)
                let isCurr = entry.drama.id == drama.id
                let seasonTitle = "第 \(actualSeason) 季"
                items.append(SeasonItem(
                    drama: entry.drama,
                    seasonNumber: actualSeason,
                    title: seasonTitle,
                    isCurrent: isCurr
                ))
            }

            self.seasonItems = items
            self.relatedSeasons = items.filter { !$0.isCurrent }.map { $0.drama }
        } catch {
            NSLog("🎬 [DetailVM] 加载相关季数失败: %@", error.localizedDescription)
        }
    }

    public func toggleFollowState() {
        let next: FollowState
        switch followState {
        case .none: next = .wishlist
        case .wishlist: next = .watching
        case .watching: next = .watched
        case .watched: next = .none
        case .updated: next = .watching
        }
        followState = next
        store.setFollowState(drama: drama, state: next)
    }

    public func downloadAllEpisodes(quality: Int = 1080) {
        guard let episodes = detail?.episodes, !episodes.isEmpty else { return }
        downloadService.enqueue(drama: drama, episodes: episodes, quality: quality)
    }

    public func downloadChunk(chunk: EpisodeChunk, quality: Int = 1080) {
        downloadService.enqueue(drama: drama, episodes: chunk.episodes, quality: quality)
    }
}
