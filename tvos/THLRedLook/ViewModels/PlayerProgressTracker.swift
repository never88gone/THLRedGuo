import Foundation

@MainActor
final class PlayerProgressTracker {
    private let store: LocalStore
    private var progressSaveTimer: Timer?
    private let watchAccountRevision = HongguoAccountVault.shared.snapshot.revision

    init(store: LocalStore = .shared) {
        self.store = store
    }

    func startTimer(onSave: @escaping () -> Void) {
        stopTimer()
        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            DispatchQueue.main.async { onSave() }
        }
    }

    func stopTimer() {
        progressSaveTimer?.invalidate()
        progressSaveTimer = nil
    }

    func restoreSavedProgress(dramaId: String) -> (episode: Int, position: Double, duration: Double)? {
        guard let entry = store.getWatchEntry(dramaId: dramaId) else { return nil }
        return (entry.episode, entry.position, entry.duration)
    }

    func recordProgress(
        drama: Drama,
        episode: Int,
        position: Double,
        duration: Double,
        danmakuId: String?,
        force: Bool = false
    ) {
        guard watchAccountRevision == HongguoAccountVault.shared.snapshot.revision, duration > 0, duration.isFinite else { return }
        let itemId = (danmakuId ?? "").split(separator: ":").last.map(String.init) ?? ""
        store.recordWatch(drama: drama, episode: episode, position: position, duration: duration, itemId: itemId, force: force)
    }
}
