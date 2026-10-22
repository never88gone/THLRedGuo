import SwiftUI

public struct DownloadsView: View {
    @StateObject private var viewModel = DownloadsViewModel()
    @State private var playingLocalJob: DownloadJob?
    public var onRequestFocusTopNav: (() -> Void)? = nil

    public init(onRequestFocusTopNav: (() -> Void)? = nil) {
        self.onRequestFocusTopNav = onRequestFocusTopNav
    }

    public var body: some View {
        ZStack {
            if viewModel.currentSource.isEmpty {
                TVSourceBlankStateView()
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 20) {
                        Text("下载与离线管理")
                            .font(.title2)
                            .bold()
                        Spacer()
                        Text("共 \(viewModel.jobs.count) 个下载任务")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !viewModel.jobs.isEmpty {
                            TVButton(title: "全部继续", icon: "play.fill") {
                                viewModel.resumeAll()
                            }
                            TVButton(title: "清空任务", icon: "trash") {
                                viewModel.clearAll()
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)

                    if viewModel.jobs.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary)
                            Text("暂无缓存任务，可在剧集详情页选择「缓存全剧」")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(viewModel.jobs) { job in
                                    HStack(spacing: 20) {
                                        PosterArtworkView(drama: job.drama, cornerRadius: 8)
                                            .frame(width: 60, height: 90)

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("\(job.drama.title) · \(job.episode.displayTitle)")
                                                .font(.headline)
                                            HStack(spacing: 12) {
                                                Text(job.stateLabel)
                                                    .font(.caption)
                                                    .foregroundColor(job.state == "failed" ? .red : .secondary)
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
                                                    .frame(width: 280)
                                            }

                                            if job.state == "failed" && !job.error.isEmpty {
                                                Text(job.error)
                                                    .font(.caption2)
                                                    .foregroundColor(.red.opacity(0.85))
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        // 动作按钮（预留上侧、右侧防裁切间距）
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
                                        .padding(.top, 4)
                                        .padding(.trailing, 6)
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 14)
                                    .tvPanelStyle(cornerRadius: 14)
                                }
                            }
                            .padding(.horizontal, 48)
                            .padding(.vertical, 16)
                        }
                        .clipShape(Rectangle().inset(by: -30))
                    }
                }
            }
        }
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
    }
}

public struct LanSyncView: View {
    @ObservedObject var lanService: LanSyncService
    @State private var syncingDevice: LanDevice?
    @State private var syncNotice: String?

    public init(lanService: LanSyncService = .shared) {
        self.lanService = lanService
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("局域网互联与接续播放")
                        .font(.title2)
                        .bold()
                    Text("本机已开启 Bonjour 服务（_zgj-link._tcp），支持手机或电脑端推送大屏播放及追剧同步。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if lanService.isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在扫描局域网设备...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 24)

            // 手机推送大屏待命提示
            HStack(spacing: 16) {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 36))
                    .foregroundColor(TVTheme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("大屏投屏待命已就绪")
                        .font(.headline)
                    Text("在糖葫芦Haw手机端播放页面点击「投屏到电视」，画面将直接在本机无缝接续播放。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(24)
            .tvPanelStyle()
            .padding(.horizontal, 48)

            // 发现的设备列表
            VStack(alignment: .leading, spacing: 14) {
                Text("发现的同网络设备")
                    .font(.headline)
                    .foregroundColor(.secondary)

                if lanService.discoveredDevices.isEmpty {
                    Text("暂未发现同网段运行的客户端设备")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(lanService.discoveredDevices) { device in
                            HStack(spacing: 16) {
                                Image(systemName: "iphone.and.arrow.forward")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.headline)
                                    Text("IP: \(device.host) · 端口: \(device.port) · 版本: \(device.version)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                TVButton(title: "同步追剧数据", icon: "arrow.triangle.2.circlepath") {
                                    Task {
                                        try? await lanService.syncWithDevice(device)
                                        syncNotice = "已成功与 \(device.name) 完成追剧与历史同步！"
                                    }
                                }
                            }
                            .padding(18)
                            .tvPanelStyle(cornerRadius: 14)
                        }
                    }
                }
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .alert(isPresented: Binding(
            get: { syncNotice != nil },
            set: { if !$0 { syncNotice = nil } }
        )) {
            Alert(title: Text("同步成功"), message: Text(syncNotice ?? ""), dismissButton: .default(Text("好的")))
        }
    }
}
