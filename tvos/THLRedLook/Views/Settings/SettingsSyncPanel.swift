import SwiftUI

// MARK: - iCloud 多端同步面板
public struct SettingsSyncPanel: View {
    @ObservedObject private var icloudSync = ICloudSyncService.shared
    
    private enum ICloudFocusTarget: Hashable {
        case toggle
        case syncNow
    }
    @FocusState private var icloudFocus: ICloudFocusTarget?
    public var onRequestFocusCategory: (() -> Void)? = nil

    public init(onRequestFocusCategory: (() -> Void)? = nil) {
        self.onRequestFocusCategory = onRequestFocusCategory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text("iCloud 多端同步")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("通过 Apple 官方 iCloud 键值存储，在登录同一 Apple ID 的 iOS、macOS 和 Apple TV 设备间实时同步配置、观看进度与追剧收藏。")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

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
                        onRequestFocusCategory?()
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
                            onRequestFocusCategory?()
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
        .onChange(of: icloudSync.isSyncEnabled) { _, isEnabled in
            if !isEnabled {
                icloudFocus = .toggle
            }
        }
    }
}
