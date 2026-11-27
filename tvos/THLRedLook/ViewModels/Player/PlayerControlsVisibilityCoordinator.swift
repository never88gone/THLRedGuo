import SwiftUI

/// 播放器控制栏与浮层提示可见性协调器
@MainActor
final class PlayerControlsVisibilityCoordinator: ObservableObject {
    @Published var isControlsVisible: Bool = true
    @Published var toastMessage: String?
    @Published var transitionEpoch: Int = 0

    private var controlsHideTimer: Timer?
    private var toastHideTimer: Timer?
    private var seamlessTimeoutTask: Task<Void, Never>?

    init(initialVisible: Bool = true) {
        self.isControlsVisible = initialVisible
    }

    func showControls(keepControlsVisible: Bool = false, isPlaying: @escaping () -> Bool) {
        withAnimation(.easeInOut(duration: 0.25)) {
            isControlsVisible = true
        }
        resetControlsHideTimer(keepControlsVisible: keepControlsVisible, isPlaying: isPlaying)
    }

    func hideControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isControlsVisible = false
        }
        controlsHideTimer?.invalidate()
    }

    func resetControlsHideTimer(keepControlsVisible: Bool, isPlaying: @escaping () -> Bool) {
        guard !keepControlsVisible else { return }
        controlsHideTimer?.invalidate()
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                if isPlaying() {
                    self?.isControlsVisible = false
                }
            }
        }
    }

    func showToast(_ message: String) {
        toastHideTimer?.invalidate()
        toastMessage = message
        toastHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.toastMessage = nil
                }
            }
        }
    }

    func advanceTransitionEpoch() {
        transitionEpoch &+= 1
    }

    func scheduleSeamlessTimeout(durationNs: UInt64 = 1_200_000_000, onTimeout: @escaping () -> Void) {
        seamlessTimeoutTask?.cancel()
        seamlessTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: durationNs)
            guard !Task.isCancelled else { return }
            self?.seamlessTimeoutTask = nil
            onTimeout()
        }
    }

    func cancelSeamlessTimeout() {
        seamlessTimeoutTask?.cancel()
        seamlessTimeoutTask = nil
    }

    func invalidate() {
        controlsHideTimer?.invalidate()
        controlsHideTimer = nil
        toastHideTimer?.invalidate()
        toastHideTimer = nil
        cancelSeamlessTimeout()
    }
}
