import SwiftUI

// MARK: - 站源管理与导入面板
public struct SettingsSourcesPanel: View {
    @EnvironmentObject private var jsService: JSSourceService
    @Binding public var showingSourceDiagnostics: Bool
    @Binding public var saveNotice: String?

    @State private var showingImportAlert = false
    @State private var showingClearAllAlert = false
    @State private var importURLString = ""
    @State private var isImporting = false

    private enum SourcesFocus: Hashable {
        case diagnostics
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
                        .fill(Color(red: 0.14, green: 0.14, blue: 0.18))
                )
            } else {
                VStack(spacing: 18) {
                    ForEach(jsService.sources.indices, id: \.self) { index in
                        let src = jsService.sources[index]
                        let id = src["id"] as? String ?? ""
                        let name = src["name"] as? String ?? "Unknown"
                        let version = src["version"] as? String ?? "1.0.0"
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
            .background(Color(white: 0.15))
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

// MARK: - 当前生效站源卡片（可聚焦，顺滑承接来自侧边栏的向右焦点，预留防裁切间距）
public struct ActiveSourceCard: View {
    public let source: SourceSite
    public var forceFocused: Bool = false
    public let action: () -> Void

    @FocusState private var isFocused: Bool

    public init(source: SourceSite, forceFocused: Bool = false, action: @escaping () -> Void) {
        self.source = source
        self.forceFocused = forceFocused
        self.action = action
    }

    public var body: some View {
        let effectiveFocused = isFocused || forceFocused
        Button(action: action) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(TVTheme.primary.opacity(0.25))
                        .frame(width: 60, height: 60)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(TVTheme.primary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text(source.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text("当前活跃源")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(TVTheme.primary)
                            .clipShape(Capsule())
                    }
                    Text(source.description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                }
                Spacer()

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(effectiveFocused ? Color(red: 0.24, green: 0.20, blue: 0.26) : Color(red: 0.18, green: 0.13, blue: 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(effectiveFocused ? Color.white : TVTheme.primary.opacity(0.45), lineWidth: effectiveFocused ? 3.0 : 1.5)
            )
            .scaleEffect(effectiveFocused ? 1.02 : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: effectiveFocused)
            .tvFocusBorder(isFocused: effectiveFocused, cornerRadius: 18)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

// MARK: - 站源选择卡片
public struct SourceCardButton: View {
    public let source: SourceSite
    public let isSelected: Bool
    public let action: () -> Void

    @FocusState private var isFocused: Bool

    public init(source: SourceSite, isSelected: Bool, action: @escaping () -> Void) {
        self.source = source
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? TVTheme.primary.opacity(0.3) : Color.white.opacity(0.08))
                        .frame(width: 48, height: 48)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? TVTheme.primary : .white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text(source.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color(red: 0.20, green: 0.16, blue: 0.18) : (isFocused ? Color(red: 0.22, green: 0.22, blue: 0.26) : Color(red: 0.13, green: 0.13, blue: 0.17)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? TVTheme.primary : Color.clear, lineWidth: 2)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 16)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

// MARK: - JS 插件管理卡片（沉浸式深色微质感，支持高光获焦，彻底消除突兀白底）
public struct JSSourcePluginCard: View {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let isActive: Bool
    public let onSelect: () -> Void
    public let onRemove: () -> Void

    @FocusState private var isCardFocused: Bool
    @FocusState private var isTrashFocused: Bool
    @State private var showDeleteConfirm = false

    public init(
        id: String,
        name: String,
        version: String,
        author: String,
        isActive: Bool,
        onSelect: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.isActive = isActive
        self.onSelect = onSelect
        self.onRemove = onRemove
    }

    private var isBuiltIn: Bool {
        id.lowercased() == "hongguo"
    }

    public var body: some View {
        HStack(spacing: 14) {
            // 左侧：切换选择按钮
            Button(action: onSelect) {
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(isActive ? TVTheme.primary.opacity(0.25) : Color(red: 0.20, green: 0.20, blue: 0.24))
                            .frame(width: 52, height: 52)
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 26))
                            .foregroundColor(isActive ? TVTheme.primary : Color.white.opacity(0.45))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text(name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            if isActive {
                                Text("当前活跃源")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(TVTheme.primary)
                                    .clipShape(Capsule())
                            }
                            if isBuiltIn {
                                Text("官方内置")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("v\(version) · 作者: \(author) · 脚本: \(id).js")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isCardFocused ? TVTheme.primary : Color.white.opacity(0.3))
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            isCardFocused
                                ? Color(red: 0.24, green: 0.20, blue: 0.26)
                                : (isActive ? Color(red: 0.18, green: 0.13, blue: 0.16) : Color(red: 0.12, green: 0.12, blue: 0.15))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            isCardFocused
                                ? Color.white
                                : (isActive ? TVTheme.primary.opacity(0.55) : Color.white.opacity(0.06)),
                            lineWidth: isCardFocused ? 3.0 : (isActive ? 1.5 : 1.0)
                        )
                )
                .scaleEffect(isCardFocused ? 1.02 : 1.0)
                .shadow(
                    color: isCardFocused ? TVTheme.primary.opacity(0.5) : Color.clear,
                    radius: isCardFocused ? 14 : 0,
                    x: 0,
                    y: isCardFocused ? 4 : 0
                )
                .animation(TVTheme.focusSpringAnimation, value: isCardFocused)
                .tvFocusBorder(isFocused: isCardFocused, cornerRadius: 18)
            }
            .buttonStyle(TVZeroHighlightButtonStyle())
            .focused($isCardFocused)
            .focusEffectDisabled()
            .accessibilityIdentifier("settings.source.card.\(id)")
            .contextMenu {
                Button {
                    onSelect()
                } label: {
                    Label("激活此数据源", systemImage: "checkmark.circle")
                }
                if !isBuiltIn {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除此数据源", systemImage: "trash")
                    }
                }
            }

            // 右侧：自定义数据源独立删除按钮（支持遥控器向右切换焦点选中）
            if !isBuiltIn {
                Button(action: {
                    showDeleteConfirm = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(isTrashFocused ? .white : .red.opacity(0.85))
                        Text("删除")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isTrashFocused ? .white : .red.opacity(0.75))
                    }
                    .frame(width: 80, height: 86)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(isTrashFocused ? Color.red.opacity(0.85) : Color.red.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isTrashFocused ? Color.white : Color.red.opacity(0.3), lineWidth: isTrashFocused ? 3 : 1)
                    )
                    .tvFocusBorder(isFocused: isTrashFocused, cornerRadius: 18)
                }
                .buttonStyle(TVZeroHighlightButtonStyle())
                .focused($isTrashFocused)
                .focusEffectDisabled()
                .accessibilityIdentifier("settings.source.delete.\(id)")
                .alert("删除数据源", isPresented: $showDeleteConfirm) {
                    Button("取消", role: .cancel) {}
                    Button("确认删除", role: .destructive) {
                        onRemove()
                    }
                } message: {
                    Text("确定要删除数据源「\(name)」(\(id).js) 吗？删除后本地文件将被彻底移除。")
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}
