import SwiftUI
import AVFoundation

public struct TVVideoFeedView: View {
    @ObservedObject var viewModel: VideoFeedViewModel
    var isSidebarVisible: Bool = false
    @State private var playbackWakeTrigger: Int = 0
    let focusTrigger: Int
    let onRequestFocusTopNav: () -> Void

    public var body: some View {
        Group {
            if let _ = viewModel.current {
                TVVideoFeedPlaybackView(
                    viewModel: viewModel,
                    isSidebarVisible: isSidebarVisible,
                    focusWakeTrigger: playbackWakeTrigger,
                    onDismiss: {
                        onRequestFocusTopNav()
                    }
                )
            } else if viewModel.isLoading {
                VStack(spacing: 24) {
                    ProgressView("正在准备推荐短视频…")
                        .font(.system(size: 26, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                    TVButton(title: "重试", icon: "arrow.clockwise", isProminent: true) {
                        Task { await viewModel.retry() }
                    }
                    .accessibilityIdentifier("feed.retry")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .focusSection()
        .onAppear {
            if !isSidebarVisible {
                playbackWakeTrigger += 1
            }
            Task {
                await viewModel.start()
            }
        }
        .onChange(of: isSidebarVisible) { _, visible in
            if !visible {
                playbackWakeTrigger += 1
            }
        }
        .onChange(of: focusTrigger) { _, _ in
            playbackWakeTrigger += 1
        }
        .onChange(of: viewModel.current?.id) { _, newId in
            if newId != nil && !isSidebarVisible {
                playbackWakeTrigger += 1
            }
        }
        .onExitCommand {
            onRequestFocusTopNav()
        }
    }
}
