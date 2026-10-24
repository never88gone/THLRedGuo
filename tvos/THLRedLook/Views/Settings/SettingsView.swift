import SwiftUI

/// 系统设置主页面（Apple tvOS 原生大屏端控制中心）
/// 架构清晰解耦：各个子模块面板均独立拆分至各个专用 Panel 视图
public struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedCategory: SettingsCategory = .sources
    @FocusState private var focusedCategory: SettingsCategory?
    @State private var saveNotice: String?

    public var initialCategory: SettingsCategory = .sources
    public var forceFocusActiveSource: Bool = false
    public var focusSidebarTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)? = nil

    @EnvironmentObject private var jsService: JSSourceService
    @State private var showingSourceDiagnostics = false

    public init(
        initialCategory: SettingsCategory = .sources,
        forceFocusActiveSource: Bool = false,
        focusSidebarTrigger: Int = 0,
        onRequestFocusTopNav: (() -> Void)? = nil
    ) {
        self.initialCategory = initialCategory
        self._selectedCategory = State(initialValue: initialCategory)
        self.forceFocusActiveSource = forceFocusActiveSource
        self.focusSidebarTrigger = focusSidebarTrigger
        self.onRequestFocusTopNav = onRequestFocusTopNav
    }

    public var body: some View {
        HStack(spacing: 36) {
            // 左侧：分类导航侧边栏（纯净分类列表，不设多余 header，与主导航栏形成清晰层级区分）
            VStack(alignment: .leading, spacing: 14) {
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
                .padding(.top, 12)

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
            .onExitCommand {
                onRequestFocusTopNav?()
            }
            .onMoveCommand { direction in
                if direction == .left {
                    onRequestFocusTopNav?()
                }
            }

            // 右侧内容区：各个子面板高度解耦独立维护
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    switch selectedCategory {
                    case .sources:
                        SettingsSourcesPanel(
                            showingSourceDiagnostics: $showingSourceDiagnostics,
                            saveNotice: $saveNotice
                        )
                    case .sync:
                        SettingsSyncPanel(
                            onRequestFocusCategory: {
                                focusedCategory = .sync
                            }
                        )
                    case .cache:
                        SettingsStoragePanel()
                    case .help:
                        SettingsHelpPanel()
                    case .contact:
                        SettingsContactPanel()
                    case .about:
                        SettingsAboutPanel()
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
                    focusedCategory = selectedCategory
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 24)
        .onChange(of: focusedCategory) { newCat in
            if let cat = newCat {
                selectedCategory = cat
            }
        }
        .onChange(of: focusSidebarTrigger) { _ in
            DispatchQueue.main.async {
                focusedCategory = selectedCategory
            }
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
        .sheet(isPresented: $showingSourceDiagnostics) {
            SourceDiagnosticsSheetView()
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            let testPage = ProcessInfo.processInfo.environment["TEST_PAGE"]
                ?? (args.firstIndex(of: "-testPage").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil })

            var targetCat = initialCategory
            if let testPage = testPage {
                if testPage == "settings_cache" {
                    targetCat = .cache
                } else if testPage == "settings_about" {
                    targetCat = .about
                } else if testPage == "settings_help" {
                    targetCat = .help
                } else if testPage == "settings_contact" {
                    targetCat = .contact
                } else if testPage == "settings_sync" {
                    targetCat = .sync
                } else if testPage == "settings_sources" || testPage == "settings" {
                    targetCat = .sources
                }
            }
            selectedCategory = targetCat
            // 正常启动或侧边栏浏览状态绝不自动抢焦，必须由用户按下 select 或 right 键明确切入
            if let testPage = testPage, testPage != "settings" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    focusedCategory = targetCat
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
}
