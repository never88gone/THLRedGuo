import Foundation

/// 负责从 release.md 加载并解析版本更新日志的核心加载器
public final class ReleaseNotesLoader {
    public static let shared = ReleaseNotesLoader()

    public init() {}

    /// 加载并按时间倒序返回更新日志列表
    public func loadReleaseNotes() -> [ReleaseNoteItem] {
        let content = loadRawContent()
        return parse(content: content)
    }

    /// 读取原始 release.md 内容（支持 Bundle 资源、根目录及多种回退路径）
    public func loadRawContent() -> String {
        // 1. 优先尝试从 Bundle.main 获取 release.md
        if let bundleUrl = Bundle.main.url(forResource: "release", withExtension: "md"),
           let text = try? String(contentsOf: bundleUrl, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        // 2. 尝试从 Bundle 根目录直接读取
        let bundlePath = Bundle.main.bundlePath
        let possibleBundlePaths = [
            (bundlePath as NSString).appendingPathComponent("release.md"),
            (bundlePath as NSString).appendingPathComponent("THLRedLook/release.md")
        ]
        for p in possibleBundlePaths {
            if FileManager.default.fileExists(atPath: p),
               let text = try? String(contentsOfFile: p, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        // 3. 尝试源码与测试环境相对路径回退
        let fallbackPaths = [
            "tvos/release.md",
            "release.md",
            "../release.md",
            "../../tvos/release.md",
            "../../../tvos/release.md"
        ]
        for p in fallbackPaths {
            if FileManager.default.fileExists(atPath: p),
               let text = try? String(contentsOfFile: p, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        // 4. 内置默认兜底更新日志
        return Self.defaultFallbackMarkdown
    }

    /// 解析 Markdown 文本为结构化列表并按时间倒序排列
    public func parse(content: String) -> [ReleaseNoteItem] {
        let lines = content.components(separatedBy: .newlines)
        var sections: [(version: String, date: String, items: [String])] = []
        var currentVersion = ""
        var currentDate = ""
        var currentItems: [String] = []

        let versionRegex = try? NSRegularExpression(
            pattern: #"^##\s+([0-9]+(?:\.[0-9]+)*)(?:\s*\(([^)]+)\))?"#,
            options: []
        )

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                if !currentVersion.isEmpty || !currentItems.isEmpty {
                    sections.append((version: currentVersion, date: currentDate, items: currentItems))
                    currentItems = []
                }

                currentVersion = "1.0.0"
                currentDate = ""

                let nsString = trimmed as NSString
                if let match = versionRegex?.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: nsString.length)) {
                    if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                        currentVersion = nsString.substring(with: match.range(at: 1))
                    }
                    if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                        currentDate = nsString.substring(with: match.range(at: 2))
                    }
                } else {
                    let rawTitle = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    currentVersion = rawTitle
                }
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                let itemContent = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !itemContent.isEmpty {
                    currentItems.append(itemContent)
                }
            }
        }

        if !currentVersion.isEmpty || !currentItems.isEmpty {
            sections.append((version: currentVersion, date: currentDate, items: currentItems))
        }

        // 按时间倒序排序（若日期合法则按日期倒序，否则保持原有顺序）
        let sorted = sections.sorted { a, b in
            if !a.date.isEmpty && !b.date.isEmpty {
                return a.date > b.date
            }
            return false
        }

        return sorted.enumerated().map { index, sec in
            ReleaseNoteItem(
                id: "\(sec.version)_\(sec.date)_\(index)",
                version: sec.version,
                date: sec.date,
                items: sec.items,
                isLatest: index == 0
            )
        }
    }

    /// 提取最新一次修改内容文本（供单测或调试调用）
    public func extractLatestNotes() -> String {
        let items = loadReleaseNotes()
        guard let latest = items.first else { return "" }
        let header = latest.date.isEmpty ? latest.version : "\(latest.version) (\(latest.date))"
        let bulletPoints = latest.items.map { "• \($0)" }.joined(separator: "\n")
        return "【\(header) 更新内容】\n\(bulletPoints)"
    }

    private static let defaultFallbackMarkdown: String = """
    # 糖葫芦Haw Apple TV 更新日志

    ## 1.0.0 (2026-11-07)
    - 新增系统级画中画（PiP）独立小窗播放功能，支持脱离主界面后持续悬浮播放
    - 支持画中画小窗模式下自动连续播放下一集，观影进度与本地历史无缝同步
    - 支持画中画小窗恢复全屏时精准返回之前的播放器与剧集页面，无缝接续播放
    - 优化播放器控制栏交互，将画中画入口提升至第一层主控制栏并常驻显示，打通遥控器焦点循环导航
    """
}
