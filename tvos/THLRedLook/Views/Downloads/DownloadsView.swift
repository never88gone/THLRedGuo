import SwiftUI

public struct DownloadsView: View {
    @StateObject private var viewModel = DownloadsViewModel()
    @State private var playingPayload: PlaybackPayload?
    public var focusTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)? = nil
    @FocusState private var isExploreFocused: Bool

    private let episodeColumns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 6)

    private struct PlaybackPayload: Identifiable {
        var id: String { "\(drama.id)_\(startEpisode.number)" }
        let drama: Drama
        let episodes: [Episode]
        let startEpisode: Episode
    }

    public init(focusTrigger: Int = 0, onRequestFocusTopNav: (() -> Void)? = nil) {
        self.focusTrigger = focusTrigger
        self.onRequestFocusTopNav = onRequestFocusTopNav
    }

    public var body: some View {
        ZStack {
            if viewModel.currentSource.isEmpty {
                TVSourceBlankStateView()
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    headerBar

                    if viewModel.jobs.isEmpty {
                        emptyStateView
                    } else {
                        dramaGroupList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(item: $playingPayload) { payload in
            TVPlayerView(
                drama: payload.drama,
                episodes: payload.episodes,
                initialEpisodeIndex: payload.startEpisode.number,
                initialPosition: 0
            )
        }
        .onExitCommand {
            if playingPayload == nil {
                onRequestFocusTopNav?()
            }
        }
        .onChange(of: focusTrigger) { _, _ in
            if viewModel.jobs.isEmpty {
                isExploreFocused = true
            }
        }
    }

    // MARK: - 顶部操作栏
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("下载与离线管理")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(TVColors.white)
                Text("管理本地存储的高清短剧切片，按剧集归类整理，无网络环境下依然畅享大屏极致流畅播放。")
                    .font(.system(size: 16))
                    .foregroundColor(TVColors.white.opacity(0.6))
            }

            Spacer()

            Text("共 \(viewModel.dramaGroups.count) 部短剧 · \(viewModel.jobs.count) 个分集")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(TVColors.white.opacity(0.65))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(TVColors.white.opacity(0.08))
                .clipShape(Capsule())

            if !viewModel.jobs.isEmpty {
                if viewModel.jobs.contains(where: { $0.isResumable }) {
                    TVButton(title: "全部继续", icon: "play.fill", isProminent: false) {
                        viewModel.resumeAll()
                    }
                    .accessibilityIdentifier("downloads.resumeAll")
                }

                TVButton(title: "清空全部", icon: "trash", isProminent: false) {
                    viewModel.clearAll()
                }
                .accessibilityIdentifier("downloads.clearAll")
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 28)
    }

    // MARK: - 空状态卡片
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(TVColors.white.opacity(0.05))
                    .frame(width: 140, height: 140)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 72))
                    .foregroundColor(TVColors.white.opacity(0.4))
            }

            Text("暂无离线缓存短剧")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(TVColors.white)

            Text("在剧集详情页面中选择「缓存全剧」或指定剧集，即可下载至电视本地存储。\n离线切片独立保存在本地沙盒，无需网络随时打开畅看。")
                .font(.system(size: 18))
                .foregroundColor(TVColors.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)
                .lineSpacing(6)

            TVButton(title: "去浏览短剧", icon: "sparkles", isProminent: true, isExternalFocused: isExploreFocused) {
                onRequestFocusTopNav?()
            }
            .focused($isExploreFocused)
            .accessibilityIdentifier("downloads.explore")
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(TVColors.downloadsCardBg.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(TVColors.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 48)
        .padding(.bottom, 36)
    }

    // MARK: - 按剧集分组展示的主列表
    private var dramaGroupList: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                ForEach(viewModel.dramaGroups) { group in
                    VStack(alignment: .leading, spacing: 20) {
                        // 剧集 Header 卡片
                        HStack(spacing: 20) {
                            PosterArtworkView(drama: group.drama, cornerRadius: 8)
                                .frame(width: 64, height: 96)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.drama.title)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(TVColors.white)
                                    .lineLimit(1)

                                HStack(spacing: 14) {
                                    Text(group.statusSummary)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(group.isAllCompleted ? TVColors.green : TVColors.white.opacity(0.7))
                                }
                            }

                            Spacer()

                            HStack(spacing: 16) {
                                if !group.completedJobs.isEmpty {
                                    TVButton(title: "播放", icon: "play.fill", isProminent: true) {
                                        playDrama(group, startEpisode: group.completedJobs.first?.episode)
                                    }
                                    .accessibilityIdentifier("downloads.drama.play.\(group.drama.id)")
                                }

                                if group.hasResumable {
                                    TVButton(title: "继续", icon: "play.fill") {
                                        viewModel.resumeDrama(group.drama.id)
                                    }
                                    .accessibilityIdentifier("downloads.drama.resume.\(group.drama.id)")
                                } else if group.hasActive {
                                    TVButton(title: "暂停", icon: "pause.fill") {
                                        viewModel.pauseDrama(group.drama.id)
                                    }
                                    .accessibilityIdentifier("downloads.drama.pause.\(group.drama.id)")
                                }

                                TVButton(title: "删除整剧", icon: "trash") {
                                    viewModel.deleteDrama(group.drama.id)
                                }
                                .accessibilityIdentifier("downloads.drama.delete.\(group.drama.id)")
                            }
                        }

                        Divider()
                            .background(TVColors.white.opacity(0.08))

                        // 分剧集网格（按剧集显示分集）
                        VStack(alignment: .leading, spacing: 12) {
                            Text("已缓存分集")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(TVColors.white.opacity(0.5))

                            LazyVGrid(columns: episodeColumns, spacing: 14) {
                                ForEach(group.jobs) { job in
                                    TVDownloadEpisodeButton(
                                        job: job,
                                        onSelect: {
                                            handleEpisodeAction(job: job, in: group)
                                        },
                                        onDelete: {
                                            viewModel.deleteJob(job.id)
                                        }
                                    )
                                    .accessibilityIdentifier("downloads.episode.\(job.id)")
                                }
                            }
                        }
                    }
                    .padding(24)
                    .tvPanelStyle(cornerRadius: 20)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 16)
        }
        .clipShape(Rectangle().inset(by: -30))
    }

    private func handleEpisodeAction(job: DownloadJob, in group: DramaDownloadGroup) {
        if job.isCompleted {
            playDrama(group, startEpisode: job.episode)
        } else if job.isActive {
            viewModel.pauseJob(job.id)
        } else {
            viewModel.resumeJob(job.id)
        }
    }

    private func playDrama(_ group: DramaDownloadGroup, startEpisode: Episode?) {
        let completed = group.completedJobs.map(\.episode)
        guard !completed.isEmpty else { return }
        let targetEpisode = startEpisode ?? completed.first!
        playingPayload = PlaybackPayload(
            drama: group.drama,
            episodes: completed,
            startEpisode: targetEpisode
        )
    }
}

#Preview {
    DownloadsView()
        .background(TVColors.background)
}
