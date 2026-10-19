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

    @Published public var drama: Drama
    private let repository: NativeRepository
    private let store: LocalStore
    private var loadGeneration = 0
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
        if drama.id.starts(with: "test_") {
            let total = max(20, drama.episodes)
            let episodes = (1...total).map { Episode(id: "\(drama.id)_\($0)", title: "第 \($0) 集", number: $0) }
            self.detail = DramaDetail(drama: drama, episodes: episodes, warning: "")
        }
    }

    public func refreshWatchHistory() {
        self.lastWatchEntry = store.getWatchEntry(dramaId: drama.id)
    }

    public func switchToDrama(_ newDrama: Drama) async {
        guard newDrama.id != drama.id else { return }
        self.drama = newDrama
        self.followState = store.followState(for: newDrama.id)
        self.lastWatchEntry = store.getWatchEntry(dramaId: newDrama.id)
        self.selectedChunkIndex = 0
        if !self.seasonItems.isEmpty {
            self.seasonItems = self.seasonItems.map {
                SeasonItem(drama: $0.drama, seasonNumber: $0.seasonNumber, title: $0.title, isCurrent: $0.drama.id == newDrama.id)
            }
        }
        self.detail = nil
        self.isLoading = true
        self.errorMessage = nil
        await loadDetail()
    }

    public func loadDetail() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedDrama = drama
        let hasRealEpisodes = detail?.episodes.contains(where: { $0.raw != nil }) == true
        if !hasRealEpisodes {
            isLoading = true
        }
        errorMessage = nil
        if drama.id.starts(with: "test_") {
            isLoading = false
            return
        }
        do {
            await JSSourceService.shared.initialize()
            let loaded = try await repository.loadDetail(drama: requestedDrama, store: store)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            self.detail = loaded
            self.drama = loaded.drama
            self.followState = store.followState(for: loaded.drama.id)
            self.lastWatchEntry = store.getWatchEntry(dramaId: loaded.drama.id)
            // 如果有历史记录，自动切换到对应集所属的 chunk
            if let entry = lastWatchEntry, !loaded.episodeChunks.isEmpty {
                for (index, chunk) in loaded.episodeChunks.enumerated() {
                    if chunk.episodes.contains(where: { $0.number == entry.episode }) {
                        selectedChunkIndex = index
                        break
                    }
                }
            }
            await loadSeasons(generation: generation)
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        guard generation == loadGeneration else { return }
        isLoading = false
    }

    private func parseSeasonNumber(title: String, baseName: String) -> Int? {
        let suffix = title.replacingOccurrences(of: baseName, with: "").trimmingCharacters(in: .whitespaces)
        let searchTexts = [suffix, title]
        let digitMap: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        
        for text in searchTexts {
            if let match = text.range(of: "第\\s*([0-9零一二两三四五六七八九十]+)\\s*[季部]", options: .regularExpression) {
                let sub = String(text[match])
                if let numMatch = sub.range(of: "[0-9]+", options: .regularExpression), let n = Int(sub[numMatch]) {
                    return n
                }
                if sub.contains("十") {
                    let parts = sub.components(separatedBy: "十")
                    let tensPart = parts.first ?? ""
                    let unitsPart = parts.count > 1 ? parts[1] : ""
                    var tens = 1
                    for (ch, val) in digitMap {
                        if tensPart.contains(ch) { tens = val; break }
                    }
                    var units = 0
                    for (ch, val) in digitMap {
                        if unitsPart.contains(ch) { units = val; break }
                    }
                    return tens * 10 + units
                }
                for (ch, val) in digitMap {
                    if sub.contains(ch) { return val }
                }
            }
        }
        
        if let match = suffix.range(of: "([0-9]+)$", options: .regularExpression), let n = Int(suffix[match]) {
            return n
        }
        return nil
    }

    private func loadSeasons(generation: Int) async {
        let pattern = "(?:第\\s*[0-9零一二两三四五六七八九十百]+\\s*[季部]|\\s*[0-9零一二两三四五六七八九十]+).*$"
        var baseName = drama.title.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if baseName.isEmpty { baseName = drama.title }

        let targetSource = drama.source.lowercased()
        do {
            let result = try await repository.loadCatalog(source: drama.source, query: baseName)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            store.refreshDramas(result.items)
            self.followState = store.followState(for: drama.id)
            self.lastWatchEntry = store.getWatchEntry(dramaId: drama.id)
            var candidates = result.items.filter {
                $0.source.lowercased() == targetSource &&
                !$0.cover.isEmpty &&
                $0.title.contains(baseName)
            }
            if let existingIndex = candidates.firstIndex(where: { $0.id == drama.id }) {
                candidates[existingIndex] = drama.merge(with: candidates[existingIndex])
            } else {
                candidates.append(drama)
            }

            if candidates.count <= 1 {
                if self.seasonItems.isEmpty {
                    self.seasonItems = []
                    self.relatedSeasons = []
                }
                return
            }

            var rawList = candidates.map { d -> (drama: Drama, seasonNum: Int?) in
                let sNum = self.parseSeasonNumber(title: d.title, baseName: baseName)
                return (d, sNum)
            }

            var seenIds = Set<String>()
            rawList = rawList.filter {
                if seenIds.contains($0.drama.id) { return false }
                seenIds.insert($0.drama.id)
                return true
            }

            struct ParsedEntry {
                let drama: Drama
                let mainSeasonNum: Int?
                let customTitle: String?
            }

            var parsedList: [ParsedEntry] = []
            for entry in rawList {
                let d = entry.drama
                let suffix = d.title.replacingOccurrences(of: baseName, with: "").trimmingCharacters(in: .whitespaces)
                let sNum = self.parseSeasonNumber(title: d.title, baseName: baseName)
                
                let hasSubSeparator = suffix.contains("：") || suffix.contains(":") || suffix.contains("-") || suffix.contains("—") || suffix.contains("，") || suffix.contains(",")
                if hasSubSeparator {
                    let cleaned = suffix.replacingOccurrences(of: "^[：:\\-\\—，,\\s]+", with: "", options: .regularExpression)
                    parsedList.append(ParsedEntry(drama: d, mainSeasonNum: nil, customTitle: cleaned.isEmpty ? nil : cleaned))
                } else if let num = sNum {
                    parsedList.append(ParsedEntry(drama: d, mainSeasonNum: num, customTitle: nil))
                } else {
                    parsedList.append(ParsedEntry(drama: d, mainSeasonNum: nil, customTitle: nil))
                }
            }

            let mainSeasons = parsedList.filter { $0.mainSeasonNum != nil }.sorted { $0.mainSeasonNum! < $1.mainSeasonNum! }
            let unnumbered = parsedList.filter { $0.mainSeasonNum == nil && $0.customTitle == nil }
            let spinOffs = parsedList.filter { $0.customTitle != nil }.sorted { $0.drama.title < $1.drama.title }

            var items: [SeasonItem] = []
            if mainSeasons.isEmpty {
                for (idx, entry) in unnumbered.enumerated() {
                    let s = idx + 1
                    items.append(SeasonItem(
                        drama: entry.drama,
                        seasonNumber: s,
                        title: "第 \(s) 季",
                        isCurrent: entry.drama.id == drama.id
                    ))
                }
            } else {
                for entry in mainSeasons {
                    let s = entry.mainSeasonNum!
                    items.append(SeasonItem(
                        drama: entry.drama,
                        seasonNumber: s,
                        title: "第 \(s) 季",
                        isCurrent: entry.drama.id == drama.id
                    ))
                }
                for (idx, entry) in unnumbered.enumerated() {
                    let title = unnumbered.count == 1 ? "经典版" : "版本 \(idx + 1)"
                    items.append(SeasonItem(
                        drama: entry.drama,
                        seasonNumber: 100 + idx,
                        title: title,
                        isCurrent: entry.drama.id == drama.id
                    ))
                }
            }

            for (idx, entry) in spinOffs.enumerated() {
                let title = entry.customTitle ?? "番外 \(idx + 1)"
                items.append(SeasonItem(
                    drama: entry.drama,
                    seasonNumber: 200 + idx,
                    title: title,
                    isCurrent: entry.drama.id == drama.id
                ))
            }

            self.seasonItems = items
            self.relatedSeasons = items.filter { !$0.isCurrent }.map { $0.drama }
        } catch {
            NSLog("🎬 [DetailVM] 加载相关季数失败: %@", error.localizedDescription)
        }
    }

    public func toggleFavorite() {
        setFollowState(followState == .none ? .wishlist : .none)
    }

    public func setFollowState(_ state: FollowState) {
        followState = state
        store.setFollowState(drama: drama, state: state)
    }

    public func downloadAllEpisodes(quality: Int = 1080) {
        guard let episodes = detail?.episodes, !episodes.isEmpty else { return }
        downloadService.enqueue(drama: drama, episodes: episodes, quality: quality)
    }

    public func downloadChunk(chunk: EpisodeChunk, quality: Int = 1080) {
        downloadService.enqueue(drama: drama, episodes: chunk.episodes, quality: quality)
    }
}
