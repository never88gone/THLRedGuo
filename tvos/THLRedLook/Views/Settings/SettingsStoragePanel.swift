import SwiftUI

// MARK: - 缓存与存储管理面板
public struct SettingsStoragePanel: View {
    @State private var storageInfo: [String: Any]? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var saveNotice: String? = nil

    public init() {}

    public var body: some View {
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

// MARK: - 存储信息卡片
public struct StorageInfoCard: View {
    public let title: String
    public let value: String
    public let icon: String
    @FocusState private var isFocused: Bool

    public init(title: String, value: String, icon: String) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    public var body: some View {
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
