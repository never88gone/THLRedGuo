import SwiftUI
import CoreImage.CIFilterBuiltins

public enum SettingsCategory: String, CaseIterable, Identifiable {
    case sources = "sources"
    case sync = "sync"
    case network = "network"
    case cache = "cache"
    case about = "about"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sources: return "站源管理"
        case .sync: return "iCloud 同步"
        case .network: return "网络与策略"
        case .cache: return "存储与缓存"
        case .about: return "系统与关于"
        }
    }

    public var subtitle: String {
        switch self {
        case .sources: return "当前活跃影视源"
        case .sync: return "多端观看记录与配置同步"
        case .network: return "代理模式与解析并发度"
        case .cache: return "沙盒空间占用与清理"
        case .about: return "版本信息与核心技术栈"
        }
    }

    public var icon: String {
        switch self {
        case .sources: return "antenna.radiowaves.left.and.right"
        case .sync: return "icloud.fill"
        case .network: return "network"
        case .cache: return "internaldrive.fill"
        case .about: return "info.circle.fill"
        }
    }
}

public struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedCategory: SettingsCategory = .sources
    @FocusState private var focusedCategory: SettingsCategory?
    private enum ICloudFocusTarget: Hashable {
        case toggle
        case syncNow
    }
    @FocusState private var icloudFocus: ICloudFocusTarget?
    @Namespace private var settingsScope
    @State private var saveNotice: String?
    @State private var pingLatency: Int? = 28
    @State private var isTestingPing: Bool = false
    @State private var pingStatus: String = "良好 (28ms)"
    @State private var pingErrorDetail: String? = nil
    @State private var autoSavedTip: String? = nil

    public var forceFocusActiveSource: Bool = false
    public var focusSidebarTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)? = nil

    @State private var wasInContentPanel: Bool = false

    @EnvironmentObject private var jsService: JSSourceService
    @State private var showingSourceDiagnostics = false
    @State private var showingImportAlert = false
    @State private var showingClearAllAlert = false
    @State private var importURLString = ""
    @State private var isImporting = false


    private var appVersionDisplay: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version)+\(build)"
    }

    public init(
        initialCategory: SettingsCategory = .sources,
        forceFocusActiveSource: Bool = false,
        focusSidebarTrigger: Int = 0,
        onRequestFocusTopNav: (() -> Void)? = nil
    ) {
        self._selectedCategory = State(initialValue: initialCategory)
        self.forceFocusActiveSource = forceFocusActiveSource
        self.focusSidebarTrigger = focusSidebarTrigger
        self.onRequestFocusTopNav = onRequestFocusTopNav
    }

    public var body: some View {
        HStack(spacing: 36) {
            // 左侧：分类导航侧边栏
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Image("applogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: TVTheme.primary.opacity(0.4), radius: 8, x: 0, y: 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("系统设置")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                        Text("糖葫芦Haw · 控制中心")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                VStack(spacing: 12) {
                    ForEach(SettingsCategory.allCases) { category in
                        SettingsNavButton(
                            category: category,
                            isSelected: selectedCategory == category,
                            isFocused: focusedCategory == category
                        ) {
                            selectedCategory = category
                            focusedCategory = category
                        }
                        .focused($focusedCategory, equals: category)
                    }
                }

                Spacer()
            }
            .frame(width: 360)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.13).opacity(0.95))
            )
            .focusSection()
            .defaultFocus($focusedCategory, selectedCategory)

            // 右侧内容
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    switch selectedCategory {
                    case .sources:
                        sourcesPanel
                    case .sync:
                        iCloudSyncPanel
                    case .network:
                        networkPanel
                    case .cache:
                        StorageSettingsView()
                    case .about:
                        aboutPanel
                    }
                }
                .padding(.top, 36)
                .padding(.bottom, 48)
                .padding(.leading, 32)
                .padding(.trailing, 48)
            }
            .clipShape(Rectangle().inset(by: -60))
            .id(selectedCategory)
            .focusSection()
            .onMoveCommand { direction in
                if direction == .left {
                    NSLog("🎯 [FOCUS_TRACE] Settings 右侧内容区按向左 -> 精确回到当前Tab %@", selectedCategory.rawValue)
                    focusedCategory = selectedCategory
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 24)
        .defaultFocus($focusedCategory, selectedCategory)
        .onChange(of: focusedCategory) { newCat in
            NSLog("🎯 [FOCUS_TRACE] Settings focusedCategory = %@", newCat?.rawValue ?? "nil")
            if let cat = newCat {
                if wasInContentPanel && cat != selectedCategory {
                    // 从右侧内容区向左返回时，修正几何偏差，精确落回当前内容页面对应的 selectedCategory！
                    NSLog("🎯 [FOCUS_TRACE] Settings 捕获右侧向左几何偏差 (%@ -> 纠正为当前选中项 %@)", cat.rawValue, selectedCategory.rawValue)
                    focusedCategory = selectedCategory
                } else {
                    // 用户在左侧侧边栏内部正常上下移动时，才切换内容页面
                    selectedCategory = cat
                }
                wasInContentPanel = false
            } else {
                // 焦点离开左侧列表，进入了右侧内容页面
                wasInContentPanel = true
            }
        }
        .onChange(of: focusSidebarTrigger) { _ in
            focusedCategory = selectedCategory
            wasInContentPanel = false
        }
        .onExitCommand {
            if focusedCategory == nil {
                focusedCategory = selectedCategory
            } else {
                onRequestFocusTopNav?()
            }
        }
        .alert(isPresented: Binding(
            get: { saveNotice != nil },
            set: { if !$0 { saveNotice = nil } }
        )) {
            Alert(title: Text("提示"), message: Text(saveNotice ?? ""), dismissButton: .default(Text("好的")))
        }
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
        .sheet(isPresented: $showingSourceDiagnostics) {
            SourceDiagnosticsView()
        }
        .overlay(
            Group {
                if showingImportAlert {
                    importAlertOverlay
                }
            }
        )
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            let testPage = ProcessInfo.processInfo.environment["TEST_PAGE"]
                ?? (args.firstIndex(of: "-testPage").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil })

            if testPage == "settings_cache" {
                selectedCategory = .cache
            } else if testPage == "settings_about" {
                selectedCategory = .about
            }

            let isImportFlow = testPage == "importFlow"
            
            if isImportFlow {
                showingImportAlert = true
                importURLString = "http://127.0.0.1:8991/hongguo.js"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    importPlugin()
                }
            }

            if args.contains("-testCustomSource") {
                Task {
                    let dummyJS = """
                    const plugin = {
                        meta: {
                            id: "test_custom_spider",
                            name: "自定义测试爬虫",
                            version: "1.0.0",
                            author: "TestUser"
                        },
                        search: async function(keyword, page) { return []; },
                        detail: async function(id) { return {}; },
                        play: async function(url) { return { url: url }; }
                    };
                    plugin;
                    """
                    _ = try? await NativeRepository.shared.jsSourceSaveAndLoad(script: dummyJS, fileName: "test_custom_spider.js", autoSelect: false)
                    await jsService.refresh()
                }
            }
        }
    }
    // MARK: - 1. 站源管理与导入面板
    private var sourcesPanel: some View {
        VStack(alignment: .leading, spacing: 32) {
            panelHeader(title: "站源管理", desc: "配置并选择当前要使用的影视数据源。内置支持官方标准短剧源，也可导入自定义 JS 插件。")
            
            TVButton(title: "数据源诊断", icon: "stethoscope", isProminent: true) {
                showingSourceDiagnostics = true
            }
            .accessibilityIdentifier("settings.sourceDiagnostics")

            // 顶部操作栏
            HStack(spacing: 20) {
                let isHongguoInstalled = jsService.sources.contains(where: { ($0["id"] as? String) == "hongguo" })
                let isHongguoActive = jsService.activeSourceId == "hongguo"

                TVButton(
                    title: isHongguoInstalled ? (isHongguoActive ? "官方数据源 (已激活)" : "设为默认源") : "导入官方数据源",
                    icon: isHongguoActive ? "checkmark.circle.fill" : "sparkles.tv.fill",
                    isProminent: true
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

                TVButton(title: "网络链接导入", icon: "plus.app.fill") {
                    showingImportAlert = true
                }

                let hasCustomSources = jsService.sources.contains(where: { (($0["id"] as? String) ?? "").lowercased() != "hongguo" })
                if hasCustomSources {
                    TVButton(title: "清空自定义源", icon: "trash.circle.fill") {
                        showingClearAllAlert = true
                    }
                    .accessibilityIdentifier("settings.clearAllSources")
                }

                Spacer()
            }
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


    // MARK: - iCloud 云端同步面板
    @ObservedObject private var icloudSync = ICloudSyncService.shared

    private var iCloudSyncPanel: some View {
        VStack(alignment: .leading, spacing: 32) {
            panelHeader(title: "iCloud 多端同步", desc: "通过 Apple 官方 iCloud 键值存储，在登录同一 Apple ID 的 iOS、macOS 和 Apple TV 设备间实时同步配置、观看进度与追剧收藏。")

            // 1. 开关卡片
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 22))
                            .foregroundColor(TVTheme.primary)
                        Text("启用 iCloud 云端同步")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(icloudSync.isSyncEnabled ? "已开启 · 自动在苹果全生态设备间实时同步观看历史、追剧收藏与偏好设置" : "已停用 · 所有记录仅保存在当前设备，不进行云端同步")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Button(action: {
                    icloudSync.isSyncEnabled.toggle()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: icloudSync.isSyncEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text(icloudSync.isSyncEnabled ? "已开启" : "已关闭")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(icloudSync.isSyncEnabled ? .white : .white.opacity(0.85))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(icloudFocus == .toggle 
                                  ? (icloudSync.isSyncEnabled ? TVTheme.primaryHover : Color.white.opacity(0.28)) 
                                  : (icloudSync.isSyncEnabled ? TVTheme.primary : Color.white.opacity(0.14)))
                    )
                    .tvFocusBorder(isFocused: icloudFocus == .toggle, cornerRadius: 14)
                }
                .buttonStyle(TVZeroHighlightButtonStyle())
                .focusEffectDisabled()
                .focused($icloudFocus, equals: .toggle)
                .accessibilityIdentifier("settings.icloud.toggle")
                .onMoveCommand { direction in
                    if direction == .down && icloudSync.isSyncEnabled {
                        icloudFocus = .syncNow
                    } else if direction == .left {
                        focusedCategory = .sync
                    }
                }
            }
            .padding(24)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .focusSection()

            // 2. 状态概览与立即同步卡片
            if icloudSync.isSyncEnabled {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                                .font(.system(size: 22))
                                .foregroundColor(TVTheme.primary)
                            Text("同步概览与状态")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text(icloudSync.lastStatusMessage)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.85))
                            .accessibilityIdentifier("settings.icloud.status")

                        if let date = icloudSync.lastSyncDate {
                            Text("上次同步时间: " + DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .medium))
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }

                    Spacer()

                    Button(action: {
                        icloudSync.syncWithCloud()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 18, weight: .bold))
                            Text(icloudSync.isSyncing ? "正在同步..." : "立刻同步")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(icloudFocus == .syncNow ? TVTheme.primaryHover : TVTheme.primary)
                        )
                        .tvFocusBorder(isFocused: icloudFocus == .syncNow, cornerRadius: 14)
                    }
                    .buttonStyle(TVZeroHighlightButtonStyle())
                    .focusEffectDisabled()
                    .focused($icloudFocus, equals: .syncNow)
                    .accessibilityIdentifier("settings.icloud.syncNow")
                    .disabled(icloudSync.isSyncing)
                    .onMoveCommand { direction in
                        if direction == .up {
                            icloudFocus = .toggle
                        } else if direction == .left {
                            focusedCategory = .sync
                        }
                    }
                }
                .padding(24)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .focusSection()
            }
        }
        .focusSection()
        .defaultFocus($icloudFocus, .toggle)
        .onChange(of: icloudSync.isSyncEnabled) { _, isEnabled in
            if !isEnabled {
                icloudFocus = .toggle
            }
        }
    }

    // MARK: - 2. 网络与抓取面板（全面优化样式，带实时测速与自适应调优）
    private var networkPanel: some View {
        VStack(alignment: .leading, spacing: 32) {
            panelHeader(title: "网络与资源抓取设置", desc: "配置电视网络连接模式与切片解析并发度，优化大屏端视频加载体验。")

            // 1. 实时网络与 CDN 延迟诊断横幅卡片
            NetworkStatusHeroCard(
                pingStatus: pingStatus,
                latency: pingLatency,
                isTesting: isTestingPing,
                errorDetail: pingErrorDetail
            ) {
                testNetworkPing()
            }

            // 2. 代理模式选择卡片组
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("网络代理连接模式")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    if let tip = autoSavedTip {
                        Text(tip)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 4)

                HStack(spacing: 20) {
                    ProxyModeOptionButton(
                        title: "直连高速 (推荐)",
                        subtitle: "绕过代理，直接连接影视源 CDN 节点，低延迟 4K 秒开",
                        icon: "bolt.fill",
                        accentColor: .yellow,
                        isSelected: viewModel.proxyMode == "direct"
                    ) {
                        viewModel.proxyMode = "direct"
                        viewModel.saveSettings()
                        triggerAutoSaveTip("已切换为直连高速模式")
                    }

                    ProxyModeOptionButton(
                        title: "系统全局代理",
                        subtitle: "同步 Apple TV 系统的全局 VPN 与路由扩展规则",
                        icon: "network.badge.shield.half.filled",
                        accentColor: .blue,
                        isSelected: viewModel.proxyMode == "auto"
                    ) {
                        viewModel.proxyMode = "auto"
                        viewModel.saveSettings()
                        triggerAutoSaveTip("已切换为系统全局代理模式")
                    }

                    ProxyModeOptionButton(
                        title: "自定义节点模式",
                        subtitle: "端侧智能分配端口，配合局域网透明旁路节点",
                        icon: "slider.horizontal.3",
                        accentColor: .purple,
                        isSelected: viewModel.proxyMode == "manual"
                    ) {
                        viewModel.proxyMode = "manual"
                        viewModel.saveSettings()
                        triggerAutoSaveTip("已启用自定义节点模式")
                    }
                }
            }

            // 3. 并行解析线程数 (并发度)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("并行解析线程数 (并发度)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text(concurrencyDescription(viewModel.concurrency))
                            .font(.system(size: 14))
                            .foregroundColor(TVTheme.primary)
                    }

                    Spacer()

                    Text("当前: \(viewModel.concurrency) 线程")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(TVTheme.primary)
                }

                HStack(spacing: 14) {
                    ForEach(1...6, id: \.self) { num in
                        TVCapsuleButton(
                            title: "\(num) 线程",
                            isSelected: viewModel.concurrency == num
                        ) {
                            viewModel.concurrency = num
                            viewModel.saveSettings()
                            triggerAutoSaveTip("并发线程数已设置为 \(num)")
                        }
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.13, green: 0.13, blue: 0.17))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            // 4. 请求防封安全间隔
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("请求防封安全间隔")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text(intervalDescription(viewModel.intervalMs))
                            .font(.system(size: 14))
                            .foregroundColor(TVTheme.primary)
                    }

                    Spacer()

                    Text("当前: \(viewModel.intervalMs) 毫秒")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(TVTheme.primary)
                }

                HStack(spacing: 12) {
                    ForEach([0, 100, 250, 500, 1000, 2000], id: \.self) { ms in
                        TVCapsuleButton(
                            title: ms == 0 ? "0ms 无延时" : "\(ms)ms",
                            isSelected: viewModel.intervalMs == ms
                        ) {
                            viewModel.intervalMs = ms
                            viewModel.saveSettings()
                            triggerAutoSaveTip("安全间隔已设为 \(ms)ms")
                        }
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.13, green: 0.13, blue: 0.17))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            // 5. 休眠与锁屏设置 (Wakelock)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("休眠与常亮策略")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 4)

                HStack(spacing: 20) {
                    ProxyModeOptionButton(
                        title: "禁止系统自动休眠锁屏",
                        subtitle: "开启后避免长时间大批量短剧下载时电视熄屏导致后台任务中断",
                        icon: "lightbulb.fill",
                        accentColor: .orange,
                        isSelected: viewModel.keepScreenOn
                    ) {
                        viewModel.keepScreenOn.toggle()
                        viewModel.saveSettings()
                        triggerAutoSaveTip(viewModel.keepScreenOn ? "已开启屏幕常亮" : "已关闭屏幕常亮")
                    }
                }
            }

            // 5. 底部快捷操作行
            HStack(spacing: 20) {
                TVButton(title: "恢复推荐网络默认值", icon: "arrow.counterclockwise") {
                    viewModel.proxyMode = "direct"
                    viewModel.concurrency = 3
                    viewModel.intervalMs = 250
                    viewModel.saveSettings()
                    triggerAutoSaveTip("已重置为最佳默认配置")
                    saveNotice = "网络与抓取配置已重置为推荐默认参数 (直连 · 3并发 · 250ms)"
                }

                Spacer()

                TVButton(title: "测试网络连通性", icon: "antenna.radiowaves.left.and.right") {
                    testNetworkPing()
                }

                TVButton(title: "保存并应用配置", icon: "checkmark.circle.fill", isProminent: true) {
                    viewModel.saveSettings()
                    saveNotice = "网络与抓取配置已保存，当前设置均在本端实时生效"
                }
            }
            .padding(.top, 4)
        }
    }

    private func concurrencyDescription(_ num: Int) -> String {
        switch num {
        case 1...2: return "适中策略：适合轻量网络或移动热点，平稳低功耗"
        case 3...4: return "推荐策略：智能多切片并发缓冲，大屏播放最流畅"
        default: return "极速策略：适合千兆宽带环境，多线程全速吞吐"
        }
    }

    private func intervalDescription(_ ms: Int) -> String {
        switch ms {
        case 0: return "狂暴无延时：切片解析无等待，加载极快"
        case 1...150: return "高速模式：兼顾流畅切片与请求防抖"
        case 151...350: return "智能均衡推荐：官方防封频控最佳平衡点"
        default: return "保守稳定：最大程度避免频繁请求触发短时限制"
        }
    }

    private func triggerAutoSaveTip(_ message: String) {
        autoSavedTip = "✓ \(message)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if autoSavedTip == "✓ \(message)" {
                autoSavedTip = nil
            }
        }
    }

    private func testNetworkPing() {
        isTestingPing = true
        pingErrorDetail = nil
        let start = Date()
        Task {
            do {
                guard let url = URL(string: "https://lf3-shortplay-tos.snssdk.com") else {
                    throw NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效探测目标地址"])
                }
                var req = URLRequest(url: url)
                req.httpMethod = "HEAD"
                req.timeoutInterval = 8
                let (_, response) = try await URLSession.shared.data(for: req)
                let elapsed = max(16, Int(Date().timeIntervalSince(start) * 1000))
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200

                await MainActor.run {
                    self.pingLatency = elapsed
                    if statusCode >= 400 {
                        let (cat, reason, _) = SourceDiagnostics.classify(error: nil, httpStatus: statusCode, body: nil, isJS: false)
                        self.pingStatus = "异常 (\(statusCode))"
                        self.pingErrorDetail = "【\(cat.tag)】\(reason)"
                    } else if elapsed < 50 {
                        self.pingStatus = "极佳 (\(elapsed)ms)"
                        self.pingErrorDetail = nil
                    } else if elapsed < 120 {
                        self.pingStatus = "良好 (\(elapsed)ms)"
                        self.pingErrorDetail = nil
                    } else {
                        self.pingStatus = "稍慢 (\(elapsed)ms)"
                        self.pingErrorDetail = nil
                    }
                    self.isTestingPing = false
                }
            } catch {
                let (cat, reason, advice) = SourceDiagnostics.classify(error: error, httpStatus: nil, body: nil, isJS: false)
                await MainActor.run {
                    self.pingLatency = nil
                    self.pingStatus = "【\(cat.tag)】"
                    self.pingErrorDetail = "\(reason)。建议：\(advice)"
                    self.isTestingPing = false
                }
            }
        }
    }

    // MARK: - 4. 系统与关于面板（全面优化样式，高质感电视端大屏视觉）
    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 32) {
            panelHeader(title: "系统与关于", desc: "Apple tvOS 纯原生独立大屏端短剧体验系统与核心架构信息。")

            // 品牌横幅交互卡片
            AboutHeroCard(appVersion: appVersionDisplay) {
                saveNotice = "当前系统已是最新版本 v\(appVersionDisplay)，核心引擎状态运行良好。"
            }

            // Telegram 交流与反馈卡片（大屏扫码）
            AboutTelegramCard()

            // 核心架构与技术规格六宫格矩阵
            VStack(alignment: .leading, spacing: 16) {
                Text("系统架构与核心引擎规格")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 4)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20)
                    ],
                    spacing: 20
                ) {
                    AboutFocusCard(
                        title: "原生开发架构",
                        value: "Swift 6.0 · SwiftUI · AVKit",
                        icon: "swift",
                        badgeColor: .orange
                    )
                    AboutFocusCard(
                        title: "视频解码链路",
                        value: "AVPlayerLayer 硬件直出 (透底渐变)",
                        icon: "play.rectangle.on.rectangle.fill",
                        badgeColor: .red
                    )
                    AboutFocusCard(
                        title: "遥控焦点引擎",
                        value: "Apple TV Siri Remote 原生驱动",
                        icon: "appletv.fill",
                        badgeColor: .purple
                    )
                    AboutFocusCard(
                        title: "局域网互联服务",
                        value: "Bonjour Discovery (_zgj-link._tcp)",
                        icon: "network",
                        badgeColor: .blue
                    )
                    AboutFocusCard(
                        title: "沙盒存储机制",
                        value: "CachesDirectory 空间自适配管理",
                        icon: "internaldrive.fill",
                        badgeColor: .green
                    )
                    AboutFocusCard(
                        title: "隐私安全合规",
                        value: "纯本地闭环解析 · 零数据上报",
                        icon: "checkmark.shield.fill",
                        badgeColor: .cyan
                    )
                }
            }

            // 合规与隐私声明卡片
            AboutDisclaimerCard()
        }
    }

    private func panelHeader(title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            Text(desc)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))
        }
    }
}

// MARK: - 左侧导航按钮（无白底纯净焦点，带双态清晰指示）
struct SettingsNavButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // 左侧选中条指示器
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? TVTheme.primary : Color.clear)
                    .frame(width: 4, height: 26)

                Image(systemName: category.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isFocused ? .white : (isSelected ? TVTheme.primary : .gray))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.system(size: 19, weight: (isSelected || isFocused) ? .bold : .medium))
                        .foregroundColor(isFocused ? .white : (isSelected ? .white : .white.opacity(0.75)))
                    Text(category.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(isFocused ? .white.opacity(0.9) : (isSelected ? .white.opacity(0.7) : .gray))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isFocused ? .white : TVTheme.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isFocused
                            ? TVTheme.primary
                            : (isSelected ? Color(red: 0.22, green: 0.14, blue: 0.17) : Color.clear)
                    )
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 16)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
    }
}

// MARK: - 当前生效站源卡片（可聚焦，顺滑承接来自侧边栏的向右焦点，预留防裁切间距）
struct ActiveSourceCard: View {
    let source: SourceSite
    var forceFocused: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
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
                    .fill(effectiveFocused ? Color(red: 0.22, green: 0.18, blue: 0.22) : Color(red: 0.14, green: 0.14, blue: 0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(effectiveFocused ? TVTheme.primary : TVTheme.primary.opacity(0.35), lineWidth: 1.5)
            )
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
struct SourceCardButton: View {
    let source: SourceSite
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
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

// MARK: - 实时网络与 CDN 延迟诊断横幅卡片
struct NetworkStatusHeroCard: View {
    let pingStatus: String
    let latency: Int?
    let isTesting: Bool
    var errorDetail: String? = nil
    let onTest: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onTest) {
            HStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: errorDetail != nil
                                    ? [Color.red.opacity(0.35), Color.orange.opacity(0.2)]
                                    : [Color.blue.opacity(0.35), Color.purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(errorDetail != nil ? Color.red.opacity(0.4) : Color.blue.opacity(0.3), lineWidth: 1.5)
                        )

                    Image(systemName: errorDetail != nil ? "exclamationmark.triangle.fill" : "wifi")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(errorDetail != nil ? .orange : .cyan)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text("端侧引擎与 CDN 链路")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        Text(errorDetail != nil ? "链路异常" : "端侧直连就绪")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(errorDetail != nil ? Color.red.opacity(0.8) : Color.blue.opacity(0.8))
                            .clipShape(Capsule())
                    }

                    if let err = errorDetail {
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                            .lineLimit(2)
                    } else {
                        Text("设备端独立网络栈 · 环回调度响应正常 · 短剧专线 CDN")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                HStack(spacing: 16) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("CDN 响应状态")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        HStack(spacing: 6) {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Circle()
                                    .fill(errorDetail != nil ? Color.red : Color.green)
                                    .frame(width: 8, height: 8)
                            }

                            Text(isTesting ? "正在测速..." : pingStatus)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isTesting ? .yellow : (errorDetail != nil ? .red : .green))
                        }
                    }

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isFocused ? TVTheme.primary : .white.opacity(0.6))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                isFocused ? Color(red: 0.16, green: 0.18, blue: 0.26) : Color(red: 0.12, green: 0.13, blue: 0.18),
                                isFocused ? Color(red: 0.12, green: 0.13, blue: 0.20) : Color(red: 0.10, green: 0.10, blue: 0.13)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isFocused ? TVTheme.primary : (errorDetail != nil ? Color.red.opacity(0.3) : Color.white.opacity(0.08)), lineWidth: isFocused ? 2.5 : 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 20)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

// MARK: - 代理模式选项卡片（预留防裁切间距，支持高质感主题徽标）
struct ProxyModeOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    var accentColor: Color = TVTheme.primary
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(isSelected || isFocused ? 0.35 : 0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(isSelected || isFocused ? .white : accentColor)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(TVTheme.primary)
                    }
                }

                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.68))
                    .lineLimit(2)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 128)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? Color(red: 0.22, green: 0.14, blue: 0.18) : (isFocused ? Color(red: 0.22, green: 0.22, blue: 0.26) : Color(red: 0.13, green: 0.13, blue: 0.17)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? TVTheme.primary : (isFocused ? Color.white.opacity(0.2) : Color.white.opacity(0.06)), lineWidth: isSelected ? 2 : 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 18)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

// MARK: - 关于品牌横幅可聚焦卡片（预留防裁切间距，电影感微暗渐变）
struct AboutHeroCard: View {
    let appVersion: String
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 32) {
                // 应用图标 / 品牌徽标
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 140, height: 140)

                    Image("applogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color.white.opacity(0.25), lineWidth: 2)
                        )
                        .shadow(color: TVTheme.primary.opacity(0.6), radius: 20, x: 0, y: 10)
                }

                // 核心品牌信息
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        Text("糖葫芦Haw · 电视版")
                            .font(.system(size: 44, weight: .heavy))
                            .foregroundColor(.white)

                        Text("v\(appVersion)")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(TVTheme.primary)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 12) {
                        HeroTagPill(title: "Apple TV 原生独占")
                        HeroTagPill(title: "纯净沉浸体验")
                        HeroTagPill(title: "端侧自闭环引擎")
                    }

                    Text("独立端侧协议解析 · 原生硬件硬解渲染 · 零远端服务依赖")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.72))
                }

                Spacer()

                // 运行状态指示器
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .shadow(color: .green.opacity(0.8), radius: 6)
                        Text("运行状态")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Text("良好 · 就绪")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .padding(26)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                isFocused ? Color(red: 0.24, green: 0.12, blue: 0.16) : Color(red: 0.18, green: 0.10, blue: 0.14),
                                isFocused ? Color(red: 0.16, green: 0.12, blue: 0.18) : Color(red: 0.11, green: 0.11, blue: 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.1), lineWidth: isFocused ? 2.5 : 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 22)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

struct HeroTagPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - 关于信息可聚焦卡片（预留防裁切间距，强化层级与图标高亮）
struct AboutFocusCard: View {
    let title: String
    let value: String
    let icon: String
    var badgeColor: Color = .red

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(badgeColor.opacity(isFocused ? 0.35 : 0.18))
                        .frame(width: 52, height: 52)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isFocused ? .white : badgeColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    Text(value)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isFocused ? Color(red: 0.22, green: 0.22, blue: 0.28) : Color(red: 0.13, green: 0.13, blue: 0.17))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.06), lineWidth: isFocused ? 2 : 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 18)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

// MARK: - Telegram 交流反馈与扫码卡片（大屏扫码）
struct AboutTelegramCard: View {
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 28) {
                // 二维码图片展示区
                Image("telegram_qr")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 156, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)

                // 右侧说明
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(TVTheme.primary)

                        Text("Telegram 交流与反馈")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)

                        Text("@TANGHULUTVOS")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.75))
                            .clipShape(Capsule())
                    }

                    Text("手机打开 Telegram 扫描左侧二维码，即可加入官方交流群组；也可直接搜索 @tanghulutvos 关注反馈。")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.75))
                        .lineSpacing(4)

                    Text("联系地址：https://t.me/tanghulutvos")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(TVTheme.primaryHover)
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(isFocused ? Color(red: 0.16, green: 0.18, blue: 0.25) : Color(red: 0.10, green: 0.11, blue: 0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.08), lineWidth: isFocused ? 2 : 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 22)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

// MARK: - 合规与隐私声明卡片
struct AboutDisclaimerCard: View {
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {}) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 26))
                    .foregroundColor(isFocused ? TVTheme.primary : .white.opacity(0.65))
                    .frame(width: 32)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("免责声明与合规承诺")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text("1. 本项目为独立 Apple tvOS 客户端系统，仅供大屏原生开发技术学习与非商业研究使用；\n2. 短剧及流媒体数据均来源于网络公开接口，开发者不搭建中转服务、不存储任何音视频内容；版权归原版权方所有；\n3. 视频解析与播放均在 Apple TV 设备本地沙箱闭环执行，零隐私数据上报，使用者需对自配内容自行承担法律责任。")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.65))
                        .lineSpacing(4)
                }
                Spacer()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isFocused ? Color(red: 0.18, green: 0.18, blue: 0.22) : Color(red: 0.11, green: 0.11, blue: 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? TVTheme.primary : Color.white.opacity(0.06), lineWidth: 1)
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 18)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}
import SwiftUI

struct StorageSettingsView: View {
    @State private var storageInfo: [String: Any]? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var saveNotice: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("缓存与存储管理")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)
                Text("查看当前设备缓存占用及缓存目录路径。")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.6))
            }

            if isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if let error = errorMessage {
                Text("无法获取存储信息：\(error)")
                    .foregroundColor(.red)
                    .padding(.top, 40)
            } else if let info = storageInfo {
                VStack(spacing: 24) {
                    let bytes = info["bytes"] as? Int ?? 0
                    let free = info["free"] as? Int ?? -1
                    let files = info["files"] as? Int ?? 0
                    let directory = info["directory"] as? String ?? ""

                    StorageInfoCard(title: "已使用", value: formatBytes(bytes), icon: "internaldrive.fill")
                    StorageInfoCard(title: "剩余空间", value: formatBytes(free), icon: "externaldrive.badge.checkmark")
                    StorageInfoCard(title: "文件数量", value: "\(files) 个文件", icon: "doc.on.doc")
                    StorageInfoCard(title: "缓存路径", value: directory, icon: "folder.fill")
                }
                .padding(.trailing, 40)
            }
            // 清理操作区
            VStack(alignment: .leading, spacing: 14) {
                Text("缓存清理")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 4)

                HStack(spacing: 20) {
                    TVButton(title: "清理播放缓存", icon: "trash.fill", isProminent: true) {
                        clearPlaybackCache()
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .onAppear {
            loadStorageInfo()
        }
        .alert(isPresented: Binding(
            get: { saveNotice != nil },
            set: { if !$0 { saveNotice = nil } }
        )) {
            Alert(title: Text("提示"), message: Text(saveNotice ?? ""), dismissButton: .default(Text("好的")))
        }
    }


    private func clearPlaybackCache() {
        let fm = FileManager.default
        var cleared = 0
        let dirs: [URL] = [
            fm.temporaryDirectory,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        for dir in dirs {
            if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for item in items where item.pathExtension == "ts" || item.pathExtension == "tmp" || item.lastPathComponent.hasPrefix("hls_") {
                    try? fm.removeItem(at: item)
                    cleared += 1
                }
            }
        }
        saveNotice = "播放临时切片缓存已清理（共 \(cleared) 个文件）"
        loadStorageInfo()
    }

    private func loadStorageInfo() {

        isLoading = true
        errorMessage = nil
        Task {
            do {
                let info = try await NativeRepository.shared.storage()
                await MainActor.run {
                    self.storageInfo = info
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 0 { return "暂不可用" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
}

struct StorageInfoCard: View {
    let title: String
    let value: String
    let icon: String
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isFocused ? TVTheme.primary : .white.opacity(0.7))
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text(value)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFocused ? Color(red: 0.20, green: 0.20, blue: 0.24) : Color(red: 0.13, green: 0.13, blue: 0.17))
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
struct JSSourcePluginCard: View {
    let id: String
    let name: String
    let version: String
    let author: String
    let isActive: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    @FocusState private var isCardFocused: Bool
    @FocusState private var isTrashFocused: Bool
    @State private var showDeleteConfirm = false

    private var isBuiltIn: Bool {
        id.lowercased() == "hongguo"
    }

    var body: some View {
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
                        .fill(isCardFocused ? Color(red: 0.20, green: 0.17, blue: 0.22) : Color(red: 0.14, green: 0.14, blue: 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(isCardFocused ? TVTheme.primary : (isActive ? TVTheme.primary.opacity(0.4) : Color.white.opacity(0.08)), lineWidth: isCardFocused ? 3 : 1)
                )
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


// MARK: - 数据源诊断与详细信息全链路视图
private enum DiagFocusTarget: Hashable {
    case action(String)
    case entry(UUID)
}

@MainActor
private struct SourceDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recorder = SourceDiagnostics.shared
    @ObservedObject private var runner = SourceDiagnosticRunner.shared
    @FocusState private var focusedTarget: DiagFocusTarget?
    @State private var showingQR = false
    @State private var showingFullReport = false
    @State private var reportImage: UIImage?
    @State private var selectedDetailEntry: SourceDiagnosticEntry? = nil
    @State private var lastSelectedEntryId: UUID? = nil

    private var displayEntries: [SourceDiagnosticEntry] {
        recorder.entries.reversed()
    }

    private func focusFirstEntry() {
        if let first = displayEntries.first {
            focusedTarget = .entry(first.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("数据源诊断").font(.system(size: 48, weight: .bold))
            Text("红果官方源 · 应用 \(SourceDiagnostics.version) · 源指纹 \(SourceDiagnostics.sourceHash.prefix(12))")
                .font(.system(size: 29))
            Text("检测使用独立游客会话，不影响收藏、历史和当前数据源。包含网络DNS、JS引擎、游客会话与剧集解析全链路检测。")
                .font(.system(size: 24)).foregroundStyle(.secondary)

            // 操作按钮栏
            HStack(spacing: 24) {
                TVButton(
                    title: runner.running ? "检测中…" : "开始检测",
                    icon: "network",
                    isProminent: true,
                    isExternalFocused: focusedTarget == .action("run"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    Task { await runner.run() }
                }
                .disabled(runner.running)
                .focused($focusedTarget, equals: .action("run"))
                .accessibilityIdentifier("sourceDiagnostics.run")

                TVButton(
                    title: "详细报告",
                    icon: "doc.text.magnifyingglass",
                    isExternalFocused: focusedTarget == .action("report"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    showingFullReport = true
                }
                .focused($focusedTarget, equals: .action("report"))
                .accessibilityIdentifier("sourceDiagnostics.report")

                TVButton(
                    title: "反馈二维码",
                    icon: "qrcode",
                    isExternalFocused: focusedTarget == .action("qr"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    let filter = CIFilter.qrCodeGenerator()
                    filter.message = Data(recorder.qrText.utf8)
                    filter.correctionLevel = "L"
                    if let output = filter.outputImage,
                       let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 4, y: 4)), from: output.extent.applying(CGAffineTransform(scaleX: 4, y: 4))) {
                        reportImage = UIImage(cgImage: image)
                        showingQR = true
                    }
                }
                .focused($focusedTarget, equals: .action("qr"))
                .accessibilityIdentifier("sourceDiagnostics.qr")

                TVButton(
                    title: "清空记录",
                    icon: "trash",
                    isExternalFocused: focusedTarget == .action("clear"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    recorder.clear()
                }
                .disabled(runner.running)
                .focused($focusedTarget, equals: .action("clear"))
                .accessibilityIdentifier("sourceDiagnostics.clear")

                TVButton(
                    title: "返回",
                    icon: "arrow.backward",
                    isExternalFocused: focusedTarget == .action("back"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    dismiss()
                }
                .focused($focusedTarget, equals: .action("back"))
                .accessibilityIdentifier("sourceDiagnostics.back")
            }

            // 当前诊断状态汇总
            HStack(spacing: 12) {
                if runner.result.contains("失败") {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.red)
                } else if runner.result.contains("完成") {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.green)
                }
                Text(runner.result)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(runner.result.contains("失败") ? .red : (runner.result.contains("完成") ? .green : .white))
                    .accessibilityIdentifier("sourceDiagnostics.result")
            }

            if runner.running { ProgressView() }

            // 诊断明细流式列表（支持精准遥控器焦点上下移动与详细信息交互，高亮严格不缩放溢出）
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let failure = recorder.entries.last(where: { $0.failed && !$0.host.isEmpty }) {
                            Text("最近失败提示：" + SourceDiagnostics.advice(failure))
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                        }

                        if displayEntries.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "stethoscope")
                                    .font(.system(size: 44))
                                    .foregroundColor(.white.opacity(0.35))
                                Text("暂无诊断记录，请点击上方「开始检测」进行全链路连通性检查。")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(48)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            ForEach(Array(displayEntries.enumerated()), id: \.element.id) { index, entry in
                                SourceDiagnosticEntryCardView(
                                    entry: entry,
                                    isFocused: focusedTarget == .entry(entry.id),
                                    onSelect: {
                                        lastSelectedEntryId = entry.id
                                        selectedDetailEntry = entry
                                    },
                                    onUpCommand: {
                                        if index == 0 {
                                            focusedTarget = .action("run")
                                        } else {
                                            let prev = displayEntries[index - 1]
                                            focusedTarget = .entry(prev.id)
                                            withAnimation { proxy.scrollTo(prev.id, anchor: .center) }
                                        }
                                    },
                                    onDownCommand: {
                                        if index + 1 < displayEntries.count {
                                            let next = displayEntries[index + 1]
                                            focusedTarget = .entry(next.id)
                                            withAnimation { proxy.scrollTo(next.id, anchor: .center) }
                                        }
                                    }
                                )
                                .focused($focusedTarget, equals: .entry(entry.id))
                                .accessibilityIdentifier("sourceDiagnostics.entry.\(index)")
                                .id(entry.id)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                }
                .focusSection()
                .onChange(of: focusedTarget) { newTarget in
                    if case .entry(let id) = newTarget {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 40)
        .defaultFocus($focusedTarget, .action("run"))
        .onExitCommand { dismiss() }
        .sheet(item: $selectedDetailEntry, onDismiss: {
            if let id = lastSelectedEntryId {
                focusedTarget = .entry(id)
            }
        }) { entry in
            SourceDiagnosticEntryDetailSheet(entry: entry) {
                lastSelectedEntryId = entry.id
                selectedDetailEntry = nil
            }
        }
        .sheet(isPresented: $showingFullReport, onDismiss: { focusedTarget = .action("report") }) {
            SourceDiagnosticsFullReportSheet(reportText: recorder.report) {
                showingFullReport = false
            }
        }
        .sheet(isPresented: $showingQR, onDismiss: { focusedTarget = .action("qr") }) {
            SourceDiagnosticsQRSheet(reportImage: reportImage) {
                showingQR = false
            }
        }
    }
}

@MainActor
private struct SourceDiagnosticEntryCardView: View {
    let entry: SourceDiagnosticEntry
    let isFocused: Bool
    let onSelect: () -> Void
    var onUpCommand: (() -> Void)? = nil
    var onDownCommand: (() -> Void)? = nil

    @Environment(\.isFocused) private var envIsFocused

    private var activeFocused: Bool {
        isFocused || envIsFocused
    }

    private var cardBackground: Color {
        if activeFocused {
            return entry.failed ? Color(red: 0.35, green: 0.12, blue: 0.14) : Color(red: 0.22, green: 0.20, blue: 0.28)
        } else {
            return entry.failed ? Color.red.opacity(0.12) : Color.white.opacity(0.06)
        }
    }

    private var cardBorderColor: Color {
        if activeFocused {
            return Color.white
        } else {
            return entry.failed ? Color.red.opacity(0.4) : Color.white.opacity(0.08)
        }
    }

    private var cardShadowColor: Color {
        guard activeFocused else { return Color.clear }
        return entry.failed ? Color.red.opacity(0.45) : Color.white.opacity(0.3)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                Text(entry.text)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)

                if !entry.errorDetail.isEmpty {
                    errorDetailRow
                }

                if !entry.suggestion.isEmpty {
                    suggestionRow
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(cardBorderColor, lineWidth: activeFocused ? 3.5 : 1)
            )
            .shadow(color: cardShadowColor, radius: activeFocused ? 12 : 0)
            .animation(TVTheme.focusSpringAnimation, value: activeFocused)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            let statusText: String = (entry.failed ? "失败 · " : "完成 · ") + entry.stage
            let statusColor: Color = entry.failed ? Color(red: 1.0, green: 0.35, blue: 0.35) : Color(red: 0.35, green: 0.9, blue: 0.45)
            Text(statusText)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(statusColor)

            if entry.category != .unknown {
                let badgeBg: Color = entry.failed ? Color.red.opacity(0.85) : Color.blue.opacity(0.8)
                Text(entry.category.tag)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeBg)
                    .clipShape(Capsule())
            }

            if entry.elapsedMs > 0 {
                Text("\(entry.elapsedMs)ms")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 详细信息操作指示
            HStack(spacing: 6) {
                Text("详细信息")
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(activeFocused ? .white : .white.opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(activeFocused ? TVTheme.primary : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
    }

    private var errorDetailRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("失败原因:")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.orange)
            Text(entry.errorDetail)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(.orange.opacity(0.95))
        }
    }

    private var suggestionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("排查建议:")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(TVTheme.primaryHover)
            Text(entry.suggestion)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - 单项诊断技术详细信息弹窗 (支持长文本遥控器滚动与参数网格)
@MainActor
private struct SourceDiagnosticEntryDetailSheet: View {
    let entry: SourceDiagnosticEntry
    let onClose: () -> Void

    @FocusState private var focusedTarget: String?

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: entry.at)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 顶部导航与关闭
            HStack {
                HStack(spacing: 16) {
                    Image(systemName: entry.failed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 38))
                        .foregroundColor(entry.failed ? .red : .green)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Text("诊断项详细信息")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(.white)
                            if entry.category != .unknown {
                                Text(entry.category.tag)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(entry.failed ? Color.red.opacity(0.85) : Color.blue.opacity(0.8))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("探测阶段: \(entry.stage) · 检测时间: \(formattedDate)")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }

                Spacer()

                TVButton(
                    title: "关闭详情",
                    icon: "xmark.circle.fill",
                    isProminent: true,
                    onDownCommand: {
                        focusedTarget = "scrollable"
                    }
                ) {
                    onClose()
                }
                .focused($focusedTarget, equals: "close")
                .accessibilityIdentifier("sourceDiagnostics.detailClose")
            }

            // 中间可滚动详情内容
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // 状态横幅卡片
                    HStack(spacing: 24) {
                        detailStatusPill(
                            title: "状态",
                            value: entry.failed ? "探测失败" : "探测成功",
                            color: entry.failed ? .red : .green
                        )
                        detailStatusPill(
                            title: "响应耗时",
                            value: entry.elapsedMs > 0 ? "\(entry.elapsedMs) ms" : "< 1 ms",
                            color: entry.elapsedMs > 1000 ? .orange : .blue
                        )
                        if entry.status > 0 {
                            detailStatusPill(
                                title: "HTTP 状态码",
                                value: "\(entry.status)",
                                color: entry.status == 200 ? .green : .red
                            )
                        }
                        if !entry.businessCode.isEmpty {
                            detailStatusPill(
                                title: "业务返回码",
                                value: entry.businessCode,
                                color: entry.businessCode == "0" ? .green : .orange
                            )
                        }
                    }

                    // 核心参数网格卡片
                    VStack(alignment: .leading, spacing: 14) {
                        Text("探测参数与链路环境")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            infoRow(label: "探测阶段", value: entry.stage)
                            infoRow(label: "执行上下文", value: entry.context)
                            infoRow(label: "目标主机", value: entry.host.isEmpty ? "本地执行 (无主机)" : entry.host)
                            infoRow(label: "故障分类", value: entry.category.name)
                            if !entry.errorCode.isEmpty {
                                infoRow(label: "错误特征代码", value: entry.errorCode)
                            }
                            if let count = entry.count {
                                infoRow(label: "返回数据条数", value: "\(count) 条")
                            }
                        }
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

                    // 失败具体原因
                    if !entry.errorDetail.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                Text("失败具体原因与技术诊断")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            Text(entry.errorDetail)
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.15))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.35), lineWidth: 1))
                                .cornerRadius(12)
                                .accessibilityIdentifier("sourceDiagnostics.detailError")
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }

                    // 排查建议
                    if !entry.suggestion.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(TVTheme.primaryHover)
                                Text("排查建议与修复措施")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(TVTheme.primaryHover)
                            }
                            Text(entry.suggestion)
                                .font(.system(size: 22))
                                .foregroundColor(.white.opacity(0.95))
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(TVTheme.primary.opacity(0.15))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TVTheme.primary.opacity(0.35), lineWidth: 1))
                                .cornerRadius(12)
                                .accessibilityIdentifier("sourceDiagnostics.detailSuggestion")
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }

                    // 原始摘要信息
                    VStack(alignment: .leading, spacing: 12) {
                        Text("原始摘要信息")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Text(entry.text)
                            .font(.system(size: 18, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(12)
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(12)
                .focusable()
                .focused($focusedTarget, equals: "scrollable")
                .onMoveCommand { direction in
                    if direction == .up {
                        focusedTarget = "close"
                    }
                }
            }
            .focusSection()
        }
        .padding(48)
        .defaultFocus($focusedTarget, "close")
        .onExitCommand { onClose() }
    }

    private func detailStatusPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(color.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.35), lineWidth: 1))
        .cornerRadius(14)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label + ":")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
        }
    }
}

@MainActor
private struct SourceDiagnosticsFullReportSheet: View {
    let reportText: String
    let onClose: () -> Void

    @FocusState private var focusedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("完整技术诊断报告")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                    Text("包含环境指纹、各链路分段耗时与详细错误堆栈，可供技术排查与社区求助")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
                TVButton(
                    title: "关闭报告",
                    icon: "xmark.circle.fill",
                    isProminent: true,
                    onDownCommand: {
                        focusedField = "content"
                    }
                ) {
                    onClose()
                }
                .focused($focusedField, equals: "close")
                .accessibilityIdentifier("sourceDiagnostics.reportClose")
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(reportText)
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .lineSpacing(6)
                        .foregroundColor(.white.opacity(0.95))
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(focusedField == "content" ? Color.white : Color.white.opacity(0.12), lineWidth: focusedField == "content" ? 3.5 : 1)
                        )
                        .shadow(color: focusedField == "content" ? Color.white.opacity(0.3) : Color.clear, radius: 8)
                        .focusable()
                        .focused($focusedField, equals: "content")
                        .accessibilityIdentifier("sourceDiagnostics.reportContent")
                        .onMoveCommand { direction in
                            if direction == .up {
                                focusedField = "close"
                            }
                        }
                }
                .padding(8)
            }
            .focusSection()
        }
        .padding(48)
        .defaultFocus($focusedField, "close")
        .onExitCommand { onClose() }
    }
}

@MainActor
private struct SourceDiagnosticsQRSheet: View {
    let reportImage: UIImage?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("扫码获取诊断报告").font(.system(size: 42, weight: .bold))
            if let reportImage {
                Image(uiImage: reportImage).interpolation(.none).resizable()
                    .scaledToFit().frame(width: 500, height: 500)
                    .padding(24).background(.white)
            }
            Text("包含版本、源指纹和最多最近 8 条脱敏记录。扫码读取文本后手动反馈，不会自动上传。")
                .font(.system(size: 29)).multilineTextAlignment(.center)
            TVButton(title: "返回诊断", icon: "arrow.backward", isProminent: true) { onClose() }
                .accessibilityIdentifier("sourceDiagnostics.qrBack")
        }
        .padding(60)
        .onExitCommand { onClose() }
    }
}
