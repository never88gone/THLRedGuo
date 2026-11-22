import UIKit
import AVKit
import SwiftUI
import Combine

/// tvOS 系统原生播放视图控制器（完全对齐 ATV-Bilibili-demo 与系统 AVPlayer 质感）
public final class TVSystemPlayerViewController: UIViewController {
    public let playerVC = AVPlayerViewController()
    private let viewModel: PlayerViewModel
    private let onDismiss: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private let relatedCoordinator = PlayerRelatedDramasCoordinator()

    private var episodeInfoVC: TVSystemEpisodeInfoViewController?
    private var relatedInfoVC: TVSystemRelatedInfoViewController?
    private var actionInfoVC: TVSystemActionInfoViewController?
    private var danmakuHostingController: UIHostingController<AnyView>?

    public init(viewModel: PlayerViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = TVColors.uiBlack

        setupPlayerVC()
        setupCustomInfoTabs()
        setupTransportBarMenus()
        setupDanmakuOverlay()
        observeViewModel()
        loadRelatedDramas()

        // 遥控器 Menu 返回手势
        let menuTap = UITapGestureRecognizer(target: self, action: #selector(handleMenuTap))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuTap)
    }

    @objc private func handleMenuTap() {
        onDismiss()
    }

    private func setupPlayerVC() {
        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)

        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        playerVC.showsPlaybackControls = true
        playerVC.allowsPictureInPicturePlayback = true
        playerVC.player = viewModel.player
        updateMetadata()
    }

    private func setupCustomInfoTabs() {
        let epVC = TVSystemEpisodeInfoViewController(viewModel: viewModel)
        self.episodeInfoVC = epVC

        let relVC = TVSystemRelatedInfoViewController(viewModel: viewModel)
        self.relatedInfoVC = relVC

        let actVC = TVSystemActionInfoViewController(viewModel: viewModel)
        self.actionInfoVC = actVC

        playerVC.customInfoViewControllers = [epVC, relVC, actVC]
    }

    public func setupTransportBarMenus() {
        let menus = TVSystemPlayerMenuBuilder.buildMenus(
            playbackRate: Float(viewModel.playbackRate),
            currentQuality: viewModel.selectedQuality,
            availableQualities: viewModel.plan?.qualities ?? [1080, 720, 0],
            danmakuEnabled: viewModel.danmakuEnabled,
            danmakuLanes: viewModel.danmakuStyle.laneCount,
            onSelectRate: { [weak self] rate in
                self?.viewModel.setRate(rate)
                self?.setupTransportBarMenus()
            },
            onSelectQuality: { [weak self] quality in
                Task { @MainActor [weak self] in
                    await self?.viewModel.changeQuality(quality)
                    self?.setupTransportBarMenus()
                }
            },
            onToggleDanmaku: { [weak self] enabled in
                self?.viewModel.toggleDanmaku()
                self?.setupTransportBarMenus()
            },
            onSelectDanmakuLanes: { [weak self] lanes in
                self?.viewModel.danmakuStyle.laneCount = lanes
                self?.setupTransportBarMenus()
            }
        )
        playerVC.transportBarCustomMenuItems = menus
    }

    private func setupDanmakuOverlay() {
        guard let overlay = playerVC.contentOverlayView else { return }
        let danmakuView = TVDanmakuView(
            danmakus: viewModel.activeDanmakus,
            position: viewModel.currentTime,
            anchor: viewModel.playbackClockDate,
            rate: Double(viewModel.playbackRate),
            moving: viewModel.isPlaying,
            style: viewModel.danmakuStyle
        )
        let host = UIHostingController(rootView: AnyView(danmakuView))
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        addChild(host)
        overlay.addSubview(host.view)
        host.didMove(toParent: self)

        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: overlay.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: overlay.bottomAnchor)
        ])
        self.danmakuHostingController = host
    }

    private func observeViewModel() {
        viewModel.$player
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPlayer in
                self?.playerVC.player = newPlayer
                self?.updateMetadata()
            }
            .store(in: &cancellables)

        viewModel.$currentEpisodeIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.episodeInfoVC?.update()
                self.actionInfoVC?.update()
                self.updateMetadata()
                self.setupTransportBarMenus()
            }
            .store(in: &cancellables)
    }

    private func updateMetadata() {
        let qLabel = PlaybackPlan.qualityLabel(viewModel.selectedQuality)
        TVSystemPlayerMetaUtils.updateMetadata(
            for: playerVC.player?.currentItem,
            title: viewModel.drama.title,
            subtitle: "第 \(viewModel.currentEpisodeIndex) 集 · \(qLabel)",
            description: viewModel.drama.description
        )
    }

    private func loadRelatedDramas() {
        relatedCoordinator.loadRelatedDramas(for: viewModel.drama) { [weak self] _ in
            DispatchQueue.main.async {
                self?.relatedInfoVC?.update()
            }
        }
    }
}
