import XCTest
import AVFoundation
import UIKit
@testable import THLRedLook

@MainActor
final class StartupPerformanceTests: XCTestCase {
    private var view: UIView?
    private var layer: AVPlayerLayer?
    private let key = "00112233445566778899aabbccddeeff"
    private let headers = ["X-THL-Synthetic": "cenc-flow"]

    private func wait(seconds: Double = 35, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(condition())
        if !condition() { throw NSError(domain: "StartupPerformanceTests", code: 1) }
    }

    private func attach(_ player: AVPlayer) throws {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let view = UIView(frame: CGRect(x: 80, y: 80, width: 640, height: 360))
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        try XCTUnwrap(window).addSubview(view)
        self.layer?.removeFromSuperlayer()
        self.view?.removeFromSuperview()
        self.view = view
        self.layer = layer
    }

    private func clean(_ player: AVPlayer) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        layer?.player = nil
        layer?.removeFromSuperlayer()
        view?.removeFromSuperview()
        layer = nil
        view = nil
    }

    private func endpoint(_ path: String) throws -> String {
        guard let base = ProcessInfo.processInfo.environment["STARTUP_SYNTHETIC_BASE"] else { throw XCTSkip("Synthetic range server not supplied") }
        return base + path
    }

    func testSyntheticStreamingFirstFrameAudioAndSeekBeforeFullDownload() async throws {
        let plan = PlaybackPlan(url: try endpoint("/slow.mp4"), headers: headers, decryptionKey: key, mediaBytes: 10_992_725)
        let start = Date()
        let prepared = try await PlaybackAssetFactory.prepare(plan)
        XCTAssertNil(prepared.decryptedURL)
        XCTAssertEqual(prepared.asset.url.scheme, "thlcenc")
        let preparedMs = Date().timeIntervalSince(start) * 1000
        let item = AVPlayerItem(asset: prepared.asset)
        item.preferredForwardBufferDuration = 3
        let player = AVPlayer(playerItem: item)
        defer { clean(player) }
        try attach(player)
        player.playImmediately(atRate: 1)
        try await wait { self.layer?.isReadyForDisplay == true && player.currentTime().seconds > 0.2 }
        let firstFrameMs = Date().timeIntervalSince(start) * 1000
        let audio = try await prepared.asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(audio.isEmpty)
        let rawStats = await PlaybackAssetFactory.statistics(for: prepared.asset)
        let stats = try XCTUnwrap(rawStats)
        XCTAssertLessThan(stats["bytesFetched"]!, stats["mediaBytes"]! / 2)
        await player.seek(to: CMTime(seconds: 65, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.playImmediately(atRate: 1)
        try await wait { player.currentTime().seconds > 65.2 && self.layer?.isReadyForDisplay == true }
        print("THL_STARTUP_SYNTH preparedMs=\(Int(preparedMs)) firstFrameMs=\(Int(firstFrameMs)) bytes=\(stats["bytesFetched"]!) media=\(stats["mediaBytes"]!) audio=\(audio.count) seek=true")
    }

    func testNoRangeServerKeepsWholeFileFallback() async throws {
        let prepared = try await PlaybackAssetFactory.prepare(PlaybackPlan(url: try endpoint("/no-range.mp4"), headers: headers, decryptionKey: key))
        let local = try XCTUnwrap(prepared.decryptedURL)
        defer { CENCMP4Decryptor.shared.removePlaybackCache(at: local) }
        XCTAssertEqual(prepared.asset.url.scheme, "file")
        let audio = try await prepared.asset.loadTracks(withMediaType: .audio)
        let video = try await prepared.asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(audio.isEmpty)
        XCTAssertFalse(video.isEmpty)
    }

    func testStreamingFeedPoolRetainsDecryptionLoader() async throws {
        let plan = PlaybackPlan(url: try endpoint("/fast.mp4"), headers: headers, decryptionKey: key)
        let prepared = try await PlaybackAssetFactory.prepare(plan)
        VideoCacheManager.shared.preload(asset: prepared.asset, for: plan.url, namespace: "startup-test")
        defer { VideoCacheManager.shared.clearNamespace("startup-test") }
        let player = try XCTUnwrap(VideoCacheManager.shared.cachedPlayer(for: plan.url, namespace: "startup-test"))
        XCTAssertTrue(player.currentItem?.asset === prepared.asset)
        XCTAssertNil(VideoCacheManager.shared.cachedPlayer(for: plan.url, namespace: "other"))
        let stats = await PlaybackAssetFactory.statistics(for: prepared.asset)
        XCTAssertNotNil(stats)
    }

    func testWholeFilePreparationBaseline() async throws {
        guard ProcessInfo.processInfo.environment["STARTUP_WHOLE_BASELINE"] == "1" else { throw XCTSkip("Whole-file baseline not requested") }
        let start = Date()
        let local = try await CENCMP4Decryptor.shared.decrypt(remoteURL: URL(string: try endpoint("/slow.mp4"))!, headers: headers, hexKey: key, mediaBytes: 10_992_725)
        defer { CENCMP4Decryptor.shared.removePlaybackCache(at: local) }
        print("THL_STARTUP_BASELINE prepareMs=\(Int(Date().timeIntervalSince(start) * 1000)) media=10992725")
    }

    func testLiveFullCatalogAndThreeStreamingStarts() async throws {
        guard ProcessInfo.processInfo.environment["STARTUP_LIVE"] == "1" else { throw XCTSkip("Live App verification not requested") }
        let repo = NativeRepository.shared
        let start = Date()
        let first = try await repo.loadCatalog(source: "hongguo", category: "app:discover:all", force: true)
        guard first.items.count >= 12 else { return XCTFail("首批剧集不足一屏: \(first.items.count)") }
        print("THL_STARTUP_CATALOG count=\(first.items.count) ms=\(Int(Date().timeIntervalSince(start)*1000)) page=\(first.page)")
        let second = try await repo.loadCatalog(source: "hongguo", category: "app:discover:all", page: 2)
        XCTAssertTrue(Set(first.items.map(\.id)).intersection(second.items.map(\.id)).isEmpty)
        let name = "THLRedLook.QA.Startup." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LocalStore(defaults: defaults, cloudUpload: { _ in })
        for index in [0, 5, 11] {
            let detailStart = Date()
            let detail = try await repo.loadDetail(drama: first.items[index])
            let detailMs = Int(Date().timeIntervalSince(detailStart)*1000)
            let model = PlayerViewModel(drama: detail.drama, allEpisodes: detail.episodes, repository: repo, store: store)
            model.danmakuEnabled = false
            let playStart = Date()
            await model.preparePlayback(episodeIndex: 1)
            let player = try XCTUnwrap(model.player)
            try attach(player)
            try await wait { self.layer?.isReadyForDisplay == true && model.currentTime > 0.2 && !model.isLoading }
            let elapsed = Int(Date().timeIntervalSince(playStart)*1000)
            let asset = try XCTUnwrap(player.currentItem?.asset)
            let stats = await PlaybackAssetFactory.statistics(for: asset)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertFalse(audio.isEmpty)
            if !(model.plan?.decryptionKey.isEmpty ?? true) { XCTAssertNotNil(stats) }
            print("THL_STARTUP_LIVE index=\(index) detailMs=\(detailMs) firstFrameMs=\(elapsed) audio=\(audio.count) bytes=\(stats?["bytesFetched"] ?? 0) media=\(stats?["mediaBytes"] ?? 0)")
            if index == 0, detail.episodes.count > 1 {
                model.seekTo(target: max(0, model.duration - 1))
                try await wait(seconds: 45) { model.currentEpisodeIndex == 2 && model.currentTime > 0.2 && !model.isLoading }
                let next = try XCTUnwrap(model.player)
                try attach(next)
                try await wait { self.layer?.isReadyForDisplay == true }
                print("THL_STARTUP_CONTINUOUS episode=2 rendered=true")
                model.onDisappear()
                clean(next)
            } else {
                model.onDisappear()
            }
            clean(player)
        }
    }

    func testLongSeriesPlaybackBeyondEpisode100() async throws {
        guard ProcessInfo.processInfo.environment["LONG_SERIES_LIVE"] == "1" else { throw XCTSkip("Requires live official source") }
        let repo = NativeRepository.shared
        let drama = Drama(id: "hongguo:7673742740500270105", source: "hongguo", title: "觉醒伪神：神明弃我我自为神", episodes: 127)
        let detail = try await repo.loadDetail(drama: drama)
        XCTAssertEqual(detail.episodes.count, 127)
        let name = "THLRedLook.QA.LongSeries." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LocalStore(defaults: defaults, cloudUpload: { _ in })
        for number in [99, 100, 101, 110, 127] {
            let model = PlayerViewModel(drama: detail.drama, allEpisodes: detail.episodes, repository: repo, store: store)
            model.danmakuEnabled = false
            let started = Date()
            await model.preparePlayback(episodeIndex: number)
            let player = try XCTUnwrap(model.player)
            try attach(player)
            try await wait { self.layer?.isReadyForDisplay == true && model.currentTime > 0.2 && !model.isLoading }
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(model.plan!.headers.keys.contains { $0.lowercased() == "referer" })
            let audio = try await player.currentItem!.asset.loadTracks(withMediaType: .audio)
            XCTAssertFalse(audio.isEmpty)
            print("THL_LONG_SERIES episode=\(number) frameMs=\(Int(Date().timeIntervalSince(started)*1000)) audio=\(audio.count)")
            if number == 100 {
                model.seekTo(target: max(0, model.duration - 1))
                try await wait(seconds: 45) { model.currentEpisodeIndex == 101 && model.currentTime > 0.2 && !model.isLoading }
                let next = try XCTUnwrap(model.player)
                try attach(next)
                try await wait { self.layer?.isReadyForDisplay == true }
                print("THL_LONG_SERIES continuous=100-to-101 rendered=true")
                model.onDisappear()
                clean(next)
            } else { model.onDisappear() }
            clean(player)
        }
    }
}
