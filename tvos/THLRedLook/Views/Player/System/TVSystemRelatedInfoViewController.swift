import UIKit
import SwiftUI

/// tvOS 系统播放器 Custom Info 面板：【相关短剧】（对齐 ATV-Bilibili-demo 相关视频设计）
public final class TVSystemRelatedInfoViewController: UIViewController {
    private let viewModel: PlayerViewModel
    private var hostingController: UIHostingController<TVPlayerRelatedPanel>?

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        self.title = "相关短剧"
        self.preferredContentSize = CGSize(width: 0, height: 260)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupHostingController()
    }

    public func update() {
        hostingController?.rootView = TVPlayerRelatedPanel(viewModel: viewModel)
    }

    private func setupHostingController() {
        let host = UIHostingController(rootView: TVPlayerRelatedPanel(viewModel: viewModel))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.hostingController = host
    }
}
