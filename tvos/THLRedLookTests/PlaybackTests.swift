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

    func testLiveEightAutomaticEpisodeTransitions() async throws {
        try live()
        await JSSourceService.shared.initialize()
        let data = try await detail("7694896136963755032")
        let model = model(data)
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        for episode in 1...8 {
            try await ready(model)
            XCTAssertEqual(model.currentEpisodeIndex, episode)
            XCTAssertFalse(try XCTUnwrap(model.plan).decryptionKey.isEmpty)
            print("THL_CONTINUOUS episode=\(episode) video=true audio=true position=\(model.currentTime)")
            if episode < 8 {
                model.seekBy(seconds: max(0, model.duration - model.currentTime - 6))
                try await wait(seconds: 100) { model.currentEpisodeIndex == episode + 1 && !model.isLoading && model.currentTime > 0.5 }
            }
        }
        print("THL_CONTINUOUS automaticTransitions=7 lastEpisode=8 error=false")
    }

    func testLiveNaturalContinuousPlaybackWithoutSeeking() async throws {
        try live()
        await JSSourceService.shared.initialize()
        let data = try await detail("7694896136963755032")
        let suite = "THLRedLook.Natural." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository, store: LocalStore(defaults: defaults))
        model.danmakuEnabled = true
        defer { model.onDisappear() }
        let began = Date()
        var events: [[String: Any]] = []
        func record(_ event: [String: Any]) {
            var value = event
            value["elapsedSeconds"] = Int(Date().timeIntervalSince(began))
            events.append(value)
            if let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let text = String(data: bytes, encoding: .utf8) {
                print("THL_NATURAL " + text)
            }
        }
        record(["stage": "selected", "title": data.drama.title, "seriesId": data.drama.cleanSourceId, "rate": 1, "seek": false, "firstEpisode": 5, "completeEpisodes": 3])
        await model.preparePlayback(episodeIndex: 5)
        for episode in 5...8 {
            try await ready(model)
            XCTAssertEqual(model.currentEpisodeIndex, episode)
            XCTAssertEqual(model.playbackRate, 1)
            XCTAssertFalse(try XCTUnwrap(model.player).isMuted)
            record(["stage": "ready", "episode": episode, "duration": model.duration, "position": model.currentTime, "video": true, "audio": true])
            if episode == 8 { break }
            let deadline = Date().addingTimeInterval(max(180, model.duration * 1.3 + 40))
            var lastLogged = -1
            while model.currentEpisodeIndex == episode && Date() < deadline {
                guard model.errorMessage == nil else {
                    XCTFail(model.errorMessage ?? "Playback failed")
                    throw NSError(domain: "NaturalPlayback", code: 1)
                }
                let bucket = Int(model.currentTime) / 15
                if bucket != lastLogged {
                    lastLogged = bucket
                    record(["stage": "playing", "episode": episode, "position": model.currentTime, "duration": model.duration, "buffering": model.isBuffering])
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            XCTAssertEqual(model.currentEpisodeIndex, episode + 1)
            record(["stage": "autoNext", "from": episode, "to": model.currentEpisodeIndex])
        }
        XCTAssertNil(model.errorMessage)
        record(["stage": "complete", "naturalCompleteEpisodes": 3, "currentEpisode": model.currentEpisodeIndex, "seek": false])
        let bytes = try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: bytes, as: UTF8.self))
        attachment.name = "natural-playback.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("THL_NATURAL_RESULT " + String(decoding: try JSONSerialization.data(withJSONObject: events, options: .sortedKeys), as: UTF8.self))
    }

    func testLiveReportedOverseasEpisodeAndAutomaticNext() async throws {
        try live()
        let data = try await detail("7697541703539887129")
        let episode = try XCTUnwrap(data.episodes.first { $0.number == 184 })
        let raw = try JSONSerialization.jsonObject(with: XCTUnwrap(episode.raw)) as? [String: Any]
        XCTAssertEqual(raw?["url"] as? String, "https://hongguoduanju.com/player/7697541703539887129/7701245171979029528")
        let suite = "THLRedLook.OverseasLive." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository, store: LocalStore(defaults: defaults))
        model.danmakuEnabled = false
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 184)
        try await ready(model)
        XCTAssertEqual(model.currentEpisodeIndex, 184)
        print("THL_OVERSEAS_LIVE episode=184 firstFrame=true video=true audio=true")
        model.seekBy(seconds: max(0, model.duration - model.currentTime - 3))
        try await wait { model.currentEpisodeIndex == 185 && !model.isLoading && model.currentTime > 0.5 }
        try await ready(model)
        XCTAssertEqual(model.currentEpisodeIndex, 185)
        print("THL_OVERSEAS_LIVE episode=185 automaticNext=true firstFrame=true video=true audio=true")
    }

    func testLive1080PrioritySwitchResolutionAndAutomaticNext() async throws {
        try live()
        let data = try await detail("7694896136963755032")
        let suite = "THLRedLook.Quality." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository, preloadingRepository: repository, store: LocalStore(defaults: defaults))
        model.danmakuEnabled = false
        defer { model.onDisappear() }
        func verifyResolution(_ expected: Int) async throws {
            try await ready(model)
            let item = try XCTUnwrap(model.player?.currentItem)
            let tracks = try await item.asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let size = try await track.load(.naturalSize)
            XCTAssertEqual(Int(min(size.width, size.height)), expected)
            XCTAssertEqual(model.selectedQuality, expected)
            XCTAssertEqual(model.plan?.quality, expected)
            XCTAssertFalse(try XCTUnwrap(model.player).isMuted)
            print("THL_QUALITY actual=\(Int(min(size.width, size.height))) requested=\(model.requestedQuality) width=\(Int(size.width)) height=\(Int(size.height)) position=\(model.currentTime)")
        }
        XCTAssertEqual(model.requestedQuality, 0)
        await model.preparePlayback(episodeIndex: 1)
        try await verifyResolution(1080)
        XCTAssertTrue(model.qualityOptions.contains(720))
        XCTAssertTrue(model.qualityOptions.contains(360))
        model.seekBy(seconds: 12 - model.currentTime)
        try await wait(seconds: 15) { model.currentTime > 11 }
        model.togglePlayPause()
        let paused = model.currentTime
        await model.changeQuality(720)
        try await verifyResolution(720)
        XCTAssertEqual(model.requestedQuality, 720)
        XCTAssertFalse(model.wantsPlayback)
        XCTAssertEqual(model.currentTime, paused, accuracy: 0.8)
        model.togglePlayPause()
        model.seekBy(seconds: max(0, model.duration - model.currentTime - 3))
        try await wait { model.currentEpisodeIndex == 2 && !model.isLoading && model.currentTime > 0.5 }
        try await verifyResolution(1080)
        XCTAssertFalse(model.qualityOptions.contains(720))
        XCTAssertEqual(model.requestedQuality, 720)
        model.togglePlayPause()
        let nextPaused = model.currentTime
        await model.changeQuality(1080)
        try await verifyResolution(1080)
        XCTAssertFalse(model.wantsPlayback)
        XCTAssertEqual(model.currentTime, nextPaused, accuracy: 0.8)
        await model.changeQuality(0)
        try await verifyResolution(1080)
        XCTAssertEqual(model.requestedQuality, 0)
        print("THL_QUALITY_RESULT default1080=true switch720=true autoNext1080Fallback=true requested720Preserved=true switch1080=true automatic1080=true pauseAndProgressPreserved=true")
    }

    private func verifyOfficialFallback(single: Bool) async throws {
        try live()
        OfficialModelFailureProtocol.configure(blockReadingBatch: single)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfficialModelFailureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = SourceDiagnostics()
        let bridge = NativeBridge(baseDirectory: root, httpSession: session, diagnostics: recorder, diagnosticContext: "官方备用实播", persistentDeviceSession: false)
        let repository = NativeRepository(bridge: bridge, playbackBridge: bridge)
        let data = try await repository.loadDetail(drama: Drama(id: "hongguo:7697541703539887129", source: "hongguo", sourceId: "7697541703539887129", title: "用户反馈分集"))
        let suite = "THLRedLook.OfficialFallback." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository, preloadingRepository: repository, store: LocalStore(defaults: defaults))
        model.danmakuEnabled = false
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 184)
        try await ready(model)
        XCTAssertEqual(model.currentEpisodeIndex, 184)
        XCTAssertFalse(try XCTUnwrap(model.plan).decryptionKey.isEmpty)
        XCTAssertEqual(OfficialModelFailureProtocol.count, single ? 2 : 1)
        model.seekBy(seconds: max(0, model.duration - model.currentTime - 3))
        try await wait { model.currentEpisodeIndex == 185 && !model.isLoading && model.currentTime > 0.5 }
        try await ready(model)
        XCTAssertEqual(OfficialModelFailureProtocol.count, single ? 2 : 1)
        let path = single ? "/novel/player/video_model/v1/" : "/novel/player/multi_video_model/v1/"
        XCTAssertGreaterThanOrEqual(recorder.entries.filter { $0.stage == "播放解析" && $0.host == "reading.snssdk.com" && $0.url.contains(path) && !$0.failed }.count, 2)
        print("THL_OFFICIAL_FALLBACK single=\(single) episodes=184,185 video=true audio=true autoNext=true failedRouteNotRepeated=true")
    }

    func testLiveOfficialReadingBatchRecoversPrimaryEmptyResponse() async throws {
        try await verifyOfficialFallback(single: false)
    }

    func testLiveOfficialSingleEndpointRecoversBatchEmptyResponses() async throws {
        try await verifyOfficialFallback(single: true)
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

@MainActor
final class ContinuousPlaybackTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        roots = []
        super.tearDown()
    }

    private func repository(mode: String, recorder: SourceDiagnostics = SourceDiagnostics()) async throws -> (NativeRepository, NativeBridge) {
        guard let path = ProcessInfo.processInfo.environment["THL_SYNTHETIC_VIDEO"] else { throw XCTSkip("Requires generated video fixture") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let video = root.appendingPathComponent("synthetic.mp4")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: video)
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: video.absoluteString, options: .fragmentsAllowed), as: UTF8.self)
        let behavior: String
        switch mode {
        case "denied": behavior = "throw Object.assign(new Error('synthetic failure'),{code:'BUSINESS_REJECTED'});"
        case "slow": behavior = "const stop=Date.now()+4000;while(Date.now()<stop){};"
        case "retry": behavior = "if(id==='2'&&calls[id]===1)throw Object.assign(new Error('synthetic transient failure'),{code:'HTTP_503'});"
        case "error": behavior = "return {url:'',error:'MEDIA_HTTP_403'};"
        default: behavior = ""
        }
        let script = """
        const meta={id:'synthetic',name:'Synthetic',version:'1.0.0'};
        const calls={};
        const spider={play:async function(flag,id){calls[id]=(calls[id]||0)+1;\(behavior)return {url:\(encoded),quality:\(mode == "normal" ? 360 : 480),expiresAt:Date.now()+\(mode == "expired" ? 500 : 60000)};},search:async function(){return {list:[{vod_id:'counts',vod_name:JSON.stringify(calls)}],page:1,pagecount:1};}};
        """
        let bridge = NativeBridge(baseDirectory: root, diagnostics: recorder, diagnosticContext: "合成 \(mode)", persistentDeviceSession: false)
        _ = try await bridge.request(action: "jsSource.saveAndLoad", payload: ["fileName": "synthetic.js", "script": script])
        return (NativeRepository(bridge: bridge, playbackBridge: bridge), bridge)
    }

    private func calls(_ repository: NativeRepository, episode: Int) async throws -> Int {
        let result = try await repository.loadCatalog(source: "synthetic", query: "counts")
        let text = try XCTUnwrap(result.items.first?.title)
        let data = try XCTUnwrap(text.data(using: .utf8))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Int])?[String(episode)] ?? 0
    }

    private func model(foreground: NativeRepository, preloading: NativeRepository) throws -> PlayerViewModel {
        let suite = "THLRedLook.Continuous." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let episodes = try (1...4).map { index in
            Episode(id: String(index), title: "合成第\(index)集", number: index, raw: try JSONSerialization.data(withJSONObject: ["url": String(index)]))
        }
        let model = PlayerViewModel(drama: Drama(id: "synthetic:series", source: "synthetic", sourceId: "series", title: "合成连续播放"), allEpisodes: episodes, repository: foreground, preloadingRepository: preloading, store: LocalStore(defaults: defaults))
        model.danmakuEnabled = false
        return model
    }

    private func wait(seconds: Double = 15, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(condition())
        guard condition() else { throw NSError(domain: "ContinuousPlaybackTests", code: 1) }
    }

    func testPlanExpiryUsesSafetyWindow() {
        let date = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(PlaybackPlan(url: "https://example.invalid/video", expiresAt: 1_002_000).isReusable(at: date))
        XCTAssertTrue(PlaybackPlan(url: "https://example.invalid/video", expiresAt: 1_030_000).isReusable(at: date))
        XCTAssertTrue(PlaybackPlan(url: "file:///synthetic", expiresAt: 1, local: true).isReusable(at: date))
    }

    func testExpiredNextEpisodeIsResolvedAgainOnAutomaticAdvance() async throws {
        let (foreground, _) = try await repository(mode: "normal")
        let (prefetch, _) = try await repository(mode: "expired")
        let model = try model(foreground: foreground, preloading: prefetch)
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        try await wait { !model.isLoading && model.currentTime > 0.5 }
        model.seekBy(seconds: 4 - model.currentTime)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let prefetchCount = try await calls(prefetch, episode: 2)
        XCTAssertEqual(prefetchCount, 1)
        model.seekBy(seconds: model.duration - model.currentTime - 0.2)
        try await wait { model.currentEpisodeIndex == 2 && !model.isLoading && model.currentTime > 0.5 }
        XCTAssertEqual(model.plan?.quality, 360)
        let foregroundCount = try await calls(foreground, episode: 2)
        XCTAssertEqual(foregroundCount, 1)
        XCTAssertNil(model.errorMessage)
    }

    func testFailedPreloadDoesNotPollEveryProgressTick() async throws {
        let (foreground, _) = try await repository(mode: "normal")
        let (prefetch, _) = try await repository(mode: "denied")
        let model = try model(foreground: foreground, preloading: prefetch)
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        try await wait { !model.isLoading && model.currentTime > 0.5 }
        model.seekBy(seconds: 3.5 - model.currentTime)
        try await Task.sleep(nanoseconds: 5_500_000_000)
        let prefetchCount = try await calls(prefetch, episode: 2)
        XCTAssertEqual(prefetchCount, 1)
        model.seekBy(seconds: model.duration - model.currentTime - 0.2)
        try await wait { model.currentEpisodeIndex == 2 && !model.isLoading && model.currentTime > 0.5 }
        XCTAssertNil(model.errorMessage)
    }

    func testSlowPreloadCannotBlockForegroundTransition() async throws {
        let (foreground, _) = try await repository(mode: "normal")
        let (prefetch, _) = try await repository(mode: "slow")
        let model = try model(foreground: foreground, preloading: prefetch)
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        try await wait { !model.isLoading && model.currentTime > 0.5 }
        model.seekBy(seconds: 4 - model.currentTime)
        try await Task.sleep(nanoseconds: 700_000_000)
        let start = Date()
        await model.nextEpisode()
        try await wait { !model.isLoading && model.currentTime > 0.2 }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertEqual(model.currentEpisodeIndex, 2)
        XCTAssertEqual(model.plan?.quality, 360)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(model.currentEpisodeIndex, 2)
        XCTAssertEqual(model.plan?.quality, 360)
    }

    func testNextEpisodeRecoveryDoesNotReusePreviousEpisodePosition() async throws {
        let (foreground, _) = try await repository(mode: "retry")
        let (prefetch, _) = try await repository(mode: "denied")
        let model = try model(foreground: foreground, preloading: prefetch)
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        try await wait { !model.isLoading && model.currentTime > 0.5 }
        model.seekBy(seconds: model.duration - model.currentTime - 0.2)
        try await wait { model.currentEpisodeIndex == 2 && !model.isLoading && model.currentTime > 0.5 }
        XCTAssertLessThan(model.currentTime, 3)
        XCTAssertNil(model.errorMessage)
        let requests = try await calls(foreground, episode: 2)
        XCTAssertEqual(requests, 2)
    }

    func testEmptyStreamRetainsMediaFailureCode() async throws {
        let recorder = SourceDiagnostics()
        let (_, bridge) = try await repository(mode: "error", recorder: recorder)
        do {
            _ = try await bridge.request(action: "resolve", payload: ["source": "synthetic", "drama": ["id": "synthetic:series"], "index": 5, "chapter": ["url": "5"]])
            XCTFail("Expected media denial")
        } catch {
            XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "MEDIA_HTTP_403")
            XCTAssertTrue(error.localizedDescription.contains("MEDIA_HTTP_403"))
        }
        XCTAssertEqual(recorder.entries.last?.errorCode, "MEDIA_HTTP_403")
        XCTAssertEqual(recorder.entries.last?.stage, "播放取流 第5集")
    }
}

private final class OfficialModelFailureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var blockReadingBatch = false
    private static var blocked = 0
    static func configure(blockReadingBatch: Bool) { lock.lock();defer { lock.unlock() };self.blockReadingBatch = blockReadingBatch;blocked = 0 }
    static var count: Int { lock.lock();defer { lock.unlock() };return blocked }
    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock();defer { lock.unlock() }
        guard request.url?.path.contains("/novel/player/multi_video_model/v1") == true else { return false }
        return request.url?.host == "api5-normal-sinfonlineb.fqnovel.com" || blockReadingBatch && request.url?.host == "reading.snssdk.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.lock();Self.blocked += 1;Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Content-Length": "0", "x-tt-logid": "synthetic-primary-empty"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}
