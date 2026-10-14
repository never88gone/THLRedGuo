import SwiftUI

/// 全站统一的无数据源纯净模式引导空白视图（Blank State）
public struct TVSourceBlankStateView: View {
    @EnvironmentObject private var jsService: JSSourceService
    @State private var showingImportAlert = false
    @State private var importURLString = ""
    @State private var isImporting = false
    @State private var alertMessage: String?

    public var onImportSuccess: (() -> Void)? = nil

    public init(onImportSuccess: (() -> Void)? = nil) {
        self.onImportSuccess = onImportSuccess
    }

    public var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 110))
                .foregroundColor(TVTheme.primary)

            VStack(spacing: 14) {
                Text("当前未添加数据源插件")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)

                Text("遵循纯净模式，本应用不预装任何数据源。\n请添加网络订阅链接导入 JS 插件以开启短剧体验。")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }

            HStack(spacing: 24) {
                TVButton(title: "添加网络订阅链接", icon: "link.badge.plus", isProminent: true) {
                    showingImportAlert = true
                }
                .frame(width: 320)
            }
            .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            Group {
                if showingImportAlert {
                    importAlertOverlay
                }
            }
        )
        .alert(isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Alert(
                title: Text("提示"),
                message: Text(alertMessage ?? ""),
                dismissButton: .default(Text("好的"))
            )
        }
    }

    private var importAlertOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 32) {
                Text("导入数据源插件")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)

                TextField("请输入 JS 插件链接 (URL)", text: $importURLString)
                    .frame(width: 600)
                    .font(.system(size: 24))

                if isImporting {
                    ProgressView("正在下载并校验插件...")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                HStack(spacing: 24) {
                    TVButton(title: "取消", icon: "xmark") {
                        showingImportAlert = false
                    }

                    TVButton(title: "导入", icon: "arrow.down.doc", isProminent: true) {
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
        let trimmed = importURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isImporting = true
        Task {
            do {
                let success = try await jsService.importFromURL(trimmed)
                await MainActor.run {
                    isImporting = false
                    if success {
                        showingImportAlert = false
                        importURLString = ""
                        onImportSuccess?()
                    } else {
                        alertMessage = "导入插件失败，请检查脚本格式是否正确"
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    alertMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
