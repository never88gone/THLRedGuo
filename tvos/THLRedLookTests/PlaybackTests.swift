import XCTest
import AVFoundation
import UIKit
@testable import THLRedLook

@MainActor
final class PlaybackTests: XCTestCase {
    private let repository = NativeRepository.shared
    private var videoView: UIView?
    private var videoLayer: AVPlayerLayer?

    override func tearDown() {
        videoLayer?.player = nil
        videoLayer?.removeFromSuperlayer()
        videoView?.removeFromSuperview()
        videoLayer = nil
        videoView = nil
        super.tearDown()
    }

    private func live() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HONGGUO_LIVE"] == "1")
        XCTAssertEqual(ProcessInfo.processInfo.environment["DISABLE_REMOTE_IMAGES"], "1")
    }

    private func wait(seconds: Double = 150, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(condition(), "Timed out waiting for native playback")
        guard condition() else { throw NSError(domain: "PlaybackTests", code: 1) }
    }

    private func attach(_ player: AVPlayer) throws {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let view = UIView(frame: CGRect(x: 100, y: 100, width: 640, height: 360))
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        try XCTUnwrap(window).addSubview(view)
        videoLayer?.removeFromSuperlayer()
        videoView?.removeFromSuperview()
        videoLayer = layer
        videoView = view
    }

    private func ready(_ model: PlayerViewModel) async throws {
        try await wait { model.player != nil && !model.isLoading && model.duration > 1 && model.currentTime > 0.5 }
        let player = try XCTUnwrap(model.player)
        try attach(player)
        try await wait(seconds: 20) { self.videoLayer?.isReadyForDisplay == true }
        let item = try XCTUnwrap(player.currentItem)
        let video = try await item.asset.loadTracks(withMediaType: .video)
        let audio = try await item.asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(video.isEmpty)
        XCTAssertFalse(audio.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    private func detail(_ id: String) async throws -> DramaDetail {
        try await repository.loadDetail(drama: Drama(id: "hongguo:" + id, source: "hongguo", sourceId: id, title: "原生播放验证"))
    }

    private func model(_ detail: DramaDetail) -> PlayerViewModel {
        let result = PlayerViewModel(drama: detail.drama, allEpisodes: detail.episodes, repository: repository)
        result.danmakuEnabled = false
        return result
    }

    func testLiveDanmakuWindowsAndPlaybackClock() async throws {
        try live()
        await JSSourceService.shared.initialize()
        let data = try await detail("7694896136963755032")
        let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository)
        model.danmakuEnabled = true
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        try await ready(model)
        let plan = try XCTUnwrap(model.plan)
        XCTAssertTrue(plan.danmakuId.hasPrefix("hongguo:7694896136963755032:"))
        var seen = Set<String>()
        for start in [Int64(0), 30000, 60000] {
            let items = try await repository.loadDanmaku(plan: plan, startMs: start, durationMs: 120000)
            XCTAssertFalse(items.isEmpty)
            for item in items {
                XCTAssertGreaterThanOrEqual(item.timeMs, start)
                XCTAssertLessThan(item.timeMs, start + 30000)
                XCTAssertTrue(seen.insert(item.id).inserted)
            }
            print("THL_TV_DANMAKU startMs=\(start) count=\(items.count) exactEpisode=true")
        }
        model.seekBy(seconds: 36 - model.currentTime)
        try await wait(seconds: 20) { model.activeDanmakus.contains { $0.timeMs >= 30000 } }
        XCTAssertTrue(model.activeDanmakus.allSatisfy { Double($0.timeMs) <= model.currentTime * 1000 })
        model.togglePlayPause()
        let paused = model.currentTime
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(model.currentTime, paused, accuracy: 0.15)
        model.toggleDanmaku()
        XCTAssertTrue(model.activeDanmakus.isEmpty)
        model.toggleDanmaku()
        try await wait(seconds: 20) { !model.activeDanmakus.isEmpty }
        model.onDisappear()
        XCTAssertTrue(model.activeDanmakus.isEmpty)
        print("THL_TV_DANMAKU_CLOCK seek=true pause=true toggle=true exit=true")
    }

    func testLivePauseQualityInterruptionAndHistory() async throws {
        try live()
        await JSSourceService.shared.initialize()
        let suite = "THLRedLook.QA.Playback." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LocalStore(defaults: defaults)
        let data = try await detail("7694896136963755032")
        let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository, store: store)
        model.danmakuEnabled = false
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        try await ready(model)
        model.seekBy(seconds: 20 - model.currentTime)
        try await wait(seconds: 15) { (model.player?.currentTime().seconds ?? 0) >= 19.5 }
        model.togglePlayPause()
        let paused = model.currentTime
        model.setRate(1.5)
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(model.currentTime, paused, accuracy: 0.2)
        await model.changeQuality(model.selectedQuality == 720 ? 360 : 720)
        try await wait(seconds: 90) { !model.isLoading && model.player?.currentItem?.status == .readyToPlay && model.duration > 0 }
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.wantsPlayback)
        XCTAssertFalse(model.isBuffering)
        XCTAssertEqual(try XCTUnwrap(model.player).rate, 0)
        XCTAssertEqual(model.currentTime, paused, accuracy: 0.75)
        model.setSceneActive(false)
        model.setSceneActive(true)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(model.isPlaying)
        model.togglePlayPause()
        try await wait(seconds: 15) { model.currentTime > paused + 0.5 && model.isPlaying }
        model.setSceneActive(false)
        let interrupted = model.currentTime
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(model.currentTime, interrupted, accuracy: 0.2)
        model.setSceneActive(true)
        try await wait(seconds: 15) { model.isPlaying && model.currentTime > interrupted + 0.5 }
        model.onDisappear()
        let history = try XCTUnwrap(LocalStore(defaults: defaults).getWatchEntry(dramaId: data.drama.id))
        XCTAssertEqual(history.episode, 1)
        XCTAssertGreaterThan(history.position, interrupted)
        XCTAssertGreaterThan(history.duration, history.position)
        print("THL_TV_PLAYBACK pauseQuality=true interruption=true resume=true historyPersistence=true")
    }

    func testLiveFinalEpisodeStopsAndReplays() async throws {
        try live()
        await JSSourceService.shared.initialize()
        let suite = "THLRedLook.QA.End." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LocalStore(defaults: defaults)
        let data = try await detail("7694896136963755032")
        let model = PlayerViewModel(drama: data.drama, allEpisodes: Array(data.episodes.prefix(1)), repository: repository, store: store)
        model.danmakuEnabled = false
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        try await ready(model)
        model.seekBy(seconds: model.duration - model.currentTime - 0.2)
        try await wait(seconds: 20) { !model.isPlaying && model.currentTime >= model.duration - 0.5 }
        let player = try XCTUnwrap(model.player)
        try await Task.sleep(nanoseconds: 21_000_000_000)
        model.requestRecovery(reason: "End-of-playlist delayed event")
        XCTAssertTrue(model.player === player)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(try XCTUnwrap(store.getWatchEntry(dramaId: data.drama.id)).finished)
        model.togglePlayPause()
        try await wait(seconds: 20) { model.isPlaying && model.currentTime > 0.5 && model.currentTime < 8 }
        model.onDisappear()
        XCTAssertFalse(try XCTUnwrap(LocalStore(defaults: defaults).getWatchEntry(dramaId: data.drama.id)).finished)
        print("THL_TV_PLAYBACK finalEpisode=true noFalseRecovery=true replay=true history=true")
    }

    func testLiveSearchPaginationAndNativePlayback() async throws {
        try live()
        await JSSourceService.shared.initialize()
        for query in ["都市", "穿越", "萌宝", "罪案"] {
            let search = SearchViewModel(repository: repository)
            await search.executeSearch(keyword: query)
            XCTAssertNil(search.errorMessage)
            XCTAssertFalse(search.searchResults.isEmpty)
            let firstIDs = Set(search.searchResults.map(\.id))
            if search.hasMore {
                await search.loadMore()
                XCTAssertNil(search.errorMessage)
                XCTAssertGreaterThan(search.searchResults.count, firstIDs.count)
                XCTAssertEqual(Set(search.searchResults.map(\.id)).count, search.searchResults.count)
            }
            let selected = try XCTUnwrap(search.searchResults.first)
            XCTAssertTrue(selected.cover.hasPrefix("https://"))
            let detail = try await repository.loadDetail(drama: selected)
            let model = model(detail)
            defer { model.onDisappear() }
            let episode = max(1, detail.episodes.count / 2)
            await model.preparePlayback(episodeIndex: episode)
            try await ready(model)
            XCTAssertFalse(try XCTUnwrap(model.plan).decryptionKey.isEmpty)
            let position = model.duration * 0.6
            model.seekBy(seconds: position - model.currentTime)
            try await wait(seconds: 25) { model.currentTime > position + 0.5 }
            print("THL_TV_SEARCH_PLAY query=\(query) series=\(selected.sourceId) episode=\(episode) firstFrame=true audio=true seek=true")
            model.onDisappear()
        }
    }

    func testLiveSourcePublicationKeepsSearchState() async throws {
        try live()
        await JSSourceService.shared.initialize()
        let store = LocalStore()
        store.currentSourceId = "hongguo"
        let search = SearchViewModel(repository: repository, store: store)
        await search.executeSearch(keyword: "都市")
        XCTAssertFalse(search.searchResults.isEmpty)
        let ids = search.searchResults.map(\.id)
        store.currentSourceId = "hongguo"
        XCTAssertTrue(search.hasSearched)
        XCTAssertEqual(search.searchResults.map(\.id), ids)
        let pending = Task { await search.executeSearch(keyword: "穿越") }
        await Task.yield()
        store.currentSourceId = "hongguo"
        await pending.value
        XCTAssertTrue(search.hasSearched)
        XCTAssertFalse(search.searchResults.isEmpty)
        XCTAssertNil(search.errorMessage)
        print("THL_TV_SEARCH_STATE repeatedSource=true pendingSearchRetained=true resultsRetained=true")
    }

    func testLivePreviouslyFailedEpisodes() async throws {
        try live()
        for (id, number) in [("7691902718872407102", 38), ("7685288902453644313", 41), ("7660929494034680857", 10)] {
            let detail = try await detail(id)
            let model = model(detail)
            defer { model.onDisappear() }
            await model.preparePlayback(episodeIndex: number)
            try await ready(model)
            let target = model.duration * 0.6
            model.seekBy(seconds: target - model.currentTime)
            try await wait(seconds: 25) { model.currentTime > target + 0.5 }
            print("THL_TV_REGRESSION series=\(id) episode=\(number) firstFrame=true audio=true seek=true")
            let local = (model.player?.currentItem?.asset as? AVURLAsset)?.url
            model.onDisappear()
            if let local, local.isFileURL { XCTAssertFalse(FileManager.default.fileExists(atPath: local.path)) }
        }
    }

    func testLiveLargeEpisodePreparation() async throws {
        try live()
        let detail = try await detail("7674630261790739481")
        let model = model(detail)
        defer { model.onDisappear() }
        let started = Date()
        await model.preparePlayback(episodeIndex: 9)
        try await ready(model)
        let target = model.duration * 0.6
        model.seekBy(seconds: target - model.currentTime)
        try await wait(seconds: 25) { model.currentTime > target + 0.5 }
        print("THL_TV_LARGE series=7674630261790739481 episode=9 firstFrame=true audio=true seek=true preparationSeconds=\(Int(Date().timeIntervalSince(started)))")
    }

    func testLiveFailureRecoveryAndContinuousPlayback() async throws {
        try live()
        let detail = try await detail("7694896136963755032")
        let model = model(detail)
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 37)
        try await ready(model)
        let failedURL = try XCTUnwrap(model.plan).url
        let position = model.currentTime
        let failedItem = AVPlayerItem(url: URL(fileURLWithPath: "/nonexistent-thl-native-test.mp4"))
        model.startPlaybackWithItem(item: failedItem, seekTo: position)
        try await wait { !model.isLoading && model.player?.currentItem?.status == .readyToPlay && model.plan?.url != failedURL && model.currentTime > position + 0.5 }
        try await ready(model)
        print("THL_TV_RECOVERY nativeFailure=true excludedFailedUrl=true resumed=true")
        model.seekBy(seconds: 45 - model.currentTime)
        try await wait(seconds: 10) { model.currentTime > 45.5 }
        model.seekBy(seconds: -30)
        let rewindPlayer = model.player
        let rewindURL = model.plan?.url
        try await Task.sleep(nanoseconds: 21_000_000_000)
        XCTAssertTrue(model.player === rewindPlayer)
        XCTAssertEqual(model.plan?.url, rewindURL)
        XCTAssertFalse(model.isLoading)
        XCTAssertGreaterThan(model.currentTime, 30)
        print("THL_TV_BACKWARD continuous=true noFalseStallRecovery=true")
        model.seekBy(seconds: model.duration - model.currentTime - 1.5)
        try await wait { model.currentEpisodeIndex == 38 && !model.isLoading && model.currentTime > 0.5 }
        try await ready(model)
        await model.previousEpisode()
        try await ready(model)
        XCTAssertEqual(model.currentEpisodeIndex, 37)
        print("THL_TV_TRANSITIONS autoNext=true previous=true")
    }

    func testLiveRapidEpisodeChangeAndExitCancellation() async throws {
        try live()
        let detail = try await detail("7694896136963755032")
        let model = model(detail)
        let pending = Task { await model.preparePlayback(episodeIndex: 1) }
        try await Task.sleep(nanoseconds: 100_000_000)
        await model.preparePlayback(episodeIndex: 2)
        await pending.value
        try await ready(model)
        XCTAssertEqual(model.currentEpisodeIndex, 2)
        let closing = Task { await model.preparePlayback(episodeIndex: 3) }
        try await Task.sleep(nanoseconds: 100_000_000)
        model.onDisappear()
        await closing.value
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(model.player)
        XCTAssertNil(model.plan)
        print("THL_TV_CANCELLATION latestEpisode=true exitReleased=true")
    }

    func testLiveStallWithoutNativeErrorRecovers() async throws {
        try live()
        let detail = try await detail("7694896136963755032")
        let model = model(detail)
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        try await ready(model)
        let first = try XCTUnwrap(model.plan).url
        let position = model.currentTime
        let started = Date()
        model.player?.pause()
        try await wait { !model.isPlaying }
        XCTAssertTrue(model.wantsPlayback)
        try await wait { !model.isLoading && model.plan?.url != first && model.currentTime > position + 0.5 }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 18)
        try await ready(model)
        print("THL_TV_STALL noNativeError=true resumed=true firstFrame=true audio=true")
    }

    func testLiveYaoFifthAndFourthSeasonFrames() async throws {
        try live()
        await JSSourceService.shared.initialize()
        let catalog = try await repository.loadCatalog(source: "hongguo", query: "满院亲戚全是上古大妖", force: true)
        let suite = "THLRedLook.QA.YaoSeasons." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LocalStore(defaults: defaults)
        for (season, id, number) in [(5, "7695704804978330649", 1), (4, "7688558312157088793", 4)] {
            let drama = try XCTUnwrap(catalog.items.first { $0.sourceId == id })
            let data = try await repository.loadDetail(drama: drama)
            XCTAssertEqual(data.drama.sourceId, id)
            XCTAssertGreaterThan(data.episodes.count, 100)
            let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository, store: store)
            model.danmakuEnabled = false
            defer { model.onDisappear() }
            await model.preparePlayback(episodeIndex: number)
            try await ready(model)
            let item = try XCTUnwrap(model.player?.currentItem)
            let audio = try await item.asset.loadTracks(withMediaType: .audio)
            print("THL_TV_YAO_NATIVE season=\(season) episode=\(number) series=\(id) firstFrame=true audioTracks=\(audio.count) duration=\(Int(model.duration)) episodes=\(data.episodes.count) encrypted=\(!(model.plan?.decryptionKey.isEmpty ?? true))")
            if season == 4 {
                model.seekBy(seconds: model.duration - model.currentTime - 1)
                try await wait(seconds: 120) { model.currentEpisodeIndex == number + 1 && !model.isLoading && model.currentTime > 0.5 }
                try await ready(model)
                XCTAssertEqual(model.currentEpisodeIndex, 5)
                print("THL_TV_YAO_NATIVE autoNext=true season=4 episode=5 firstFrame=true audio=true")
            }
            model.onDisappear()
        }
    }

    func testLiveStaleSeasonIdentityAndProgress() async throws {
        try live()
        await JSSourceService.shared.initialize()
        let suite = "THLRedLook.QA.StaleSeasons." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldFourth = Drama(id: "hongguo:7688558312157089000", sourceId: "7688558312157089000", title: "满院亲戚全是上古大妖第四季")
        let oldSecond = Drama(id: "hongguo:7678338044344159000", sourceId: "7678338044344159000", title: "满院亲戚全是上古大妖第二季")
        let fifth = Drama(id: "hongguo:7695704804978330649", sourceId: "7695704804978330649", title: "满院亲戚全是上古大妖第五季")
        let unrelated = Drama(id: "test_stale_preservation", title: "合成本地记录")
        let seed = LocalStore(defaults: defaults)
        seed.setFollowState(drama: oldFourth, state: .watched)
        seed.setFollowState(drama: oldSecond, state: .watching)
        for (drama, episode) in [(fifth, 11), (oldFourth, 12), (oldSecond, 5), (unrelated, 3)] {
            seed.recordWatch(drama: drama, episode: episode, position: 7, duration: 160)
        }
        let store = LocalStore(defaults: defaults)
        let detailModel = DetailViewModel(drama: fifth, repository: repository, store: store)
        await detailModel.loadDetail()
        XCTAssertNil(detailModel.errorMessage)
        XCTAssertEqual(store.followState(for: "hongguo:7688558312157088793"), .watched)
        XCTAssertEqual(store.followState(for: "hongguo:7678338044344159256"), .watching)
        for (target, expected, number) in [(fifth, "7695704804978330649", 11), (oldFourth, "7688558312157088793", 12), (oldSecond, "7678338044344159256", 5)] {
            if target.id != fifth.id { await detailModel.switchToDrama(target) }
            XCTAssertNil(detailModel.errorMessage)
            let data = try XCTUnwrap(detailModel.detail)
            XCTAssertEqual(data.drama.cleanSourceId, expected)
            XCTAssertEqual(detailModel.lastWatchEntry?.episode, number)
            XCTAssertEqual(detailModel.lastWatchEntry?.position, 7)
            let player = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository, store: store)
            player.danmakuEnabled = false
            defer { player.onDisappear() }
            await player.preparePlayback(episodeIndex: number, seekTo: 7)
            try await ready(player)
            try await wait(seconds: 20) { player.currentTime > 7.5 && player.isPlaying }
            print("THL_TV_STALE_NATIVE series=\(expected) episode=\(number) resume=true firstFrame=true audio=true")
            if target.id == oldFourth.id {
                await player.preparePlayback(episodeIndex: 1)
                try await ready(player)
                player.seekBy(seconds: player.duration - player.currentTime - 1)
                try await wait { player.currentEpisodeIndex == 2 && !player.isLoading && player.currentTime > 0.5 }
                try await ready(player)
                print("THL_TV_STALE_NATIVE season=4 selection=1 autoNext=2 firstFrame=true audio=true")
            }
            if target.id == oldSecond.id {
                await player.preparePlayback(episodeIndex: 13)
                try await ready(player)
                print("THL_TV_STALE_NATIVE season=2 selection=13 firstFrame=true audio=true")
            }
            player.onDisappear()
        }
        let direct = DetailViewModel(drama: oldFourth, repository: repository, store: store)
        await direct.loadDetail()
        XCTAssertNil(direct.errorMessage)
        XCTAssertEqual(direct.drama.cleanSourceId, "7688558312157088793")
        XCTAssertEqual(direct.lastWatchEntry?.episode, 2)
        let reloaded = LocalStore(defaults: defaults)
        XCTAssertEqual(reloaded.followedDramas.count, 2)
        XCTAssertFalse(reloaded.history.contains { [oldFourth.id, oldSecond.id].contains($0.drama.id) })
        XCTAssertEqual(reloaded.followState(for: direct.drama.id), .watched)
        XCTAssertEqual(reloaded.getWatchEntry(dramaId: unrelated.id), seed.getWatchEntry(dramaId: unrelated.id))
        let stalePlayer = PlayerViewModel(drama: oldSecond, allEpisodes: [], repository: repository, store: store)
        stalePlayer.danmakuEnabled = false
        defer { stalePlayer.onDisappear() }
        await stalePlayer.preparePlayback(episodeIndex: 5)
        try await ready(stalePlayer)
        XCTAssertEqual(stalePlayer.drama.cleanSourceId, "7678338044344159256")
        stalePlayer.onDisappear()
        print("THL_TV_STALE_NATIVE oldFavorite=true directPlayer=true persisted=true favorites=true unrelatedHistory=true")
    }

    func testLiveDiscoveryCursorSurvivesSourceRefresh() async throws {
        try live()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("THLDiscoveryCursor-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = NativeBridge(baseDirectory: directory)
        let first = try await bridge.request(action: "recommendations", payload: ["category": "real-drama", "page": 1])
        XCTAssertTrue(first["hasMore"] as? Bool ?? false)
        _ = try await bridge.request(action: "jsSource.scan", payload: [:])
        let second = try await bridge.request(action: "recommendations", payload: ["category": "real-drama", "page": 2])
        XCTAssertFalse((second["items"] as? [[String: Any]] ?? []).isEmpty)
        _ = try await bridge.request(action: "jsSource.saveAndLoad", payload: ["script": BuiltInHongguoJSContent, "fileName": "hongguo.js", "autoSelect": true])
        let third = try await bridge.request(action: "recommendations", payload: ["category": "real-drama", "page": 3])
        XCTAssertFalse((third["items"] as? [[String: Any]] ?? []).isEmpty)
        let board = "hongguo-app:human:human_hot_sc"
        _ = try await bridge.request(action: "rankings", payload: ["board": board, "page": 1])
        _ = try await bridge.request(action: "jsSource.scan", payload: [:])
        let rankingNext = try await bridge.request(action: "rankings", payload: ["board": board, "page": 2])
        XCTAssertFalse((rankingNext["items"] as? [[String: Any]] ?? []).isEmpty)
        print("THL_TV_DISCOVERY_CURSOR scan=true unchangedImport=true recommendations=3 ranking=2 retained=true")
    }

}
