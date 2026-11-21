import Foundation
import JavaScriptCore

final class JSSourceRegistry {
    private let sourcesDirURL: URL
    private(set) var installedSources: [String: [String: Any]] = [:]
    private(set) var sourceScripts: [String: String] = [:]
    private(set) var activeSourceId: String = "hongguo"

    init(sourcesDirURL: URL) {
        self.sourcesDirURL = sourcesDirURL
        self.sourceScripts["hongguo"] = BuiltInHongguoJSContent
        self.installedSources["hongguo"] = [
            "id": "hongguo",
            "name": "官方内置",
            "version": "1.0.0",
            "author": "THL"
        ]
    }

    func ensureInitialized() {
        try? FileManager.default.createDirectory(at: sourcesDirURL, withIntermediateDirectories: true)

        let hongguoFile = sourcesDirURL.appendingPathComponent("hongguo.js")
        let needsUpdate: Bool
        if let currentScript = try? String(contentsOf: hongguoFile, encoding: .utf8) {
            needsUpdate = currentScript != BuiltInHongguoJSContent
        } else {
            needsUpdate = true
        }
        if needsUpdate {
            try? BuiltInHongguoJSContent.write(to: hongguoFile, atomically: true, encoding: .utf8)
            NSLog("🎬 [JSSourceRegistry] 已自动同步并更新最新内置官方数据源到沙盒: %@", hongguoFile.path)
        }

        scanSourcesDirectory()

        if activeSourceId.isEmpty || activeSourceId == "hongguo" || !installedSources.keys.contains(activeSourceId) {
            activeSourceId = installedSources.keys.contains("hongguo") ? "hongguo" : (installedSources.keys.first ?? "")
        }
    }

    func scanSourcesDirectory() {
        installedSources.removeAll()
        sourceScripts.removeAll()
        let official = BuiltInHongguoJSContent
        let bundledMeta = extractScriptMeta(script: official, fallbackId: "hongguo") ?? [:]

        let files = (try? FileManager.default.contentsOfDirectory(at: sourcesDirURL, includingPropertiesForKeys: nil)) ?? []

        for file in files where file.pathExtension.lowercased() == "js" {
            guard var script = try? String(contentsOf: file, encoding: .utf8), !script.isEmpty else {
                continue
            }
            if var meta = extractScriptMeta(script: script, fallbackId: file.deletingPathExtension().lastPathComponent) {
                let sid = meta["id"] as? String ?? file.deletingPathExtension().lastPathComponent
                if sid == "hongguo" && script != BuiltInHongguoJSContent &&
                    !isSourceVersionNewer(meta["version"] as? String ?? "", than: bundledMeta["version"] as? String ?? "") {
                    script = official
                    meta = bundledMeta
                    try? official.write(to: file, atomically: true, encoding: .utf8)
                    NSLog("🎬 [JSSourceRegistry] 扫描时已将旧版沙盒数据源自动热升级为最新内置官方源")
                }
                if sid == "hongguo", let existing = installedSources[sid],
                   !isSourceVersionNewer(meta["version"] as? String ?? "", than: existing["version"] as? String ?? "") {
                    continue
                }
                installedSources[sid] = meta
                sourceScripts[sid] = script
            }
        }

        if !official.isEmpty, sourceScripts["hongguo"] == nil {
            var meta = bundledMeta
            meta["sha256"] = SourceDiagnostics.fingerprint(official)
            meta["sourceCommit"] = SourceDiagnostics.sourceManifest["sourceCommit"] ?? ""
            installedSources["hongguo"] = meta
            sourceScripts["hongguo"] = official
        }
        if let script = sourceScripts["hongguo"] {
            installedSources["hongguo"]?["sha256"] = SourceDiagnostics.fingerprint(script)
            installedSources["hongguo"]?["sourceCommit"] = script == official ? SourceDiagnostics.sourceManifest["sourceCommit"] ?? "" : ""
        }

        if !installedSources.keys.contains(activeSourceId) {
            activeSourceId = installedSources.keys.contains("hongguo") ? "hongguo" : (installedSources.keys.first ?? "")
        }
    }

    func setActiveSourceId(_ id: String) -> Bool {
        if installedSources.keys.contains(id) {
            activeSourceId = id
            return true
        }
        return false
    }

    func saveAndLoad(script: String, fileName: String, autoSelect: Bool) throws -> String {
        guard !script.isEmpty else {
            throw NSError(domain: "CatPawOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "脚本内容为空"])
        }
        let targetFile = sourcesDirURL.appendingPathComponent(fileName)
        try script.write(to: targetFile, atomically: true, encoding: .utf8)
        scanSourcesDirectory()
        let fileId = fileName.replacingOccurrences(of: ".js", with: "")
        if let targetMeta = installedSources.values.first(where: {
            let sid = ($0["id"] as? String) ?? ""
            return sid == "hongguo" || sid == fileId
        }) {
            let targetId = targetMeta["id"] as? String ?? activeSourceId
            if autoSelect || targetId == "hongguo" || activeSourceId.isEmpty {
                activeSourceId = targetId
            }
        } else if autoSelect, installedSources[fileId] != nil {
            activeSourceId = fileId
        }
        return activeSourceId
    }

    func removeSource(sourceId: String) -> (removed: Bool, active: String) {
        let trimmed = sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "hongguo" else {
            return (false, activeSourceId)
        }

        var removedAny = false
        let exactFile = sourcesDirURL.appendingPathComponent("\(trimmed).js")
        if FileManager.default.fileExists(atPath: exactFile.path) {
            try? FileManager.default.removeItem(at: exactFile)
            removedAny = true
        }

        if let files = try? FileManager.default.contentsOfDirectory(at: sourcesDirURL, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension.lowercased() == "js" {
                let baseName = file.deletingPathExtension().lastPathComponent
                if baseName == "hongguo" { continue }
                if baseName == trimmed {
                    try? FileManager.default.removeItem(at: file)
                    removedAny = true
                    continue
                }
                if let script = try? String(contentsOf: file, encoding: .utf8), !script.isEmpty {
                    if let meta = extractScriptMeta(script: script, fallbackId: baseName) {
                        let sid = (meta["id"] as? String) ?? baseName
                        if sid == trimmed {
                            try? FileManager.default.removeItem(at: file)
                            removedAny = true
                        }
                    }
                }
            }
        }

        installedSources.removeValue(forKey: trimmed)
        sourceScripts.removeValue(forKey: trimmed)
        scanSourcesDirectory()
        if activeSourceId == trimmed || !installedSources.keys.contains(activeSourceId) {
            activeSourceId = installedSources.keys.contains("hongguo") ? "hongguo" : (installedSources.keys.first ?? "")
        }
        return (removedAny, activeSourceId)
    }

    func clearAll() -> String {
        if let files = try? FileManager.default.contentsOfDirectory(at: sourcesDirURL, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension.lowercased() == "js" {
                let baseName = file.deletingPathExtension().lastPathComponent
                if baseName.lowercased() != "hongguo" {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        installedSources.removeAll()
        sourceScripts.removeAll()
        scanSourcesDirectory()
        activeSourceId = installedSources.keys.contains("hongguo") ? "hongguo" : ""
        return activeSourceId
    }

    func resetOfficial() -> String {
        let hongguoFile = sourcesDirURL.appendingPathComponent("hongguo.js")
        let script = BuiltInHongguoJSContent
        if !script.isEmpty {
            try? script.write(to: hongguoFile, atomically: true, encoding: .utf8)
            sourceScripts["hongguo"] = script
        }
        scanSourcesDirectory()
        activeSourceId = "hongguo"
        return activeSourceId
    }

    func getScript(sourceId: String) -> String? {
        sourceScripts[sourceId]
    }

    func setScript(sourceId: String, script: String) {
        sourceScripts[sourceId] = script
    }

    private func isSourceVersionNewer(_ candidate: String, than baseline: String) -> Bool {
        guard candidate.count <= 128, baseline.count <= 128 else { return false }
        let pattern = #"^(\d{1,9})\.(\d{1,9})\.(\d{1,9})(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        func fields(_ value: String) -> [String]? {
            guard let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
            return (1...4).map { index in Range(match.range(at: index), in: value).map { String(value[$0]) } ?? "" }
        }
        guard let a = fields(candidate), let b = fields(baseline) else { return false }
        for index in 0..<3 {
            let left = Int(a[index])!, right = Int(b[index])!
            if left != right { return left > right }
        }
        if a[3].isEmpty || b[3].isEmpty { return a[3].isEmpty && !b[3].isEmpty }
        let ap = a[3].split(separator: "."), bp = b[3].split(separator: ".")
        for index in 0..<min(ap.count, bp.count) {
            let left = ap[index], right = bp[index]
            if left == right { continue }
            let an = left.allSatisfy { $0.isASCII && $0.isNumber }, bn = right.allSatisfy { $0.isASCII && $0.isNumber }
            if an != bn { return !an }
            if an {
                let digitsA = left.drop(while: { $0 == "0" }), digitsB = right.drop(while: { $0 == "0" })
                if digitsA.count != digitsB.count { return digitsA.count > digitsB.count }
                if digitsA != digitsB { return digitsA.lexicographicallyPrecedes(digitsB) == false }
            } else { return right.lexicographicallyPrecedes(left) }
        }
        return ap.count > bp.count
    }

    private func extractScriptMeta(script: String, fallbackId: String) -> [String: Any]? {
        let ctx = JSContext()!
        ctx.evaluateScript("var meta = {}; var spider = { meta: {} };")
        ctx.evaluateScript(script)

        let metaVal = ctx.evaluateScript("typeof spider !== 'undefined' && spider.meta ? spider.meta : (typeof meta !== 'undefined' ? meta : null);")
        if let dict = metaVal?.toDictionary() as? [String: Any], let id = dict["id"] as? String, !id.isEmpty {
            return dict
        }

        if let match = script.range(of: "id\\s*:\\s*[\"']([^\"']+)[\"']", options: .regularExpression) {
            let idSubstring = script[match]
            let id = idSubstring.components(separatedBy: CharacterSet(charactersIn: "\"'"))[1]
            let nameMatch = script.range(of: "name\\s*:\\s*[\"']([^\"']+)[\"']", options: .regularExpression)
            let name = nameMatch != nil ? script[nameMatch!].components(separatedBy: CharacterSet(charactersIn: "\"'"))[1] : id
            let versionMatch = script.range(of: "version\\s*:\\s*[\"']([^\"']+)[\"']", options: .regularExpression)
            let version = versionMatch.map { String(script[$0]).components(separatedBy: CharacterSet(charactersIn: "\"'"))[1] } ?? ""
            let authorMatch = script.range(of: "author\\s*:\\s*[\"']([^\"']+)[\"']", options: .regularExpression)
            let author = authorMatch.map { String(script[$0]).components(separatedBy: CharacterSet(charactersIn: "\"'"))[1] } ?? ""
            return [
                "id": id,
                "name": name,
                "version": version,
                "author": author,
                "description": "自定义 JS 插件"
            ]
        }

        return [
            "id": fallbackId,
            "name": fallbackId,
            "version": "1.0.0",
            "description": "本地 JS 插件"
        ]
    }
}
