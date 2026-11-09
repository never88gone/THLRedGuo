import SwiftUI

// MARK: - 缓存与存储管理面板
public struct SettingsStoragePanel: View {
    @State private var storageInfo: [String: Any]? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var saveNotice: String? = nil

    private let gridColumns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("缓存与存储管理")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)
                Text("查看当前设备缓存占用、剩余磁盘空间及沙盒存储目录路径。")
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
                let bytes = info["bytes"] as? Int ?? 0
                let free = info["free"] as? Int ?? -1
                let files = info["files"] as? Int ?? 0
                let directory = info["directory"] as? String ?? ""

                LazyVGrid(columns: gridColumns, spacing: 20) {
                    StorageInfoCard(title: "已使用缓存空间", value: formatBytes(bytes), icon: "internaldrive.fill")
                    StorageInfoCard(title: "设备可用剩余空间", value: formatBytes(free), icon: "externaldrive.badge.checkmark")
                    StorageInfoCard(title: "缓存文件数量", value: "\(files) 个文件", icon: "doc.on.doc.fill")
                    StorageInfoCard(title: "本地沙盒存储路径", value: directory, icon: "folder.fill")
                }
                .frame(maxWidth: .infinity)
            }

            // 缓存维护与清理操作区
            VStack(alignment: .leading, spacing: 16) {
                Text("缓存与空间维护")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white.opacity(0.95))

                HStack(spacing: 24) {
                    TVButton(title: "清理播放切片缓存", icon: "trash.fill", isProminent: false) {
                        clearPlaybackCache()
                    }
                    .accessibilityIdentifier("settings.storage.clearCache")

                    TVButton(title: "重新统计存储信息", icon: "arrow.triangle.2.circlepath", isProminent: false) {
                        loadStorageInfo()
                    }
                }
            }
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
