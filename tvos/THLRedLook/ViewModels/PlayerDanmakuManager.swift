import Foundation
import Combine
import SwiftUI

@MainActor
final class PlayerDanmakuManager: ObservableObject {
    @Published var activeDanmakus: [DanmakuItem] = []
    @Published var danmakuEnabled: Bool
    @Published var danmakuStyle: TVDanmakuStyle

    private let repository: NativeRepository
    private let store: LocalStore
    private var danmakuCache: [DanmakuItem] = []
    private var danmakuPages: [Int64: [DanmakuItem]] = [:]
    private var danmakuRetryAfter: [Int64: Date] = [:]
    private var danmakuTask: Task<Void, Never>?
    private var danmakuRequestSequence = 0

    init(store: LocalStore = .shared, repository: NativeRepository = .shared) {
        self.store = store
        self.repository = repository
        self.danmakuEnabled = store.danmakuEnabled
        self.danmakuStyle = store.danmakuStyle
    }

    func toggleDanmaku() {
        danmakuEnabled.toggle()
        store.danmakuEnabled = danmakuEnabled
    }

    func updateStyle(_ style: TVDanmakuStyle) {
        danmakuStyle = style
        store.danmakuStyle = style
    }

    func setFontSize(_ size: CGFloat) {
        var next = danmakuStyle
        next.fontSize = size
        updateStyle(next)
    }

    func setOpacity(_ op: Double) {
        var next = danmakuStyle
        next.opacity = op
        updateStyle(next)
    }

    func setLaneCount(_ lanes: Int) {
        var next = danmakuStyle
        next.laneCount = lanes
        updateStyle(next)
    }

    func reset() {
        danmakuRequestSequence += 1
        danmakuTask?.cancel()
        danmakuTask = nil
        danmakuPages.removeAll()
        danmakuRetryAfter.removeAll()
        danmakuCache = []
        activeDanmakus = []
    }

    func updateActiveDanmakus(currentTime: Double, duration: Double, plan: PlaybackPlan?) {
        guard danmakuEnabled, currentTime.isFinite, duration.isFinite, duration > 0, duration <= 86400 else {
            activeDanmakus = []
            return
        }
        let currentMs = Int64(max(0, min(currentTime, duration)) * 1000)
        let durationMs = Int64(duration * 1000)
        activeDanmakus = danmakuCache.filter { $0.timeMs > currentMs - 8000 && $0.timeMs <= currentMs }

        guard let plan, !plan.danmakuId.isEmpty else { return }
        let start = currentMs / 30000 * 30000
        requestDanmaku(plan: plan, start: start, durationMs: durationMs, currentTime: currentTime)
        if danmakuPages[start] != nil && currentMs >= start + 22000 {
            requestDanmaku(plan: plan, start: start + 30000, durationMs: durationMs, currentTime: currentTime)
        }
    }

    private func requestDanmaku(plan: PlaybackPlan, start: Int64, durationMs: Int64, currentTime: Double) {
        guard danmakuTask == nil, danmakuPages[start] == nil,
              start < durationMs, danmakuRetryAfter[start, default: .distantPast] <= Date() else { return }

        danmakuRequestSequence += 1
        let sequence = danmakuRequestSequence
        danmakuTask = Task { [weak self] in
            guard let self else { return }
            defer { if sequence == self.danmakuRequestSequence { self.danmakuTask = nil } }
            do {
                let rows = try await self.repository.loadDanmaku(plan: plan, startMs: start, durationMs: durationMs)
                guard !Task.isCancelled, sequence == self.danmakuRequestSequence, self.danmakuEnabled else { return }
                self.danmakuPages[start] = rows
                let position = Int64(currentTime * 1000)
                let nearest = self.danmakuPages.keys.sorted { abs($0 - position) < abs($1 - position) }
                for key in nearest.dropFirst(6) { self.danmakuPages.removeValue(forKey: key) }
                self.danmakuRetryAfter.removeValue(forKey: start)
                var seen = Set<String>()
                self.danmakuCache = self.danmakuPages.values.flatMap { $0 }.sorted { $0.timeMs < $1.timeMs }.filter { seen.insert($0.id).inserted }
                self.danmakuTask = nil
            } catch {
                guard !Task.isCancelled, sequence == self.danmakuRequestSequence else { return }
                self.danmakuRetryAfter[start] = Date().addingTimeInterval(15)
            }
        }
    }
}
