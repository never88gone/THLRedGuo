import Foundation
import AVKit
import Combine
import SwiftUI

/// tvOS 原生系统画中画 (Picture in Picture) 全局协调器
@MainActor
public final class TVPictureInPictureCoordinator: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    public static let shared = TVPictureInPictureCoordinator()

    /// 设备是否支持系统画中画
    public var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// 当前画中画是否处于活跃运行状态
    @Published public private(set) var isPictureInPictureActive: Bool = false

    /// 是否正在进入画中画过渡期
    @Published public private(set) var isStartingPiP: Bool = false

    /// 当前画中画会话数据
    @Published public private(set) var currentSession: TVPictureInPictureSession?

    /// 请求恢复全屏播放界面的信号
    @Published public var shouldRestoreFullScreen: Bool = false

    /// 全局常驻宿主视图 (挂载在 MainTabView，永不被销毁)
    public private(set) weak var globalHostView: TVGlobalPiPHostUIView?

    /// 当前绑定的控制器与播放器
    public private(set) weak var activeController: AVPictureInPictureController?
    public private(set) var activePlayer: AVPlayer?

    private var restoreCompletionHandler: ((Bool) -> Void)?
    private var progressSaveTimer: Timer?
    private var isRestoring: Bool = false
    private var isSwitchingNextEpisodeInPiP: Bool = false

    public override init() {
        super.init()
        setupItemEndNotification()
    }

    private func setupItemEndNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlayerItemDidPlayToEndTime(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    // MARK: - 全局常驻宿主绑定

    public func bindGlobalHost(view: TVGlobalPiPHostUIView) {
        self.globalHostView = view
        if let controller = view.pipController {
            controller.delegate = self
            self.activeController = controller
        }
        NSLog("🎬 [TVPiPCoordinator] 成功绑定常驻全局画中画宿主容器")
    }

    // MARK: - 控制器与播放上下文注册

    public func register(
        controller: AVPictureInPictureController? = nil,
        player: AVPlayer,
        drama: Drama,
        currentEpisodeIndex: Int,
        allEpisodes: [Episode],
        initialPosition: Double = 0,
        playbackPlan: PlaybackPlan? = nil
    ) {
        let targetController = controller ?? globalHostView?.pipController

        // 关键防抖：如果画中画未处于激活状态，且播放的剧集、集数、播放源与控制器均未改变，直接复用既有会话，
        // 严禁在此高频重复给 @Published currentSession 赋值，彻底杜绝引发 SwiftUI 根视图 AttributeGraph 无限重绘死循环
        if let current = self.currentSession,
           current.drama.id == drama.id,
           current.episodeIndex == currentEpisodeIndex,
           current.playbackPlan?.url == playbackPlan?.url,
           self.activeController === targetController,
           self.activePlayer === player,
           !isPictureInPictureActive {
            return
        }

        if let ctrl = targetController, self.activeController !== ctrl {
            self.activeController = ctrl
            ctrl.delegate = self
        }
        if self.activePlayer !== player {
            self.activePlayer = player
        }

        let newSession = TVPictureInPictureSession(
            drama: drama,
            episodeIndex: currentEpisodeIndex,
            allEpisodes: allEpisodes,
            currentPosition: initialPosition,
            playbackPlan: playbackPlan
        )
        if self.currentSession != newSession {
            self.currentSession = newSession
        }
    }

    public func unregister(controller: AVPictureInPictureController) {
        guard activeController === controller else { return }
        if !isPictureInPictureActive && !isStartingPiP {
            self.activeController = nil
            self.activePlayer = nil
            self.currentSession = nil
        }
    }

    /// 退出全屏播放器时清理上下文（画中画未激活时彻底释放对播放器和会话的强引用）
    public func unregisterPlaybackContext() {
        if !isPictureInPictureActive && !isStartingPiP {
            self.activeController = nil
            self.activePlayer = nil
            self.currentSession = nil
            self.globalHostView?.detachPlayer()
        }
    }

    // MARK: - 触发操作

    public func startPictureInPicture(
        player: AVPlayer? = nil,
        drama: Drama? = nil,
        currentEpisodeIndex: Int? = nil,
        allEpisodes: [Episode]? = nil,
        initialPosition: Double? = nil,
        playbackPlan: PlaybackPlan? = nil
    ) {
        guard isPictureInPictureSupported else {
            NSLog("⚠️ [TVPiPCoordinator] 当前环境不支持画中画")
            return
        }

        if let p = player, let d = drama, let ep = currentEpisodeIndex, let eps = allEpisodes {
            register(
                player: p,
                drama: d,
                currentEpisodeIndex: ep,
                allEpisodes: eps,
                initialPosition: initialPosition ?? 0,
                playbackPlan: playbackPlan
            )
        }

        // 优先使用全局常驻宿主挂接播放器启动画中画（保障退出全屏后图层依然存活）
        if let host = globalHostView, let globalPip = host.pipController {
            host.attachPlayer(self.activePlayer)
            self.activeController = globalPip
            globalPip.delegate = self

            if globalPip.isPictureInPicturePossible {
                isStartingPiP = true
                globalPip.startPictureInPicture()
                NSLog("🎬 [TVPiPCoordinator] 通过全局宿主启动系统画中画")
                return
            }
        }

        // 回退机制：使用局部注册的控制器启动
        guard let controller = activeController, controller.isPictureInPicturePossible else {
            NSLog("⚠️ [TVPiPCoordinator] 画中画暂不可用 (尚未就绪)")
            return
        }
        isStartingPiP = true
        controller.startPictureInPicture()
        NSLog("🎬 [TVPiPCoordinator] 通过局部控制器启动系统画中画")
    }

    public func stopPictureInPicture() {
        globalHostView?.pipController?.stopPictureInPicture()
        activeController?.stopPictureInPicture()
        isPictureInPictureActive = false
        isStartingPiP = false

        if !isRestoring {
            // 主动停止且非全屏恢复时，立即停止音频与播放器，消除残留声音
            activePlayer?.pause()
            activePlayer?.replaceCurrentItem(with: nil)
            globalHostView?.detachPlayer()
            activePlayer = nil
            currentSession = nil
        }
    }

    public func updatePlaybackProgress(position: Double) {
        if var session = currentSession {
            session.currentPosition = position
            self.currentSession = session
        }
    }

    public func markRestoreHandled() {
        shouldRestoreFullScreen = false
    }

    public func completeRestore(success: Bool) {
        shouldRestoreFullScreen = false
        if let completion = restoreCompletionHandler {
            completion(success)
            restoreCompletionHandler = nil
        }
        isRestoring = false
    }

    // MARK: - 画中画模式下的自动连续播放功能

    @objc private func handlePlayerItemDidPlayToEndTime(_ notification: Notification) {
        Task { @MainActor in
            guard self.isPictureInPictureActive, !self.isStartingPiP else { return }
            guard let endedItem = notification.object as? AVPlayerItem,
                  let currentItem = self.activePlayer?.currentItem,
                  endedItem === currentItem else { return }
            await self.playNextEpisodeInPiP()
        }
    }

    public func playNextEpisodeInPiP() async {
        guard !isSwitchingNextEpisodeInPiP else { return }
        guard let session = currentSession else { return }
        guard session.episodeIndex < session.allEpisodes.count else {
            NSLog("🎬 [TVPiPCoordinator] 画中画已连播至全剧最后一集 (%d 集)", session.allEpisodes.count)
            saveCurrentProgressToStore()
            return
        }

        isSwitchingNextEpisodeInPiP = true
        defer { isSwitchingNextEpisodeInPiP = false }

        let nextIndex = session.episodeIndex + 1
        let nextEp = session.allEpisodes.first { $0.number == nextIndex }
        NSLog("🎬 [TVPiPCoordinator] 画中画自动切集: 即将播放第 %d 集 · %@", nextIndex, session.drama.title)

        do {
            let plan = try await NativeRepository.shared.resolvePlayback(
                drama: session.drama,
                episode: nextEp,
                episodeIndex: nextIndex,
                quality: 0
            )
            let prepared = try await PlaybackAssetFactory.prepare(plan)
            let newItem = AVPlayerItem(asset: prepared.asset)

            self.activePlayer?.replaceCurrentItem(with: newItem)
            self.activePlayer?.play()

            self.currentSession?.episodeIndex = nextIndex
            self.currentSession?.currentPosition = 0
            self.currentSession?.playbackPlan = plan

            saveCurrentProgressToStore()
            NSLog("🎬 [TVPiPCoordinator] 画中画已起播第 %d 集", nextIndex)
        } catch {
            NSLog("❌ [TVPiPCoordinator] 画中画切下一集失败: %@", error.localizedDescription)
        }
    }

    // MARK: - AVPictureInPictureControllerDelegate 回调

    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        NSLog("🎬 [TVPiPCoordinator] 即将启动画中画")
        isStartingPiP = true
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        NSLog("🎬 [TVPiPCoordinator] 画中画已成功启动")
        isStartingPiP = false
        isPictureInPictureActive = true
        startPeriodicProgressSaving()
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        NSLog("❌ [TVPiPCoordinator] 画中画启动失败: %@", error.localizedDescription)
        isStartingPiP = false
        isPictureInPictureActive = false
        globalHostView?.detachPlayer()
    }

    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        NSLog("🎬 [TVPiPCoordinator] 即将退出画中画")
        stopPeriodicProgressSaving()
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        NSLog("🎬 [TVPiPCoordinator] 画中画已退出 (isRestoring=%@)", String(describing: isRestoring))
        isPictureInPictureActive = false
        isStartingPiP = false

        if !isRestoring {
            // 用户从小窗直接点击关闭或者系统停止小窗，保存历史记录并彻底暂停清理播放器，杜绝声音残留
            saveCurrentProgressToStore()
            activePlayer?.pause()
            activePlayer?.replaceCurrentItem(with: nil)
            globalHostView?.detachPlayer()
            activePlayer = nil
            activeController = nil
            currentSession = nil
        }
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        NSLog("🎬 [TVPiPCoordinator] 收到从小窗全屏恢复请求")
        isRestoring = true
        restoreCompletionHandler = completionHandler
        shouldRestoreFullScreen = true
    }

    // MARK: - 内部进度保存与生命周期支持

    private func startPeriodicProgressSaving() {
        stopPeriodicProgressSaving()
        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveCurrentProgressToStore()
            }
        }
    }

    private func stopPeriodicProgressSaving() {
        progressSaveTimer?.invalidate()
        progressSaveTimer = nil
    }

    private func saveCurrentProgressToStore() {
        guard let session = currentSession, let player = activePlayer else { return }
        let seconds = CMTimeGetSeconds(player.currentTime())
        let dur = CMTimeGetSeconds(player.currentItem?.duration ?? .zero)
        let effectivePos = seconds.isFinite && seconds > 0 ? seconds : session.currentPosition
        let effectiveDur = dur.isFinite && dur > 0 ? dur : 0

        LocalStore.shared.recordWatch(
            drama: session.drama,
            episode: session.episodeIndex,
            position: effectivePos,
            duration: effectiveDur
        )
    }
}

// MARK: - SwiftUI 预览组件 (满足单文件单类/视图且附带预览规范)

public struct TVPictureInPictureCoordinatorPreviewView: View {
    @ObservedObject var coordinator = TVPictureInPictureCoordinator.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Text("画中画全局协调器预览")
                .font(.title2)
                .bold()
                .foregroundColor(TVColors.textPrimary)

            HStack(spacing: 16) {
                Text("硬件支持: \(coordinator.isPictureInPictureSupported ? "是" : "否")")
                Text("活跃状态: \(coordinator.isPictureInPictureActive ? "进行中" : "未激活")")
            }
            .font(.callout)
            .foregroundColor(TVColors.textSecondary)

            if let session = coordinator.currentSession {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前剧集: \(session.drama.title)")
                    Text("集数: 第 \(session.episodeIndex) 集")
                    Text("当前进度: \(Int(session.currentPosition)) 秒")
                }
                .padding()
                .background(TVColors.surfaceCard)
                .cornerRadius(12)
            }
        }
        .padding(40)
        .background(TVColors.background)
    }
}

#Preview {
    TVPictureInPictureCoordinatorPreviewView()
}
