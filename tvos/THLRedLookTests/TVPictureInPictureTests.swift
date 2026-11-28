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

    func testRestoreFromPiPPreservesActivePlayerItemWithoutBlackScreen() throws {
        let item = AVPlayerItem(url: URL(string: "https://example.com/pip_restore.mp4")!)
        let player = AVPlayer(playerItem: item)
        let hostView = TVGlobalPiPHostUIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        coordinator.bindGlobalHost(view: hostView)

        let drama = Drama(id: "pip_restore_drama", source: "hongguo", title: "恢复不黑屏测试", episodes: 3)
        let episodes = [Episode(id: "1", title: "第1集", number: 1)]
        let layer = AVPlayerLayer(player: player)
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: layer) else {
            return
        }

        coordinator.register(
            controller: controller,
            player: player,
            drama: drama,
            currentEpisodeIndex: 1,
            allEpisodes: episodes,
            initialPosition: 10.0
        )
        hostView.attachPlayer(player)
        coordinator.pictureInPictureControllerWillStartPictureInPicture(controller)
        coordinator.pictureInPictureControllerDidStartPictureInPicture(controller)

        // 模拟用户从画中画点恢复全屏
        var restoredHandlerCalled = false
        coordinator.pictureInPictureController(controller) { success in
            restoredHandlerCalled = success
        }
        XCTAssertTrue(coordinator.isRestoring)
        XCTAssertTrue(coordinator.hasRestoreCompletionHandler)

        // PlayerViewModel.onAppear 调用 checkRestorePiP 并随后调用 completeRestore(success: true)
        let playerPiP = PlayerPiPCoordinator()
        let restored = try XCTUnwrap(playerPiP.checkRestorePiP(dramaId: drama.id))
        XCTAssertTrue(restored.player === player)
        coordinator.completeRestore(success: true)
        XCTAssertTrue(restoredHandlerCalled)
        XCTAssertTrue(coordinator.isRestoring, "completeRestore 在 didStop 回调前不得过早清除 isRestoring")

        // 系统随后异步结束画中画回调 didStopPictureInPicture：必须解绑后台宿主图层，但绝不能置空 currentItem
        coordinator.pictureInPictureControllerDidStopPictureInPicture(controller)
        XCTAssertFalse(coordinator.isRestoring)
        XCTAssertFalse(coordinator.isPictureInPictureActive)
        XCTAssertNil(hostView.playerLayer.player, "退出画中画后后台1x1宿主图层必须解绑")
        XCTAssertNotNil(player.currentItem, "恢复全屏绝不能清空原 AVPlayer 的 currentItem 导致黑屏")
    }

    func testStartingDifferentVideoStopsCompetingPiPToPreventDualPlayback() {
        let item = AVPlayerItem(url: URL(string: "https://example.com/pip_competing.mp4")!)
        let player = AVPlayer(playerItem: item)
        let hostView = TVGlobalPiPHostUIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        coordinator.bindGlobalHost(view: hostView)

        let dramaA = Drama(id: "pip_drama_a", source: "hongguo", title: "剧A", episodes: 2)
        let layer = AVPlayerLayer(player: player)
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: layer) else {
            return
        }

        coordinator.register(
            controller: controller,
            player: player,
            drama: dramaA,
            currentEpisodeIndex: 1,
            allEpisodes: [Episode(id: "1", title: "第1集", number: 1)],
            initialPosition: 5.0
        )
        hostView.attachPlayer(player)
        coordinator.pictureInPictureControllerWillStartPictureInPicture(controller)
        coordinator.pictureInPictureControllerDidStartPictureInPicture(controller)
        XCTAssertTrue(coordinator.isPictureInPictureActive)

        // 用户切换到另一部剧 B 播放时，必须立即停掉剧 A 的小窗播放器，避免两个视频同时播放
        let playerPiP = PlayerPiPCoordinator()
        playerPiP.stopCompetingPiPIfNeeded(forDramaId: "pip_drama_b")
        XCTAssertFalse(coordinator.isPictureInPictureActive)
        XCTAssertNil(coordinator.activePlayer)
        XCTAssertNil(hostView.playerLayer.player)
        XCTAssertNil(player.currentItem)
    }
}
