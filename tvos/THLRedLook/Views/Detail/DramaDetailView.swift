import SwiftUI
import Kingfisher

public struct DramaDetailView: View {
    @ObservedObject private var accountLibrary = HongguoAccountModel.shared
    @StateObject private var viewModel: DetailViewModel
    @Environment(\.presentationMode) var presentationMode

    @State private var playingEpisodeIndex: Int?
    @State private var hasAppeared = false
    @State private var didLoadDetail = false
    @State private var playerDismissedAt = Date.distantPast
    @State private var returningEpisode: Int?
    @State private var selectedEpisodeNumber: Int = 1
    @State private var resumePosition: Double = 0
    @State private var isDescriptionExpanded: Bool = false
    @State private var showingDownloadSuccess: Bool = false
    @State private var appearAnimation: Bool = false
    @State private var showingAnchorDetail: Bool = false
    @State private var currentAnchor: Anchor? = nil
    @FocusState private var focusedTarget: DetailFocus?

    public var onDismiss: (() -> Void)? = nil

    public init(drama: Drama, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: DetailViewModel(drama: drama))
        self.onDismiss = onDismiss
    }

    private var currentDrama: Drama {
        viewModel.detail?.drama ?? viewModel.drama
    }

    private var normalizedCoverURL: URL? {
        guard ProcessInfo.processInfo.environment["DISABLE_REMOTE_IMAGES"] != "1" else { return nil }
        var str = currentDrama.cover.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        if str.hasPrefix("//") {
            str = "https:" + str
        }
        return URL(string: str)
    }

    public var body: some View {
        detailBody.onChange(of: accountLibrary.libraryVersion) { _, _ in viewModel.refreshWatchHistory() }.overlay(alignment: .top) {
            if let error = accountLibrary.libraryWriteError { Text(error).font(.system(size: 29)).foregroundStyle(.orange).padding(24).background(.black.opacity(0.8)) }
        }
    }

    private var detailBody: some View {
        ZStack {
            // 背景沉浸式深邃氛围底色（受 GeometryReader 严格限制，杜绝图片撑大溢出）
            GeometryReader { geo in
                ZStack {
                    Color.black

                    LinearGradient(
                        colors: [TVColors.detailTopGradient, Color.black],
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
                            .opacity(appearAnimation ? 0.35 : 0.0)
                            .animation(.easeOut(duration: 0.6), value: appearAnimation)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
            .ignoresSafeArea()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        // 剧集头部资料区
                        DramaDetailInfoCard(
                            drama: currentDrama,
                            appearAnimation: appearAnimation,
                            isDescriptionExpanded: $isDescriptionExpanded
                        )

                        DramaDetailActionBar(
                            viewModel: viewModel,
                            accountLibrary: accountLibrary,
                            detail: viewModel.detail,
                            appearAnimation: appearAnimation,
                            focusedTarget: $focusedTarget,
                            selectedEpisodeNumber: $selectedEpisodeNumber,
                            resumePosition: $resumePosition,
                            playingEpisodeIndex: $playingEpisodeIndex,
                            showingDownloadSuccess: $showingDownloadSuccess,
                            onShowAnchor: {
                                Task {
                                    let anchors = await AnchorService.shared.fetchAnchors(for: currentDrama)
                                    if let first = anchors.first {
                                        currentAnchor = first
                                        showingAnchorDetail = true
                                    }
                                }
                            },
                            scrollProxy: scrollProxy,
                            onFocus: { target in
                                focus(target, with: scrollProxy)
                            }
                        )
                        .padding(.top, 16)

                        if let detail = viewModel.detail {
                            // 紧凑型季度选择行（若有多季才显示，绝不显示标题，包含小海报与明确季数标识，绝不挤压下方选集）
                            if viewModel.seasonItems.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(Array(viewModel.seasonItems.enumerated()), id: \.element.id) { index, item in
                                            TVSeasonCapsuleCard(
                                                item: item,
                                                isExternalFocused: focusedTarget == .season(index),
                                                onUpCommand: {

                                                    focus(.play, with: scrollProxy)
                                                },
                                                onDownCommand: {

                                                    if detail.episodeChunks.count > 1 {
                                                        focus(.chunk(viewModel.selectedChunkIndex), with: scrollProxy)
                                                    } else if let firstEp = detail.episodes.first {
                                                        focus(.episode(firstEp.number), with: scrollProxy)
                                                    }
                                                }
                                            ) {
                                                if !item.isCurrent && item.playable {
                                                    Task {
                                                        focus(.season(index), with: scrollProxy)
                                                        await viewModel.switchToDrama(item.drama)
                                                        if let entry = viewModel.lastWatchEntry {
                                                            selectedEpisodeNumber = entry.episode
                                                        } else {
                                                            selectedEpisodeNumber = 1
                                                        }
                                                    }
                                                }
                                            }
                                            .focused($focusedTarget, equals: .season(index))
                                            .id("season_card_\(index)")
                                            .accessibilityIdentifier("detail.season.\(index)")
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 8)
                                }
                            }

                            Divider()
                                .padding(.vertical, 4)

                            // 选集区
                            VStack(alignment: .leading, spacing: 24) {
                                Text("选集播放")
                                    .font(.title2)
                                    .bold()

                                // 分组 Tab (1-50, 51-100)（增加上侧、左侧、右侧间距，保证焦点段完整激活）
                                if detail.episodeChunks.count > 1 {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 24) {
                                            ForEach(Array(detail.episodeChunks.enumerated()), id: \.offset) { index, chunk in
                                                TVCapsuleButton(
                                                    title: chunk.title,
                                                    isSelected: viewModel.selectedChunkIndex == index,
                                                    isExternalFocused: focusedTarget == .chunk(index),
                                                    onUpCommand: {

                                                        if viewModel.seasonItems.count > 1 {
                                                            focus(.season(viewModel.seasonItems.firstIndex(where: { $0.isCurrent }) ?? 0), with: scrollProxy)
                                                        } else {
                                                            focus(.play, with: scrollProxy)
                                                        }
                                                    },
                                                    onDownCommand: {

                                                        if !detail.episodeChunks.isEmpty && viewModel.selectedChunkIndex < detail.episodeChunks.count {
                                                            let currentChunk = detail.episodeChunks[viewModel.selectedChunkIndex]
                                                            if let firstEp = currentChunk.episodes.first {
                                                                focus(.episode(firstEp.number), with: scrollProxy)
                                                            }
                                                        }
                                                    }
                                                ) {
                                                    viewModel.selectedChunkIndex = index
                                                }
                                                .focused($focusedTarget, equals: .chunk(index))
                                                .id("detail_chunk_\(index)")
                                                .accessibilityIdentifier("detail.chunk.\(index)")
                                            }
                                        }
                                        .padding(.top, 14)
                                        .padding(.bottom, 14)
                                        .padding(.leading, 12)
                                        .padding(.trailing, 24)
                                    }
                                }

                                // 当前组内的集数列表网格
                                if !detail.episodeChunks.isEmpty && viewModel.selectedChunkIndex < detail.episodeChunks.count {
                                    let currentChunk = detail.episodeChunks[viewModel.selectedChunkIndex]
                                    DramaDetailEpisodeGrid(
                                        currentChunk: currentChunk,
                                        selectedEpisodeNumber: selectedEpisodeNumber,
                                        lastWatchEpisode: viewModel.lastWatchEntry?.episode,
                                        focusedTarget: $focusedTarget,
                                        onUpFallback: { ep in
                                            if detail.episodeChunks.count > 1 {
                                                focus(.chunk(viewModel.selectedChunkIndex), with: scrollProxy)
                                            } else if viewModel.seasonItems.count > 1 {
                                                focus(.season(viewModel.seasonItems.firstIndex(where: { $0.isCurrent }) ?? 0), with: scrollProxy)
                                            } else {
                                                focus(.play, with: scrollProxy)
                                            }
                                        },
                                        onSelectEpisode: { ep in
                                            selectedEpisodeNumber = ep.number
                                            resumePosition = (viewModel.lastWatchEntry?.episode == ep.number) ? (viewModel.lastWatchEntry?.position ?? 0) : 0
                                            playingEpisodeIndex = ep.number
                                        }
                                    )
                                }
                            }
                        } else if viewModel.isLoading {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("选集播放")
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(.white.opacity(0.85))

                                HStack(spacing: 16) {
                                    ForEach(1...8, id: \.self) { idx in
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.06))
                                            .frame(width: 86, height: 64)
                                            .overlay(
                                                Text("\(idx)")
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.2))
                                            )
                                    }
                                }
                                .padding(.top, 6)
                            }
                            .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                }
                .onChange(of: returningEpisode) { _, number in
                    guard let number else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        focus(.episode(number), with: scrollProxy)
                    }
                }
                .onChange(of: viewModel.detail != nil) { hasDetail in
                    if hasDetail {
                        withAnimation(.easeInOut(duration: 0.35)) {}
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            focus(.play, with: scrollProxy)
                        }
                    }
                }
                .defaultFocus($focusedTarget, .play)
                .onAppear {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.75)) {
                        appearAnimation = true
                    }
                    guard !hasAppeared else { return }
                    hasAppeared = true
                    if let entry = viewModel.lastWatchEntry {
                        selectedEpisodeNumber = entry.episode
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focus(.play, with: scrollProxy)
                    }
                }
            }
        }
        .task {
            guard !didLoadDetail else { return }
            didLoadDetail = true
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
        ), onDismiss: {
            viewModel.refreshWatchHistory()
            let number = viewModel.lastWatchEntry?.episode ?? selectedEpisodeNumber
            selectedEpisodeNumber = number
            if let detail = viewModel.detail,
               let chunk = detail.episodeChunks.firstIndex(where: { $0.episodes.contains(where: { $0.number == number }) }) {
                viewModel.selectedChunkIndex = chunk
            }
            returningEpisode = nil
            DispatchQueue.main.async { returningEpisode = number }
        }) { wrapper in
            if let detail = viewModel.detail {
                TVPlayerView(
                    drama: detail.drama,
                    episodes: detail.episodes,
                    initialEpisodeIndex: wrapper.index,
                    initialPosition: resumePosition,
                    onDismiss: {
                        playerDismissedAt = Date()
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
        .onReceive(TVPictureInPictureCoordinator.shared.$shouldRestoreFullScreen) { shouldRestore in
            guard shouldRestore, let session = TVPictureInPictureCoordinator.shared.currentSession else { return }
            if session.drama.id == viewModel.drama.id {
                NSLog("🎯 [DramaDetailView] 接管画中画恢复全屏: drama='%@', episode=%d", session.drama.title, session.episodeIndex)
                TVPictureInPictureCoordinator.shared.markRestoreHandled()
                self.selectedEpisodeNumber = session.episodeIndex
                self.resumePosition = session.currentPosition
                self.playingEpisodeIndex = session.episodeIndex
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
                        .fill(TVColors.detailCardBg.opacity(0.95))
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
        .fullScreenCover(isPresented: $showingAnchorDetail) {
            if let anchor = currentAnchor {
                AnchorDetailView(anchor: anchor, relatedDrama: currentDrama)
            }
        }
        .onExitCommand {
            guard playingEpisodeIndex == nil, Date().timeIntervalSince(playerDismissedAt) > 0.5 else { return }
            if let onDismiss = onDismiss {
                onDismiss()
            } else {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }

    private func focus(_ target: DetailFocus, with proxy: ScrollViewProxy) {
        let identifier: String
        switch target {
        case .play: identifier = "detail_play"
        case .favorite: identifier = "detail_favorite"
        case .anchor: identifier = "detail_anchor"
        case .followState: identifier = "detail_follow_state"
        case .download: identifier = "detail_download"
        case .season(let index): identifier = "season_card_\(index)"
        case .chunk(let index): identifier = "detail_chunk_\(index)"
        case .episode(let number): identifier = "detail_episode_\(number)"
        }
        focusedTarget = nil
        proxy.scrollTo(identifier, anchor: .center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focusedTarget = target }
    }
}
