import XCTest
import AVFoundation
import UIKit
@testable import THLRedLook

@MainActor
final class PlaybackTests: XCTestCase {
    private let repository = NativeRepository.shared
    private var videoView: UIView?
    private var videoLayer: AVPlayerLayer?
    private var testStarted = Date()

    override func setUp() {
        super.setUp()
        testStarted = Date()
    }

    override func tearDown() {
        if ProcessInfo.processInfo.environment["HONGGUO_LIVE"] == "1" {
            let traces = SourceDiagnostics.shared.entries.filter { $0.at >= testStarted }.map { entry -> [String: Any] in
                ["at": entry.at.timeIntervalSince1970, "context": entry.context, "stage": entry.stage,
                 "host": entry.host, "path": URL(string: entry.url)?.path ?? "", "status": entry.status,
                 "code": entry.errorCode, "bodyBytes": entry.bodyBytes ?? -1, "elapsedMs": entry.elapsedMs,
                 "session": entry.sessionStatus]
            }
            if let bytes = try? JSONSerialization.data(withJSONObject: traces, options: [.sortedKeys]) {
                let text = String(decoding: bytes, as: UTF8.self)
                print("THL_LIVE_TRACES " + text)
                let attachment = XCTAttachment(string: text)
                attachment.name = "playback-traces.json"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
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
        try await wait { model.errorMessage != nil || (model.player != nil && !model.isLoading && model.duration > 1 && model.currentTime > 0.5) }
        if let error = model.errorMessage {
            XCTFail(error)
            throw NSError(domain: "PlaybackTests", code: 2, userInfo: [NSLocalizedDescriptionKey: error])
        }
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
        let suite = "THLRedLook.Automatic." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository, store: LocalStore(defaults: defaults, cloudUpload: { _ in }))
        model.danmakuEnabled = false
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
        let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, repository: repository, store: LocalStore(defaults: defaults, cloudUpload: { _ in }))
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

    func testLiveDiagnosticsRepeatedWithSavedSession() async throws {
        try live()
        guard let directory = ProcessInfo.processInfo.environment["THL_MATRIX_OUTPUT"] else { throw XCTSkip("Requires output directory") }
        var rows: [[String: Any]] = []
        for number in 1...5 {
            let started = Date()
            await SourceDiagnosticRunner.shared.run()
            let entries = SourceDiagnostics.shared.entries.filter { $0.at >= started && $0.context.hasPrefix("主动检测 ") }
            let row: [String: Any] = ["number": number, "result": SourceDiagnosticRunner.shared.result, "entries": entries.map { ["stage": $0.stage, "host": $0.host, "status": $0.status, "bytes": $0.bodyBytes ?? -1, "code": $0.errorCode, "sessionStatus": $0.sessionStatus] as [String: Any] }]
            rows.append(row)
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: directory).appendingPathComponent("diagnostic-repeat.json"), options: .atomic)
            print("THL_DIAGNOSTIC_REPEAT round=\(number) result=\(SourceDiagnosticRunner.shared.result)")
            XCTAssertTrue(SourceDiagnosticRunner.shared.result.hasPrefix("检测完成"))
        }
    }

    func testLiveExpandedCatalogPlaybackMatrix() async throws {
        try live()
        guard let directory = ProcessInfo.processInfo.environment["THL_MATRIX_OUTPUT"] else { throw XCTSkip("Requires output directory") }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var candidates: [(Drama, String)] = []
        var seen = Set<String>()
        var discovery: [[String: Any]] = []
        var results: [[String: Any]] = []
        func save() throws {
            let selected = candidates.map { ["id": $0.0.id, "seriesId": $0.0.cleanSourceId, "title": $0.0.title, "origin": $0.1] }
            let report: [String: Any] = ["appManifest": SourceDiagnostics.sourceManifest, "discovery": discovery, "candidates": selected, "results": results]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("matrix.json"), options: .atomic)
        }
        func append(_ items: [Drama], origin: String, limit: Int) -> Int {
            var added = 0
            for drama in items where candidates.count < 30 && added < limit {
                if seen.insert(drama.id).inserted { candidates.append((drama, origin)); added += 1 }
            }
            return added
        }
        if let path = ProcessInfo.processInfo.environment["THL_MATRIX_SELECTION"] {
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String: String]] ?? []
            for item in raw {
                let id = try XCTUnwrap(item["id"])
                candidates.append((Drama(id: id, source: "hongguo", sourceId: item["seriesId"] ?? "", title: item["title"] ?? id), item["origin"] ?? "固定复验"))
            }
        } else {
            let categories = try await repository.loadCategories(source: "hongguo")
            for category in categories.prefix(4) {
                var remaining = 5
                for page in 1...2 where remaining > 0 {
                    do {
                        let data = try await repository.loadCatalog(source: "hongguo", category: category.id, page: page)
                        discovery.append(["origin": "找剧-" + category.name, "page": page, "count": data.items.count])
                        remaining -= append(data.items, origin: "找剧-" + category.name, limit: remaining)
                        if !data.hasMore { break }
                    } catch { discovery.append(["origin": "找剧-" + category.name, "error": SourceDiagnostics.redact(error.localizedDescription)]) }
                }
            }
            let session = UUID().uuidString
            for page in 1...2 {
                do {
                    let feed = try await repository.loadVideoFeed(page: page, session: session)
                    discovery.append(["origin": "推荐", "page": page, "count": feed.items.count])
                    _ = append(feed.items.map(\.drama), origin: "推荐", limit: 4)
                    if !feed.hasMore { break }
                } catch { discovery.append(["origin": "推荐", "error": SourceDiagnostics.redact(error.localizedDescription)]) }
            }
            for query in ["重生", "修仙", "千金", "萌宝", "觉醒", "悬疑", "亲戚", "系统"] where candidates.count < 30 {
                do {
                    let data = try await repository.loadCatalog(source: "hongguo", query: query)
                    discovery.append(["origin": "搜索-" + query, "count": data.items.count])
                    _ = append(data.items, origin: "搜索-" + query, limit: 2)
                } catch { discovery.append(["origin": "搜索-" + query, "error": SourceDiagnostics.redact(error.localizedDescription)]) }
            }
        }
        try save()
        XCTAssertGreaterThanOrEqual(candidates.count, 25)
        let history = LocalStore.shared.history
        let favorites = LocalStore.shared.followedDramas
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .moviePlayback)
        try audio.setActive(true)
        for (index, candidate) in candidates.enumerated() {
            do {
                let data = try await repository.loadDetail(drama: candidate.0)
                let episodes = data.episodes.sorted { $0.number < $1.number }
                guard let first = episodes.first else { throw NSError(domain: "ExpandedPlayback", code: 1, userInfo: [NSLocalizedDescriptionKey: "No episode metadata"]) }
                var samples = [first]
                if index % 5 == 0, episodes.count > 2 { samples += [episodes[episodes.count / 2], episodes[episodes.count - 1]] }
                for episode in samples {
                    var row: [String: Any] = ["title": data.drama.title, "seriesId": data.drama.cleanSourceId, "origin": candidate.1, "episode": episode.number, "episodes": episodes.count, "chapterTarget": episode.rawChapter?["url"] as? String ?? ""]
                    try save()
                    print("THL_MATRIX_BEGIN series=\(data.drama.cleanSourceId) title=\(data.drama.title) episode=\(episode.number) origin=\(candidate.1)")
                    let started = Date()
                    var phase = "resolve"
                    do {
                        let plan = try await repository.resolvePlayback(drama: data.drama, episode: episode, episodeIndex: episode.number)
                        row["firstResolveSucceeded"] = true
                        row["quality"] = plan.quality
                        row["host"] = URL(string: plan.url)?.host ?? ""
                        row["encrypted"] = !plan.decryptionKey.isEmpty
                        row["preview"] = PlaybackPlan.isPublicPreviewURL(plan.url)
                        phase = "prepare"
                        let prepared = try await PlaybackAssetFactory.prepare(plan)
                        phase = "play"
                        let measured = try await measureExpandedPlayback(prepared, seconds: index % 6 == 0 ? 35 : 15)
                        row.merge(measured) { _, new in new }
                        row["firstPlaybackSucceeded"] = true
                        row["autoRecoveryNeeded"] = false
                        XCTAssertFalse(PlaybackPlan.isPublicPreviewURL(plan.url))
                    } catch {
                        row["firstPlaybackSucceeded"] = false
                        if phase == "resolve" { row["firstResolveSucceeded"] = false }
                        row["failedPhase"] = phase
                        row["firstError"] = SourceDiagnostics.redact(error.localizedDescription)
                        row["firstCode"] = (error as NSError).userInfo["diagnosticCode"] as? String ?? String((error as NSError).code)
                        row["requests"] = SourceDiagnostics.shared.entries.filter { $0.at >= started && $0.stage.contains("播放") }.map { ["stage": $0.stage, "host": $0.host, "status": $0.status, "bytes": $0.bodyBytes ?? -1, "code": $0.errorCode] as [String: Any] }
                        row["autoRecoveryNeeded"] = true
                        let suite = "THLRedLook.Expanded." + UUID().uuidString
                        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                        let model = PlayerViewModel(drama: data.drama, allEpisodes: data.episodes, initialEpisodeIndex: episode.number, repository: repository, store: LocalStore(defaults: defaults, cloudUpload: { _ in }))
                        model.danmakuEnabled = false
                        await model.preparePlayback(episodeIndex: episode.number)
                        let deadline = Date().addingTimeInterval(75)
                        while model.errorMessage == nil, (model.isLoading || model.currentTime < 3), Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
                        row["recovered"] = model.errorMessage == nil && !model.isLoading && model.currentTime >= 3
                        row["recoveryError"] = SourceDiagnostics.redact(model.errorMessage ?? "")
                        row["recoveredPosition"] = model.currentTime
                        model.onDisappear()
                        defaults.removePersistentDomain(forName: suite)
                    }
                    row["sessionRecoveries"] = SourceDiagnostics.shared.entries.filter { $0.at >= started && $0.stage == "游客会话恢复" }.map(\.sessionStatus)
                    row["elapsedSeconds"] = Date().timeIntervalSince(started)
                    results.append(row)
                    try save()
                    print("THL_MATRIX " + String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self))
                }
            } catch {
                results.append(["title": candidate.0.title, "seriesId": candidate.0.cleanSourceId, "origin": candidate.1, "failedPhase": "detail", "firstPlaybackSucceeded": false, "firstError": SourceDiagnostics.redact(error.localizedDescription)])
                try save()
            }
        }
        XCTAssertEqual(LocalStore.shared.history, history)
        XCTAssertEqual(LocalStore.shared.followedDramas, favorites)
        let failed = results.filter { $0["firstPlaybackSucceeded"] as? Bool != true }
        print("THL_MATRIX_SUMMARY dramas=\(candidates.count) episodes=\(results.count) firstFailures=\(failed.count)")
        XCTAssertTrue(failed.isEmpty, failed.map { ($0["title"] as? String ?? "") + " 第\($0["episode"] ?? 0)集 " + ($0["firstCode"] as? String ?? "") }.joined(separator: "; "))
    }

    private func measureExpandedPlayback(_ prepared: PreparedPlaybackAsset, seconds: Double) async throws -> [String: Any] {
        let item = AVPlayerItem(asset: prepared.asset)
        item.preferredForwardBufferDuration = 3
        let player = AVPlayer(playerItem: item)
        player.isMuted = false
        player.volume = 1
        var streamError: Error?
        let observer = NotificationCenter.default.addObserver(forName: .encryptedPlaybackFailed, object: prepared.asset, queue: .main) { notification in
            streamError = notification.userInfo?[NSUnderlyingErrorKey] as? Error
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            player.pause()
            player.replaceCurrentItem(with: nil)
            videoLayer?.player = nil
            if let file = prepared.decryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: file) }
        }
        try attach(player)
        player.play()
        let readyDeadline = Date().addingTimeInterval(25)
        while item.status != .readyToPlay || videoLayer?.isReadyForDisplay != true {
            if let error = streamError ?? item.error { throw error }
            if Date() > readyDeadline { throw NSError(domain: "ExpandedPlayback", code: 2, userInfo: [NSLocalizedDescriptionKey: "Video first frame timeout"]) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let videos = try await item.asset.loadTracks(withMediaType: .video)
        let audios = try await item.asset.loadTracks(withMediaType: .audio)
        guard let video = videos.first, !audios.isEmpty else { throw NSError(domain: "ExpandedPlayback", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing video/audio track"]) }
        let size = try await video.load(.naturalSize)
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { throw NSError(domain: "ExpandedPlayback", code: 4) }
        let target = min(seconds, max(0.5, duration - 0.5))
        let deadline = Date().addingTimeInterval(target + 20)
        while player.currentTime().seconds < target {
            if let error = streamError ?? item.error { throw error }
            if Date() > deadline { throw NSError(domain: "ExpandedPlayback", code: 5, userInfo: [NSLocalizedDescriptionKey: "Playback progress stalled"]) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        var result: [String: Any] = ["duration": duration, "position": player.currentTime().seconds, "actualResolution": Int(min(abs(size.width), abs(size.height))), "video": true, "audioTrack": true, "muted": player.isMuted]
        if let statistics = await PlaybackAssetFactory.statistics(for: prepared.asset) { result["streamStatistics"] = statistics }
        return result
    }

    func testLiveSavedAndFreshSessionsResolveSameEpisode() async throws {
        try live()
        let recoveryKey = "thl_tv_hongguo_guest_recovery_v2_at"
        let oldRecovery = UserDefaults.standard.object(forKey: recoveryKey)
        UserDefaults.standard.removeObject(forKey: recoveryKey)
        defer { if let oldRecovery { UserDefaults.standard.set(oldRecovery, forKey: recoveryKey) } else { UserDefaults.standard.removeObject(forKey: recoveryKey) } }
        let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain.contains("fqnovel") || $0.domain.contains("snssdk") }
        print("THL_SHARED_COOKIES count=\(cookies.count) names=\(cookies.map { $0.domain + ":" + $0.name }.sorted().joined(separator: ","))")
        let data = try await detail("7694896136963755032")
        let episode = try XCTUnwrap(data.episodes.first)
        for persistent in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let recorder = SourceDiagnostics()
            let bridge = NativeBridge(baseDirectory: root, diagnostics: recorder, diagnosticContext: "会话对比", persistentDeviceSession: persistent)
            let source = NativeRepository(bridge: bridge, playbackBridge: bridge)
            do {
                let plan = try await source.resolvePlayback(drama: data.drama, episode: episode, episodeIndex: 1)
                print("THL_SESSION_COMPARE saved=\(persistent) quality=\(plan.quality) success=true")
                XCTAssertEqual(plan.quality, 1080)
            } catch {
                for entry in recorder.entries { print("THL_SESSION_TRACE saved=\(persistent) stage=\(entry.stage) host=\(entry.host) status=\(entry.status) bytes=\(entry.bodyBytes ?? -1) code=\(entry.errorCode)") }
                print("THL_SESSION_COMPARE saved=\(persistent) success=false code=\((error as NSError).userInfo["diagnosticCode"] ?? "")")
                XCTFail(error.localizedDescription)
            }
        }
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

    func testLiveFullEpisodesPastThirtySecondsAndLegacyPreviewRecovery() async throws {
        try live()
        OfficialModelFailureProtocol.configure(blockReadingBatch: false, missingModel: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfficialModelFailureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = NativeBridge(baseDirectory: root, httpSession: session, diagnostics: SourceDiagnostics(), diagnosticContext: "完整分集验证", persistentDeviceSession: false)
        let source = NativeRepository(bridge: bridge, playbackBridge: bridge)
        for (series, number, minimumDuration) in [("7694896136963755032", 1, 150.0), ("7688558312157088793", 1, 120.0), ("7697541703539887129", 184, 60.0)] {
            let detail = try await source.loadDetail(drama: Drama(id: "hongguo:" + series, source: "hongguo", sourceId: series, title: "完整播放验证"))
            let original = try XCTUnwrap(detail.episodes.first { $0.number == number })
            let raw = try XCTUnwrap(original.rawChapter)
            let target = try XCTUnwrap(raw["url"] as? String)
            let vid = try XCTUnwrap(URL(string: target)?.pathComponents.last)
            let preview = "https://hongguoduanju.com/video/public/" + vid + "/360p.mp4"
            let legacy = Episode(id: original.id, title: original.title, number: original.number, raw: try JSONSerialization.data(withJSONObject: ["url": preview]))
            let episodes = detail.episodes.map { $0.number == number ? legacy : $0 }
            let suite = "THLRedLook.FullEpisode." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let model = PlayerViewModel(drama: detail.drama, allEpisodes: episodes, repository: source, preloadingRepository: source, store: LocalStore(defaults: defaults))
            model.danmakuEnabled = false
            defer { model.onDisappear() }
            await model.preparePlayback(episodeIndex: number)
            try await ready(model)
            XCTAssertGreaterThan(model.duration, minimumDuration)
            XCTAssertEqual(model.plan?.quality, 1080)
            XCTAssertEqual(model.selectedQuality, 1080)
            XCTAssertFalse(PlaybackPlan.isPublicPreviewURL(model.plan?.url ?? ""))
            XCTAssertFalse(model.plan?.decryptionKey.isEmpty ?? true)
            try await wait(seconds: 55) { model.currentTime > 32 && !model.isBuffering }
            XCTAssertEqual(model.currentEpisodeIndex, number)
            XCTAssertTrue(try XCTUnwrap(model.player).rate > 0)
            XCTAssertFalse(try XCTUnwrap(model.player).isMuted)
            XCTAssertNil(model.errorMessage)
            print("THL_FULL_EPISODE series=\(series) episode=\(number) quality=\(model.selectedQuality) duration=\(model.duration) naturalPosition=\(model.currentTime) legacyPreviewRecovered=true")
            if number == 184 {
                model.seekBy(seconds: max(0, model.duration - model.currentTime - 3))
                try await wait { model.currentEpisodeIndex == 185 && !model.isLoading && model.currentTime > 0.5 }
                try await ready(model)
                XCTAssertGreaterThan(model.duration, 30)
                XCTAssertEqual(model.selectedQuality, 1080)
            }
            model.onDisappear()
        }
        XCTAssertGreaterThanOrEqual(OfficialModelFailureProtocol.count, 1)
        XCTAssertEqual(OfficialModelFailureProtocol.webCount, 0)
    }

    func testEncryptedPlaybackRecoversLaterRangeFailures() async throws {
        guard let base = ProcessInfo.processInfo.environment["THL_FAULT_SERVER"] else { throw XCTSkip("Requires synthetic range server") }
        for mode in ["503", "403"] {
            _ = try await URLSession.shared.data(from: URL(string: base + "/reset")!)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let bridge = NativeBridge(baseDirectory: root, persistentDeviceSession: false)
            let script = """
            const meta={id:'synthetic',name:'Synthetic',version:'1.0.0'};
            let calls=0;
            const spider={play:async function(){calls++;return {url:'\(base)/video.mp4?attempt='+calls,decryptionKey:'00112233445566778899aabbccddeeff',quality:360,qualities:[360],expiresAt:Date.now()+60000};}};
            """
            _ = try await bridge.request(action: "jsSource.saveAndLoad", payload: ["fileName": "synthetic.js", "script": script])
            let source = NativeRepository(bridge: bridge, playbackBridge: bridge)
            let suite = "THLRedLook.Midstream." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let episode = Episode(id: "1", title: "合成分集", number: 1, raw: try JSONSerialization.data(withJSONObject: ["url": "1"]))
            let recorder = SourceDiagnostics()
            let model = PlayerViewModel(drama: Drama(id: "synthetic:stream", source: "synthetic", sourceId: "stream", title: "合成断流恢复"), allEpisodes: [episode], repository: source, preloadingRepository: source, store: LocalStore(defaults: defaults), diagnostics: recorder)
            model.danmakuEnabled = false
            defer { model.onDisappear() }
            await model.preparePlayback(episodeIndex: 1)
            try await ready(model)
            let player = try XCTUnwrap(model.player)
            let item = try XCTUnwrap(player.currentItem)
            let url = try XCTUnwrap(model.plan?.url)
            let position = model.currentTime
            let interruptedAt = Date()
            _ = try await URLSession.shared.data(from: URL(string: base + "/arm?mode=" + mode)!)
            try await wait(seconds: 35) { model.currentTime > position + 5 && !model.isLoading && (mode == "503" || model.plan?.url != url) }
            let (data, _) = try await URLSession.shared.data(from: URL(string: base + "/metrics")!)
            let metrics = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertGreaterThanOrEqual(metrics["failures"] as? Int ?? 0, mode == "503" ? 2 : 1)
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.currentEpisodeIndex, 1)
            XCTAssertTrue(model.player === player)
            XCTAssertFalse(player.isMuted)
            if mode == "503" {
                XCTAssertTrue(player.currentItem === item)
                XCTAssertEqual(model.plan?.url, url)
                XCTAssertTrue(recorder.entries.isEmpty)
            } else {
                XCTAssertFalse(player.currentItem === item)
                XCTAssertLessThan(Date().timeIntervalSince(interruptedAt), 12)
                XCTAssertTrue(recorder.entries.contains { $0.stage == "播放恢复 第1集" && $0.errorCode == "MEDIA_HTTP_403" })
                try await ready(model)
            }
            print("THL_MIDSTREAM mode=\(mode) failures=\(metrics["failures"] ?? 0) positionBefore=\(position) positionAfter=\(model.currentTime) sameItem=\(player.currentItem === item) manualRetry=false")
            model.onDisappear()
        }
    }

    func testPublicPreviewCannotBeReusedOrPreparedAsFullEpisode() async throws {
        let plan = PlaybackPlan(url: "https://hongguoduanju.com/video/public/7694898085759028248/360p.mp4", quality: 360)
        XCTAssertFalse(plan.isReusable())
        do {
            _ = try await PlaybackAssetFactory.prepare(plan)
            XCTFail("Preview must be rejected before AVPlayer setup")
        } catch {
            XCTAssertEqual((error as NSError).userInfo["diagnosticCode"] as? String, "PREVIEW_STREAM_REJECTED")
        }
        XCTAssertTrue(PlaybackPlan(url: "https://fixture.qznovelvod.com/full360.mp4", quality: 360).isReusable())
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

    private func repository(mode: String, recorder: SourceDiagnostics = SourceDiagnostics(), long: Bool = false) async throws -> (NativeRepository, NativeBridge) {
        guard let path = ProcessInfo.processInfo.environment[long ? "THL_SYNTHETIC_LONG_VIDEO" : "THL_SYNTHETIC_VIDEO"] else { throw XCTSkip("Requires generated video fixture") }
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
        case "transientWindow": behavior = "if(!firstFailure)firstFailure=Date.now();if(Date.now()-firstFailure<3000)throw Object.assign(new Error('synthetic temporary outage'),{code:'HTTP_503'});"
        case "retry": behavior = "if(id==='2'&&calls[id]===1)throw Object.assign(new Error('synthetic transient failure'),{code:'HTTP_503'});"
        case "error": behavior = "return {url:'',error:'MEDIA_HTTP_403'};"
        default: behavior = ""
        }
        let script = """
        const meta={id:'synthetic',name:'Synthetic',version:'1.0.0'};
        const calls={};
        let firstFailure=0;
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

    private func model(foreground: NativeRepository, preloading: NativeRepository, diagnostics: SourceDiagnostics = SourceDiagnostics()) throws -> PlayerViewModel {
        let suite = "THLRedLook.Continuous." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let episodes = try (1...4).map { index in
            Episode(id: String(index), title: "合成第\(index)集", number: index, raw: try JSONSerialization.data(withJSONObject: ["url": String(index)]))
        }
        let model = PlayerViewModel(drama: Drama(id: "synthetic:series", source: "synthetic", sourceId: "series", title: "合成连续播放"), allEpisodes: episodes, repository: foreground, preloadingRepository: preloading, store: LocalStore(defaults: defaults), diagnostics: diagnostics)
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

    func testTransientOutageRecoversAfterServerHasTimeToRecover() async throws {
        let (repository, _) = try await repository(mode: "transientWindow")
        let recorder = SourceDiagnostics()
        let model = try model(foreground: repository, preloading: repository, diagnostics: recorder)
        defer { model.onDisappear() }
        let start = Date()
        await model.preparePlayback(episodeIndex: 1)
        try await wait { !model.isLoading && model.currentTime > 0.5 }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 3)
        XCTAssertNil(model.errorMessage)
        let count = try await calls(repository, episode: 1)
        XCTAssertEqual(count, 4)
        XCTAssertEqual(recorder.entries.filter { $0.stage == "播放恢复 第1集" }.count, 3)
        print("THL_TRANSIENT_RECOVERY outageSeconds=3 automatic=true manualRetry=false")
    }

    func testStablePlaybackRestoresRecoveryBudgetAndPreservesPosition() async throws {
        let (repository, _) = try await repository(mode: "normal", long: true)
        let recorder = SourceDiagnostics()
        let model = try model(foreground: repository, preloading: repository, diagnostics: recorder)
        defer { model.onDisappear() }
        await model.preparePlayback(episodeIndex: 1)
        try await wait { !model.isLoading && model.currentTime > 0.5 }
        for burst in 0..<2 {
            for _ in 0..<3 {
                let item = try XCTUnwrap(model.player?.currentItem)
                let position = model.currentTime
                NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: item, userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: URLError(.networkConnectionLost)])
                try await wait { model.player?.currentItem !== item && !model.isLoading && model.currentTime > position + 0.2 }
                XCTAssertEqual(model.currentEpisodeIndex, 1)
                XCTAssertNil(model.errorMessage)
            }
            if burst == 0 {
                let position = model.currentTime
                try await wait(seconds: 15) { model.currentTime > position + 10.5 }
            }
        }
        let recoveries = recorder.entries.filter { $0.stage == "播放恢复 第1集" }
        XCTAssertEqual(recoveries.count, 6)
        XCTAssertTrue(recoveries[3].sessionStatus.contains("恢复=1，"))
        XCTAssertTrue(recoveries.allSatisfy { $0.errorCode == "MEDIA_NETWORK_1005" })
        print("THL_STABLE_RECOVERY interruptions=6 twoBursts=true progressPreserved=true automatic=true")
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
    private static var missingModel = false
    private static var blockedWeb = 0
    static func configure(blockReadingBatch: Bool, missingModel: Bool = false) { lock.lock();defer { lock.unlock() };self.blockReadingBatch = blockReadingBatch;self.missingModel = missingModel;blocked = 0;blockedWeb = 0 }
    static var webCount: Int { lock.lock();defer { lock.unlock() };return blockedWeb }
    static var count: Int { lock.lock();defer { lock.unlock() };return blocked }
    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock();defer { lock.unlock() }
        if request.url?.host == "hongguoduanju.com" { return true }
        guard request.url?.path.contains("/novel/player/multi_video_model/v1") == true else { return false }
        return request.url?.host == "api5-normal-sinfonlineb.fqnovel.com" || blockReadingBatch && request.url?.host == "reading.snssdk.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.lock()
        let web = request.url?.host == "hongguoduanju.com"
        if web { Self.blockedWeb += 1 } else { Self.blocked += 1 }
        let missing = Self.missingModel
        Self.lock.unlock()
        let body = missing ? Data("{\"code\":0,\"data\":{}}".utf8) : Data()
        if web {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Content-Length": String(body.count), "x-tt-logid": "synthetic-primary-empty"])!, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }
}
