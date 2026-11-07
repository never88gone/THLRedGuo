import SwiftUI

/// 系统设置 - 更新内容展示面板
/// 动态读取 tvOS 根目录下的 release.md，按时间倒序排列表达版本演进与功能更新
public struct SettingsReleaseNotesPanel: View {
    @State private var releaseItems: [ReleaseNoteItem] = []
    @FocusState private var focusedItemId: String?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // 顶部面板标题区
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("更新内容")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(TVColors.textPrimary)

                    Text("记录每次版本迭代功能，按时间倒序展示发布日志")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(TVColors.textSecondary)
                }

                Spacer()

                // 当前运行版本状态胶囊
                HStack(spacing: 8) {
                    Circle()
                        .fill(TVColors.successGreen)
                        .frame(width: 10, height: 10)

                    Text("当前版本 v\(currentAppVersion)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(TVColors.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(TVColors.surfaceDark)
                )
                .overlay(
                    Capsule()
                        .stroke(TVColors.borderSubtle, lineWidth: 1)
                )
            }
            .padding(.bottom, 8)

            // 版本更新日志列表（按时间倒序排列）
            if releaseItems.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: TVColors.primary))
                        .scaleEffect(1.2)
                    Text("正在加载更新日志...")
                        .font(.system(size: 17))
                        .foregroundColor(TVColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 24) {
                    ForEach(releaseItems) { item in
                        versionCard(for: item)
                    }
                }
            }
        }
        .onAppear {
            loadNotes()
        }
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func loadNotes() {
        releaseItems = ReleaseNotesLoader.shared.loadReleaseNotes()
    }

    @ViewBuilder
    private func versionCard(for item: ReleaseNoteItem) -> some View {
        let isFocused = (focusedItemId == item.id)

        Button(action: {}) {
            VStack(alignment: .leading, spacing: 16) {
                // 卡片头部：版本号、发布日期与“最新”状态标签
                HStack(alignment: .center, spacing: 14) {
                    Text("v\(item.version)")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(TVColors.textPrimary)

                    if !item.date.isEmpty {
                        Text(item.date)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(TVColors.releaseDateText)
                    }

                    if item.isLatest {
                        Text("最新版本")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(TVColors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(TVColors.releaseLatestBadge)
                            )
                    }

                    Spacer()
                }

                Divider()
                    .background(TVColors.borderSubtle)

                // 具体的条目列表
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(item.items.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(item.isLatest ? TVColors.releaseTimelineDot : TVColors.textMuted)
                                .frame(width: 7, height: 7)
                                .padding(.top, 7)

                            Text(entry)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(TVColors.releaseBulletPoint)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isFocused ? TVColors.surfaceFocused : TVColors.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isFocused ? TVColors.focusedBorderColor : (item.isLatest ? TVColors.borderSelected : TVColors.borderSubtle),
                        lineWidth: isFocused ? 2.5 : (item.isLatest ? 1.5 : 1)
                    )
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .shadow(
                color: isFocused ? TVColors.focusedShadowColor : Color.clear,
                radius: isFocused ? 14 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($focusedItemId, equals: item.id)
    }
}

// MARK: - 预览
#Preview("Settings Release Notes Panel") {
    ZStack {
        TVColors.backgroundGradient
            .ignoresSafeArea()

        ScrollView {
            SettingsReleaseNotesPanel()
                .padding(40)
        }
    }
}
