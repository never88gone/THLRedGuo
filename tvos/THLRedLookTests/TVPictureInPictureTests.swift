import XCTest
import AVKit
import SwiftUI
@testable import THLRedLook

@MainActor
final class TVPictureInPictureTests: XCTestCase {
    private var coordinator: TVPictureInPictureCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        coordinator = TVPictureInPictureCoordinator.shared
    }

    func testCoordinatorInitialState() {
        XCTAssertNotNil(coordinator)
        XCTAssertEqual(coordinator.isPictureInPictureActive, false)
        XCTAssertEqual(coordinator.isStartingPiP, false)
        XCTAssertEqual(coordinator.shouldRestoreFullScreen, false)
    }

    func testSessionRegistrationAndUpdateProgress() {
        let drama = Drama(
            id: "pip_test_drama_01",
            source: "hongguo",
            title: "画中画测试短剧",
            description: "画中画功能测试简介",
            cover: "https://example.com/cover.jpg",
            episodes: 20
        )
        let episodes = (1...20).map { Episode(id: "ep_\($0)", title: "第 \($0) 集", number: $0) }
        let player = AVPlayer()

        let playerLayer = AVPlayerLayer(player: player)
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }
        let controller = AVPictureInPictureController(playerLayer: playerLayer)!

        coordinator.register(
            controller: controller,
            player: player,
            drama: drama,
            currentEpisodeIndex: 3,
            allEpisodes: episodes,
            initialPosition: 15.0
        )

        XCTAssertNotNil(coordinator.currentSession)
        XCTAssertEqual(coordinator.currentSession?.drama.id, "pip_test_drama_01")
        XCTAssertEqual(coordinator.currentSession?.episodeIndex, 3)
        XCTAssertEqual(coordinator.currentSession?.currentPosition, 15.0)

        // 测试进度更新
        coordinator.updatePlaybackProgress(position: 45.0)
        XCTAssertEqual(coordinator.currentSession?.currentPosition, 45.0)

        // 测试注销
        coordinator.unregister(controller: controller)
        XCTAssertNil(coordinator.activeController)
        XCTAssertNil(coordinator.currentSession)
    }

    func testPictureInPictureLifecycleCallbacks() {
        let drama = Drama(
            id: "pip_test_drama_02",
            source: "hongguo",
            title: "画中画生命周期测试",
            description: "生命周期回调验证",
            cover: "https://example.com/cover.jpg",
            episodes: 10
        )
        let episodes = (1...10).map { Episode(id: "ep_\($0)", title: "第 \($0) 集", number: $0) }
        let player = AVPlayer()
        let playerLayer = AVPlayerLayer(player: player)
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: playerLayer)!

        coordinator.register(
            controller: controller,
            player: player,
            drama: drama,
            currentEpisodeIndex: 1,
            allEpisodes: episodes,
            initialPosition: 0
        )

        // 模拟即将启动
        coordinator.pictureInPictureControllerWillStartPictureInPicture(controller)
        XCTAssertTrue(coordinator.isStartingPiP)
        XCTAssertFalse(coordinator.isPictureInPictureActive)

        // 模拟成功启动
        coordinator.pictureInPictureControllerDidStartPictureInPicture(controller)
        XCTAssertFalse(coordinator.isStartingPiP)
        XCTAssertTrue(coordinator.isPictureInPictureActive)

        // 模拟全屏恢复请求
        var restoredSuccess: Bool? = nil
        coordinator.pictureInPictureController(controller) { success in
            restoredSuccess = success
        }
        XCTAssertTrue(coordinator.shouldRestoreFullScreen)

        // 调用完成全屏恢复
        coordinator.completeRestore(success: true)
        XCTAssertEqual(restoredSuccess, true)
        XCTAssertFalse(coordinator.shouldRestoreFullScreen)

        // 模拟画中画停止
        coordinator.pictureInPictureControllerDidStopPictureInPicture(controller)
        XCTAssertFalse(coordinator.isPictureInPictureActive)
    }

    func testRestoreHandledMechanism() {
        let player = AVPlayer()
        let playerLayer = AVPlayerLayer(player: player)
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            coordinator.shouldRestoreFullScreen = true
            coordinator.markRestoreHandled()
            XCTAssertFalse(coordinator.shouldRestoreFullScreen)
            return
        }

        coordinator.pictureInPictureController(controller) { _ in }
        XCTAssertTrue(coordinator.shouldRestoreFullScreen)

        coordinator.markRestoreHandled()
        XCTAssertFalse(coordinator.shouldRestoreFullScreen)
    }

    func testPiPContinuousPlaybackNextEpisode() async {
        let drama = Drama(
            id: "pip_test_drama_03",
            source: "hongguo",
            title: "画中画连播测试",
            description: "连续播放验证",
            cover: "https://example.com/cover.jpg",
            episodes: 5
        )
        let episodes = (1...5).map { Episode(id: "ep_\($0)", title: "第 \($0) 集", number: $0) }
        let player = AVPlayer()
        let playerLayer = AVPlayerLayer(player: player)
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: playerLayer)!

        coordinator.register(
            controller: controller,
            player: player,
            drama: drama,
            currentEpisodeIndex: 2,
            allEpisodes: episodes,
            initialPosition: 100.0
        )

        // 验证切集前
        XCTAssertEqual(coordinator.currentSession?.episodeIndex, 2)

        // 触发画中画连续切集
        await coordinator.playNextEpisodeInPiP()

        // 验证当前集数已切到第 3 集，播放进度复位为 0
        XCTAssertEqual(coordinator.currentSession?.episodeIndex, 3)
        XCTAssertEqual(coordinator.currentSession?.currentPosition, 0)
    }
}
