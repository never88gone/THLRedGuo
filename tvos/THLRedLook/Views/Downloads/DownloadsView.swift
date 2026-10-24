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
                    HStack(spacing: 20) {
                        Text("下载与离线管理")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("共 \(viewModel.jobs.count) 个下载任务")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))

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
                        HStack(alignment: .top, spacing: 32) {
                            // 左侧：离线任务状态与引导
                            VStack(spacing: 22) {
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 68))
                                    .foregroundColor(.white.opacity(0.35))
                                Text("暂无缓存任务")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                                Text("可在剧集详情页选择「缓存全剧」或指定剧集，下载完成后即可在大屏端享受极致流畅的离线免网播放。")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 420)

                                TVButton(title: "去浏览短剧", icon: "sparkles", isProminent: true, isExternalFocused: isExploreFocused) {
                                    onRequestFocusTopNav?()
                                }
                                .focused($isExploreFocused)
                                .accessibilityIdentifier("downloads.explore")
                                .padding(.top, 8)
                                Spacer()
                            }
                            .padding(32)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )

                            // 右侧：大屏投屏与同网络设备互联
                            ScrollView(.vertical, showsIndicators: false) {
                                LanSyncView()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(.horizontal, 48)
                        .padding(.bottom, 36)
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

public struct LanSyncView: View {
    @ObservedObject var lanService: LanSyncService
    @State private var syncingDevice: LanDevice?
    @State private var syncNotice: String?

    public init(lanService: LanSyncService = .shared) {
        self.lanService = lanService
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("局域网互联与接续播放")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    Text("本机已开启 Bonjour 服务（_zgj-link._tcp），支持手机或电脑端推送大屏播放及追剧同步。")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
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
            .padding(.top, 8)

            // 手机推送大屏待命提示
            HStack(spacing: 16) {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 36))
                    .foregroundColor(TVTheme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("大屏投屏待命已就绪")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("在糖葫芦Haw手机端播放页面点击「投屏到电视」，画面将直接在本机无缝接续播放。")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            // 发现的设备列表
            VStack(alignment: .leading, spacing: 14) {
                Text("发现的同网络设备")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))

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
                                        .foregroundColor(.white)
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

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(isPresented: Binding(
            get: { syncNotice != nil },
            set: { if !$0 { syncNotice = nil } }
        )) {
            Alert(title: Text("同步成功"), message: Text(syncNotice ?? ""), dismissButton: .default(Text("好的")))
        }
    }
}
