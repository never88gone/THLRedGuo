import Foundation

@MainActor
final class PlayerRecoveryCoordinator {
    var recoveryAttempts = 0
    var failedURL = ""
    var stableRecoverySeconds = 0.0

    private let diagnostics: SourceDiagnostics
    private var recoveryTask: Task<Void, Never>?

    init(diagnostics: SourceDiagnostics = .shared) {
        self.diagnostics = diagnostics
    }

    func cancel() {
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    func reset() {
        cancel()
        recoveryAttempts = 0
        failedURL = ""
        stableRecoverySeconds = 0.0
    }

    func requestRecovery(
        reason: String,
        code: String = "",
        error: Error? = nil,
        drama: Drama,
        episodeIndex: Int,
        currentTime: Double,
        planURL: String?,
        onRetry: @escaping (Int, Double) async -> Void,
        onExceeded: @escaping (String) -> Void
    ) {
        guard recoveryTask == nil else { return }
        let errCode = recoveryCode(code, error: error)
        stableRecoverySeconds = 0

        guard let delay = PlaybackRetryPolicy.delay(code: errCode, attempt: recoveryAttempts + 1) else {
            let message = "当前分集重试后仍无法播放，请稍后重试。\n" + reason
            recordRecovery(reason: reason, code: errCode, delay: nil, drama: drama, episodeIndex: episodeIndex, currentTime: currentTime, planURL: planURL)
            onExceeded(message)
            return
        }

        recoveryAttempts += 1
        failedURL = planURL ?? failedURL
        recordRecovery(reason: reason, code: errCode, delay: delay, drama: drama, episodeIndex: episodeIndex, currentTime: currentTime, planURL: planURL)
        NSLog("[PlayerRecovery] episode=%d attempt=%d delayMs=%llu code=%@", episodeIndex, recoveryAttempts, delay / 1_000_000, SourceDiagnostics.safeCode(errCode))

        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.recoveryTask = nil
            await onRetry(episodeIndex, currentTime)
        }
    }

    private func recoveryCode(_ code: String, error: Error?) -> String {
        if !code.isEmpty { return SourceDiagnostics.safeCode(code) }
        guard let error = error as NSError? else { return "PLAYBACK_INTERRUPTED" }
        if let code = error.userInfo["diagnosticCode"] as? String { return SourceDiagnostics.safeCode(code) }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error { return recoveryCode("", error: underlying) }
        return error.domain == NSURLErrorDomain ? "MEDIA_NETWORK_\(abs(error.code))" : "PLAYER_\(abs(error.code))"
    }

    private func recordRecovery(
        reason: String,
        code: String,
        delay: UInt64?,
        drama: Drama,
        episodeIndex: Int,
        currentTime: Double,
        planURL: String?
    ) {
        let phase = planURL == nil ? "取流" : (currentTime > 0 ? "媒体读取" : "媒体准备")
        let waiting = delay.map { String($0 / 1_000_000) + "ms" } ?? "停止"
        let targetURL = planURL ?? failedURL
        diagnostics.add(SourceDiagnosticEntry(
            context: "播放器",
            stage: "播放恢复 第\(episodeIndex)集",
            host: URL(string: targetURL)?.host ?? "",
            url: SourceDiagnostics.desensitizeUrl(targetURL),
            errorCode: code,
            errorDetail: SourceDiagnostics.redact(reason),
            suggestion: delay == nil ? "自动恢复已达到上限，请扫码导出诊断报告。" : "正在保留进度自动恢复。",
            sessionStatus: "剧=\(drama.sourceId)，进度=\(Int(currentTime))秒，恢复=\(recoveryAttempts)，延迟=\(waiting)，阶段=\(phase)"
        ))
    }
}
