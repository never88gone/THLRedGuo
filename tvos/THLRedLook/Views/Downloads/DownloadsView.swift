import SwiftUI

public struct DownloadsView: View {
    @StateObject private var viewModel = DownloadsViewModel()
    @State private var playingLocalJob: DownloadJob?
    public var focusTrigger: Int = 0
    public var onRequestFocusTopNav: (() -> Void)? = nil
    @FocusState private var isExploreFocused: Bool

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
                    // 顶部标题与批量控制栏
                    HStack(alignment: .center, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("下载与离线管理")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.white)
                            Text("管理本地存储的高清短剧切片，无网络环境下依然畅享大屏极致流畅播放。")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                        }

                        Spacer()

                        Text("共 \(viewModel.jobs.count) 个离线任务")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())

                        if !viewModel.jobs.isEmpty {
                            TVButton(title: "全部继续", icon: "play.fill", isProminent: false) {
                                viewModel.resumeAll()
                            }
                            TVButton(title: "清空任务", icon: "trash", isProminent: false) {
                                viewModel.clearAll()
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 28)

                    if viewModel.jobs.isEmpty {
                        // 全屏沉浸式空状态卡片（无任何局域网投屏残留）
                        VStack(spacing: 24) {
                            Spacer()

                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.05))
                                    .frame(width: 140, height: 140)
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 72))
                                    .foregroundColor(.white.opacity(0.4))
                            }

                            Text("暂无离线缓存短剧")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)

                            Text("在剧集详情页面中选择「缓存全剧」或指定剧集，即可下载至电视本地存储。\n离线切片独立保存在本地沙盒，无需网络随时打开畅看。")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.6))
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
                                .fill(Color(red: 0.10, green: 0.10, blue: 0.14).opacity(0.7))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .padding(.horizontal, 48)
                        .padding(.bottom, 36)
                    } else {
                        // 离线任务列表（全宽展示）
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(viewModel.jobs) { job in
                                    HStack(spacing: 20) {
                                        PosterArtworkView(drama: job.drama, cornerRadius: 8)
                                            .frame(width: 64, height: 96)

                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("\(job.drama.title) · \(job.episode.displayTitle)")
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.white)

                                            HStack(spacing: 14) {
                                                Text(job.stateLabel)
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(job.state == "failed" ? .red : (job.isCompleted ? .green : .secondary))
                                                if job.bytes > 0 {
                                                    let mbDone = String(format: "%.1f", Double(job.bytes) / 1024 / 1024)
                                                    let mbTotal = job.total > 0 ? String(format: "%.1f MB", Double(job.total) / 1024 / 1024) : "--"
                                                    Text("\(mbDone) MB / \(mbTotal)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }

                                            if job.isActive {
                                                ProgressView(value: job.progress)
                                                    .progressViewStyle(LinearProgressViewStyle(tint: .red))
                                                    .frame(width: 320)
                                            }

                                            if job.state == "failed" && !job.error.isEmpty {
                                                Text(job.error)
                                                    .font(.caption2)
                                                    .foregroundColor(.red.opacity(0.85))
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        HStack(spacing: 20) {
                                            if job.isCompleted {
                                                TVButton(title: "播放", icon: "play.fill", isProminent: true) {
                                                    playingLocalJob = job
                                                }
                                            } else if job.state == "downloading" {
                                                TVButton(title: "暂停", icon: "pause.fill") {
                                                    viewModel.pauseJob(job.id)
                                                }
                                            } else {
                                                TVButton(title: "继续", icon: "play.fill") {
                                                    viewModel.resumeJob(job.id)
                                                }
                                            }

                                            TVButton(title: "删除", icon: "trash") {
                                                viewModel.deleteJob(job.id)
                                            }
                                        }
                                        .padding(.trailing, 6)
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 16)
                                    .tvPanelStyle(cornerRadius: 16)
                                }
                            }
                            .padding(.horizontal, 48)
                            .padding(.vertical, 16)
                        }
                        .clipShape(Rectangle().inset(by: -30))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(item: $playingLocalJob) { job in
            TVPlayerView(
                drama: job.drama,
                episodes: [job.episode],
                initialEpisodeIndex: job.episode.number,
                initialPosition: 0
            )
        }
        .onExitCommand {
            if playingLocalJob == nil {
                onRequestFocusTopNav?()
            }
        }
        .onChange(of: focusTrigger) { _, _ in
            if viewModel.jobs.isEmpty {
                DispatchQueue.main.async {
                    isExploreFocused = true
                }
            }
        }
    }
}
