import SwiftUI
import Kingfisher



public struct EpisodeWrapper: Identifiable {
    public let id: Int
    public var index: Int { id }
    public init(index: Int) { self.id = index }
}

public struct DramaDetailView: View {
    @StateObject private var viewModel: DetailViewModel
    @Environment(\.presentationMode) var presentationMode

    @State private var playingEpisodeIndex: Int?
    @State private var selectedEpisodeNumber: Int = 1
    @State private var resumePosition: Double = 0
    @State private var isDescriptionExpanded: Bool = false
    @State private var showingDownloadSuccess: Bool = false
    @FocusState private var isPlayButtonFocused: Bool
    @FocusState private var focusedEpisode: Int?

    public init(drama: Drama) {
        _viewModel = StateObject(wrappedValue: DetailViewModel(drama: drama))
    }

    private var normalizedCoverURL: URL? {
        var str = viewModel.drama.cover.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        if str.hasPrefix("//") {
            str = "https:" + str
        }
        return URL(string: str)
    }

    public var body: some View {
        ZStack {
            // 背景沉浸式深邃氛围底色（受 GeometryReader 严格限制，杜绝图片撑大溢出）
            GeometryReader { geo in
                ZStack {
                    Color.black

                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.08, blue: 0.12), Color.black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    if let url = normalizedCoverURL {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 50)
                            .opacity(0.3)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
            .ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("正在载入剧集详情...")
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Text("加载出错：\(error)")
                    TVButton(title: "重试", isProminent: true) {
                        Task { await viewModel.loadDetail() }
                    }
                }
            } else if let detail = viewModel.detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        // 剧集头部资料区（无顶部多余返回按钮，直接由遥控器实体 Menu/Back 键退出）
                        HStack(alignment: .top, spacing: 40) {
                            // 海报视图（严格限定尺寸并剪裁，防止超大图撑爆布局）
                            PosterArtworkView(drama: detail.drama, cornerRadius: 16)
                                .frame(width: 220, height: 320)
                                .clipped()
                                .shadow(radius: 12)

                            // 标题、标签、简介与动作
                            VStack(alignment: .leading, spacing: 18) {
                                Text(detail.drama.title)
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white)

                                HStack(spacing: 12) {
                                    Text(detail.drama.releaseLabel)
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.8))
                                        .clipShape(Capsule())

                                    if !detail.drama.heat.isEmpty {
                                        Text("热度：\(detail.drama.heat)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    if !detail.drama.onlineDate.isEmpty {
                                        Text("上线：\(detail.drama.onlineDate)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                // 简介
                                Text(detail.drama.description)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(isDescriptionExpanded ? nil : 3)
                                    .onTapGesture {
                                        withAnimation {
                                            isDescriptionExpanded.toggle()
                                        }
                                    }

                                // 动作按钮行（预留上侧、左侧、右侧充足防裁切间距）
                                HStack(spacing: 32) {
                                    // 播放按钮
                                    let resumeEp = viewModel.lastWatchEntry?.episode ?? selectedEpisodeNumber
                                    let resumePos = viewModel.lastWatchEntry?.position ?? 0
                                    let playTitle = viewModel.lastWatchEntry != nil ? "继续播放 第 \(resumeEp) 集" : "立即播放"

                                    TVButton(title: playTitle, icon: "play.fill", isProminent: true) {
                                        selectedEpisodeNumber = resumeEp
                                        resumePosition = resumePos
                                        playingEpisodeIndex = resumeEp
                                    }
                                    .focused($isPlayButtonFocused)

                                    // 追剧按钮
                                    TVButton(
                                        title: viewModel.followState == .none ? "追剧" : viewModel.followState.label,
                                        icon: viewModel.followState == .none ? "bookmark" : "bookmark.fill"
                                    ) {
                                        viewModel.toggleFollowState()
                                    }

                                    // 下载按钮
                                    TVButton(title: "缓存全剧", icon: "arrow.down.circle") {
                                        viewModel.downloadAllEpisodes()
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            showingDownloadSuccess = true
                                        }
                                    }
                                }
                                .padding(.top, 16)
                                .padding(.leading, 6)
                                .padding(.trailing, 16)
                            }
                        }
                        .padding(.top, 16)

                        // 紧凑型季度选择行（若有多季才显示，绝不显示标题，包含小海报与明确季数标识，绝不挤压下方选集）
                        if viewModel.seasonItems.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 20) {
                                    ForEach(viewModel.seasonItems) { item in
                                        TVSeasonCapsuleCard(item: item) {
                                            if !item.isCurrent {
                                                Task {
                                                    await viewModel.switchToDrama(item.drama)
                                                    if let entry = viewModel.lastWatchEntry {
                                                        selectedEpisodeNumber = entry.episode
                                                    } else {
                                                        selectedEpisodeNumber = 1
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 6)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 4)

                        // 选集区
                        VStack(alignment: .leading, spacing: 24) {
                            Text("选集播放")
                                .font(.title2)
                                .bold()

                            // 分组 Tab (1-50, 51-100)（增加上侧、左侧、右侧间距，杜绝 ScrollView 截断）
                            if detail.episodeChunks.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 24) {
                                        ForEach(Array(detail.episodeChunks.enumerated()), id: \.offset) { index, chunk in
                                            TVCapsuleButton(
                                                title: chunk.title,
                                                isSelected: viewModel.selectedChunkIndex == index,
                                                onDownCommand: {
                                                    if !detail.episodeChunks.isEmpty && viewModel.selectedChunkIndex < detail.episodeChunks.count {
                                                        let currentChunk = detail.episodeChunks[viewModel.selectedChunkIndex]
                                                        if let firstEp = currentChunk.episodes.first {
                                                            focusedEpisode = firstEp.number
                                                        }
                                                    }
                                                }
                                            ) {
                                                viewModel.selectedChunkIndex = index
                                            }
                                        }
                                    }
                                    .padding(.top, 14)
                                    .padding(.bottom, 14)
                                    .padding(.leading, 12)
                                    .padding(.trailing, 24)
                                }
                            }

                            // 当前组内的集数列表网格（采用 8 列并预留上、左、右安全间距）
                            if !detail.episodeChunks.isEmpty && viewModel.selectedChunkIndex < detail.episodeChunks.count {
                                let currentChunk = detail.episodeChunks[viewModel.selectedChunkIndex]
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 8), spacing: 24) {
                                    ForEach(currentChunk.episodes) { ep in
                                        let isCurrentEp = (ep.number == selectedEpisodeNumber) || (viewModel.lastWatchEntry?.episode == ep.number)
                                        TVEpisodeButton(
                                            episode: ep,
                                            isCurrent: isCurrentEp,
                                            isExternalFocused: focusedEpisode == ep.number,
                                            onUpCommand: {
                                                if let firstIndex = currentChunk.episodes.firstIndex(where: { $0.id == ep.id }), firstIndex < 8 {
                                                    focusedEpisode = nil
                                                    isPlayButtonFocused = true
                                                }
                                            }
                                        ) {
                                            selectedEpisodeNumber = ep.number
                                            resumePosition = (viewModel.lastWatchEntry?.episode == ep.number) ? (viewModel.lastWatchEntry?.position ?? 0) : 0
                                            playingEpisodeIndex = ep.number
                                        }
                                        .focused($focusedEpisode, equals: ep.number)
                                        .id("detail_episode_\(ep.number)")
                                    }
                                }
                                .padding(.top, 12)
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                }
                .defaultFocus($isPlayButtonFocused, true)
                .onAppear {
                    if let entry = viewModel.lastWatchEntry {
                        selectedEpisodeNumber = entry.episode
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isPlayButtonFocused = true
                    }
                }
            }
        }
        .task {
            await viewModel.loadDetail()
            if let entry = viewModel.lastWatchEntry {
                selectedEpisodeNumber = entry.episode
            }
        }
        .onChange(of: viewModel.lastWatchEntry?.episode) { newEp in
            if let ep = newEp {
                selectedEpisodeNumber = ep
            }
        }
        .fullScreenCover(item: Binding<EpisodeWrapper?>(
            get: { playingEpisodeIndex != nil ? EpisodeWrapper(index: playingEpisodeIndex!) : nil },
            set: { playingEpisodeIndex = $0?.index }
        )) { wrapper in
            if let detail = viewModel.detail {
                TVPlayerView(
                    drama: detail.drama,
                    episodes: detail.episodes,
                    initialEpisodeIndex: wrapper.index,
                    initialPosition: resumePosition,
                    onDismiss: {
                        playingEpisodeIndex = nil
                        viewModel.refreshWatchHistory()
                        if let entry = viewModel.lastWatchEntry {
                            selectedEpisodeNumber = entry.episode
                        }
                    },
                    onSwitchSeason: { newDrama in
                        playingEpisodeIndex = nil
                        Task {
                            await viewModel.switchToDrama(newDrama)
                            if let entry = viewModel.lastWatchEntry {
                                selectedEpisodeNumber = entry.episode
                            } else {
                                selectedEpisodeNumber = 1
                            }
                        }
                    }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if showingDownloadSuccess {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                    Text("全剧集已安排后台下载，您可在「下载」标签页查看。")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.95))
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                )
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation(.easeOut) {
                            showingDownloadSuccess = false
                        }
                    }
                }
            }
        }
        .onExitCommand {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

/// 紧凑型季度选择卡片（高度约 60，横向排布，无标题，含小海报与明确当前季高亮徽章）
public struct TVSeasonCapsuleCard: View {
    public let item: SeasonItem
    public let action: () -> Void

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 小海报缩略图（36x50，圆角 6，内含带协议与字符转义的 PosterArtworkView）
                PosterArtworkView(drama: item.drama, cornerRadius: 6)
                    .frame(width: 36, height: 50)
                    .clipped()

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    if item.isCurrent {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("当前播放")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.red.opacity(0.95))
                        }
                    } else {
                        Text(item.drama.releaseLabel)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.isCurrent ? Color.red.opacity(0.22) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(item.isCurrent ? Color.red.opacity(0.8) : Color.white.opacity(0.12), lineWidth: item.isCurrent ? 2 : 1)
            )
        }
        .buttonStyle(.card)
    }
}
