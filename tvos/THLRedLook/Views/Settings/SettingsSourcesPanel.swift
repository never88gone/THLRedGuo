import SwiftUI

// MARK: - 站源管理与导入面板
public struct SettingsSourcesPanel: View {
    @EnvironmentObject private var jsService: JSSourceService
    @ObservedObject private var sourceDiagnostics = SourceDiagnostics.shared
    @Binding public var showingSourceDiagnostics: Bool
    @Binding public var saveNotice: String?

    @State private var showingImportAlert = false
    @State private var showingClearAllAlert = false
    @State private var importURLString = ""
    @State private var isImporting = false

    private enum SourcesFocus: Hashable {
        case diagnostics
        case resetOfficial
        case officialSource
        case importNetwork
        case clearAll
    }
    @FocusState private var focusedButton: SourcesFocus?

    public init(
        showingSourceDiagnostics: Binding<Bool>,
        saveNotice: Binding<String?>
    ) {
        self._showingSourceDiagnostics = showingSourceDiagnostics
        self._saveNotice = saveNotice
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text("站源管理")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("配置并选择当前要使用的影视数据源。内置支持官方标准短剧源，也可导入自定义 JS 插件。")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("应用 " + SourceDiagnostics.version + " · " + SourceDiagnostics.sourceRevision)
                    .font(.system(size: 29)).accessibilityIdentifier("settings.sourceRevision")
                Text(SourceDiagnostics.sourceBundleStatus + " · " + sourceDiagnostics.sourceRuntimeStatus)
                    .font(.system(size: 25)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.sourceRuntime")
            }

            // 顶部操作栏
            HStack(spacing: 20) {
                TVButton(
                    title: "数据源诊断",
                    icon: "stethoscope",
                    isProminent: false,
                    isExternalFocused: focusedButton == .diagnostics
                ) {
                    showingSourceDiagnostics = true
                }
                .focused($focusedButton, equals: .diagnostics)
                .accessibilityIdentifier("settings.sourceDiagnostics")

                TVButton(
                    title: "重置数据源与凭证",
                    icon: "arrow.counterclockwise.circle.fill",
                    isProminent: false,
                    isExternalFocused: focusedButton == .resetOfficial
                ) {
                    Task {
                        isImporting = true
                        let success = await jsService.resetOfficialSourceAndSession()
                        isImporting = false
                        if success {
                            saveNotice = "已成功重置官方数据源沙盒与会话凭证，已建立全新官方连接！"
                        } else {
                            saveNotice = "重置失败，请重试。"
                        }
                    }
                }
                .focused($focusedButton, equals: .resetOfficial)
                .accessibilityIdentifier("settings.resetSourceAndSession")

                let isHongguoInstalled = jsService.sources.contains(where: { ($0["id"] as? String) == "hongguo" })
                let isHongguoActive = jsService.activeSourceId == "hongguo"

                TVButton(
                    title: isHongguoInstalled ? (isHongguoActive ? "官方数据源 (已激活)" : "设为默认源") : "导入官方数据源",
                    icon: isHongguoActive ? "checkmark.circle.fill" : "sparkles.tv.fill",
                    isProminent: !isHongguoActive,
                    isExternalFocused: focusedButton == .officialSource
                ) {
                    Task {
                        isImporting = true
                        let success = await jsService.importBuiltInHongguoSource(autoSelect: true)
                        isImporting = false
                        if success {
                            saveNotice = "已成功导入官方免费短剧数据源，并默认设为当前激活源！"
                        } else {
                            saveNotice = "导入数据源失败，请重试。"
                        }
                    }
                }
                .focused($focusedButton, equals: .officialSource)
                .accessibilityIdentifier("settings.officialSource")

                TVButton(
                    title: "网络链接导入",
                    icon: "plus.app.fill",
                    isProminent: false,
                    isExternalFocused: focusedButton == .importNetwork
                ) {
                    showingImportAlert = true
                }
                .focused($focusedButton, equals: .importNetwork)
                .accessibilityIdentifier("settings.importNetworkSource")

                let hasCustomSources = jsService.sources.contains(where: { (($0["id"] as? String) ?? "").lowercased() != "hongguo" })
                if hasCustomSources {
                    TVButton(
                        title: "清空自定义源",
                        icon: "trash.circle.fill",
                        isProminent: false,
                        isExternalFocused: focusedButton == .clearAll
                    ) {
                        showingClearAllAlert = true
                    }
                    .focused($focusedButton, equals: .clearAll)
                    .accessibilityIdentifier("settings.clearAllSources")
                }

                Spacer()
            }
            .focusSection()
            .padding(.bottom, 16)
            
            Text("已安装插件列表")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
            
            if jsService.sources.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("暂无任何数据源。推荐立即导入官方标准数据源，即刻开启全量短剧在线播放体验。")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))

                    TVButton(title: "立即导入官方数据源", icon: "sparkles.tv.fill", isProminent: true) {
                        Task {
                            isImporting = true
                            let success = await jsService.importBuiltInHongguoSource(autoSelect: true)
                            isImporting = false
                            if success {
                                saveNotice = "已成功导入官方免费短剧数据源，并默认设为当前激活源！"
                            }
                        }
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(TVColors.sourcePanelItemBg)
                )
            } else {
                VStack(spacing: 18) {
                    ForEach(jsService.sources.indices, id: \.self) { index in
                        let src = jsService.sources[index]
                        let id = src["id"] as? String ?? ""
                        let name = src["name"] as? String ?? "Unknown"
                        let version = id == "hongguo" ? (SourceDiagnostics.sourceManifest["sourceVersion"] ?? (src["version"] as? String ?? "")) : (src["version"] as? String ?? "")
                        let author = src["author"] as? String ?? "Unknown"
                        let isActive = jsService.activeSourceId == id
                        
                        JSSourcePluginCard(
                            id: id,
                            name: name,
                            version: version,
                            author: author,
                            isActive: isActive,
                            onSelect: {
                                Task {
                                    await jsService.setActiveSource(id)
                                    saveNotice = "已切换激活：\(name)"
                                }
                            },
                            onRemove: {
                                Task {
                                    let ok = await jsService.removeSource(id)
                                    await MainActor.run {
                                        if ok {
                                            saveNotice = "已成功删除数据源：\(name)"
                                        } else {
                                            saveNotice = "删除数据源失败，请重试。"
                                        }
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
        .overlay(
            Group {
                if showingImportAlert {
                    importAlertOverlay
                }
            }
        )
        .alert("清空自定义数据源", isPresented: $showingClearAllAlert) {
            Button("取消", role: .cancel) {}
            Button("全部清空", role: .destructive) {
                Task {
                    let ok = await jsService.clearAllSources()
                    await MainActor.run {
                        if ok {
                            saveNotice = "已成功清空所有自定义数据源，并重置为官方默认源。"
                        } else {
                            saveNotice = "清空数据源失败，请重试。"
                        }
                    }
                }
            }
        } message: {
            Text("确定要清空所有自定义导入的 JS 数据源吗？官方内置数据源将保留，此操作不可撤销。")
        }
    }

    private var importAlertOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 32) {
                Text("添加网络订阅链接")
                    .font(.system(size: 34, weight: .bold))
                
                TextField("请输入 JS 插件链接 (URL)", text: $importURLString)
                    .frame(width: 600)
                    .font(.system(size: 24))
                
                Text("提示：导入官方数据源时将默认自动选中并激活")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))

                if isImporting {
                    ProgressView()
                }
                
                HStack(spacing: 24) {
                    TVButton(title: "取消", icon: "xmark") {
                        showingImportAlert = false
                    }

                    TVButton(title: "直接导入内置官方源", icon: "sparkles.tv.fill") {
                        Task {
                            isImporting = true
                            let success = await jsService.importBuiltInHongguoSource(autoSelect: true)
                            isImporting = false
                            showingImportAlert = false
                            if success {
                                saveNotice = "已成功导入官方免费短剧数据源，并默认设为当前激活源！"
                            }
                        }
                    }
                    
                    TVButton(title: "从 URL 导入", icon: "arrow.down.doc", isProminent: true) {
                        importPlugin()
                    }
                }
            }
            .padding(60)
            .background(TVColors.darkPlaceholderBg)
            .cornerRadius(24)
        }
    }

    private func importPlugin() {
        guard !importURLString.isEmpty else { return }
        isImporting = true
        Task {
            do {
                let success = try await jsService.importFromURL(importURLString, autoSelect: true)
                if success {
                    await MainActor.run {
                        isImporting = false
                        showingImportAlert = false
                        importURLString = ""
                        saveNotice = "插件导入成功，已默认选择激活！"
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    saveNotice = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
