import Foundation

@MainActor
public final class SourceDiagnosticRunner: ObservableObject {
    public static let shared = SourceDiagnosticRunner()
    @Published public private(set) var running = false
    @Published public private(set) var result = "尚未检测"

    public func run() async {
        guard !running else { return }
        running = true
        result = "正在检查：网络与DNS、JS脚本引擎、游客会话、短剧搜索、选集详情…"
        let recorder = SourceDiagnostics.shared
        let context = "主动检测 " + ISO8601DateFormatter().string(from: Date())
        async let network: Void = recorder.refreshNetworkEgress(force: true)
        defer { running = false }

        let bridge = NativeBridge(diagnostics: recorder, diagnosticContext: context)
        var stage = "搜索第一页"
        do {
            let first = try await bridge.request(
                action: "catalog",
                payload: ["source": "hongguo", "query": "短剧", "page": 1]
            )
            let items = first["items"] as? [[String: Any]] ?? []
            recorder.add(SourceDiagnosticEntry(
                context: context,
                stage: stage,
                count: items.count
            ))

            guard !items.isEmpty else {
                throw NSError(domain: "SourceDiagnostic", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "官方搜索返回空结果，未能验证分页与详情",
                    "diagnosticCategory": DiagnosticCategory.invalidResponse.rawValue,
                    "diagnosticCode": "SEARCH_EMPTY"
                ])
            }
            let more = first["hasMore"] as? Bool == true
            if more {
                stage = "搜索分页"
                let next = try await bridge.request(
                    action: "catalog",
                    payload: ["source": "hongguo", "query": "短剧", "page": 2]
                )
                recorder.add(SourceDiagnosticEntry(
                    context: context,
                    stage: stage,
                    count: (next["items"] as? [Any])?.count ?? 0
                ))
            }

            if let drama = items.first {
                stage = "详情解析"
                let detail = try await bridge.request(action: "detail", payload: ["drama": drama])
                guard let chapters = detail["chapters"] as? [[String: Any]], let chapter = chapters.first else {
                    let err = NSError(domain: "SourceDiagnostic", code: 2, userInfo: [NSLocalizedDescriptionKey: "详情接口未返回剧集章节列表"])
                    throw err
                }
                stage = "播放流解析"
                recorder.add(SourceDiagnosticEntry(context: context, stage: "检测分集", sessionStatus: "剧=\(drama["sourceId"] as? String ?? "")，集=1"))
                result = "搜索与详情已通过，正在检查所选分集的播放解析…"
                let plan = try await Self.resolvePlayback(bridge: bridge, payload: ["source": "hongguo", "drama": detail["drama"] as? [String: Any] ?? drama, "chapter": chapter, "index": 1])
                guard let url = plan["url"] as? String, !url.isEmpty else {
                    throw NSError(domain: "SourceDiagnostic", code: 4, userInfo: [NSLocalizedDescriptionKey: "播放接口未返回可用地址", "diagnosticCode": "NO_STREAM_URL"])
                }
                recorder.add(SourceDiagnosticEntry(context: context, stage: stage, count: 1))
            }

            result = "检测完成：JS引擎、游客会话、搜索\(more ? "、分页" : "")、详情与播放解析通过"
        } catch {
            let nsErr = error as NSError
            let errorMsg = error.localizedDescription
            let cat: DiagnosticCategory
            let reason: String
            let advice: String
            if let rawCat = nsErr.userInfo["diagnosticCategory"] as? String,
               let parsedCat = DiagnosticCategory(rawValue: rawCat) {
                cat = parsedCat
                reason = errorMsg
                advice = (nsErr.userInfo["diagnosticAdvice"] as? String)
                    ?? SourceDiagnostics.advice(SourceDiagnosticEntry(context: context, stage: stage, category: cat, errorDetail: reason))
            } else {
                let isJS = errorMsg.contains("SyntaxError") || errorMsg.contains("ReferenceError") || errorMsg.contains("TypeError")
                let classified = SourceDiagnostics.classify(error: error, httpStatus: nil, body: nil, isJS: isJS)
                cat = classified.category
                reason = classified.reason
                advice = classified.suggestion
            }
            let url = nsErr.userInfo["diagnosticUrl"] as? String ?? ""
            let logId = nsErr.userInfo["diagnosticLogId"] as? String ?? ""
            let snippet = nsErr.userInfo["diagnosticSnippet"] as? String ?? ""
            let tabs = nsErr.userInfo["diagnosticTabs"] as? String ?? ""
            let session = nsErr.userInfo["diagnosticSession"] as? String ?? ""
            recorder.add(SourceDiagnosticEntry(
                context: context,
                stage: stage,
                host: URL(string: url)?.host ?? "",
                url: url,
                logId: logId,
                errorCode: (nsErr.userInfo["diagnosticCode"] as? String) ?? cat.tag,
                category: cat,
                errorDetail: reason,
                suggestion: advice,
                responseSnippet: snippet,
                searchTabsSummary: tabs,
                sessionStatus: session
            ))
            let passed = stage == "播放流解析" ? "搜索与详情已通过；所选分集" : ""
            result = "检测失败：" + passed + "【\(cat.tag)】\(stage) - \(reason)"
        }
        await network
    }

    static func resolvePlayback(bridge: NativeBridge, payload: [String: Any]) async throws -> [String: Any] {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do { return try await bridge.request(action: "resolve", payload: payload) }
            catch {
                if error is CancellationError { throw error }
                attempt += 1
                let code = (error as NSError).userInfo["diagnosticCode"] as? String ?? ""
                guard let delay = PlaybackRetryPolicy.delay(code: code, attempt: attempt) else { throw error }
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }
}
