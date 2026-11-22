import SwiftUI
import AVKit

/// tvOS 系统原生播放器 SwiftUI 桥接视图（遵循 ATV-Bilibili-demo 与 AVPlayerViewController 原生架构）
public struct TVSystemPlayerView: UIViewControllerRepresentable {
    @ObservedObject public var viewModel: PlayerViewModel
    public let onDismiss: () -> Void

    public init(viewModel: PlayerViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    public func makeUIViewController(context: Context) -> TVSystemPlayerViewController {
        TVSystemPlayerViewController(viewModel: viewModel, onDismiss: onDismiss)
    }

    public func updateUIViewController(_ uiViewController: TVSystemPlayerViewController, context: Context) {
        uiViewController.setupTransportBarMenus()
    }
}

// MARK: - 预览
#Preview("TVSystemPlayerView Preview") {
    struct PreviewContainer: View {
        var body: some View {
            let drama = Drama(id: "prev_system", title: "都市逆袭之王者归来", cover: "", episodes: 80)
            let eps = (1...20).map { Episode(id: "\($0)", title: "第 \($0) 集", number: $0) }
            let vm = PlayerViewModel(drama: drama, allEpisodes: eps, initialEpisodeIndex: 1)
            TVSystemPlayerView(viewModel: vm) {
                print("Dismiss system player")
            }
            .ignoresSafeArea()
        }
    }
    return PreviewContainer()
}
