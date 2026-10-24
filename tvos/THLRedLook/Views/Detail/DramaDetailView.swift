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
    @State private var hasAppeared = false
    @State private var didLoadDetail = false
    @State private var playerDismissedAt = Date.distantPast
    @State private var returningEpisode: Int?
    @State private var selectedEpisodeNumber: Int = 1
    @State private var resumePosition: Double = 0
    @State private var isDescriptionExpanded: Bool = false
    @State private var showingDownloadSuccess: Bool = false
    @State private var appearAnimation: Bool = false
    private enum DetailFocus: Hashable {
        case play
        case favorite
        case followState
        case season(Int)
        case chunk(Int)
        case episode(Int)
    }
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
                        // 剧集头部资料区（无顶部多余返回按钮，直接由遥控器实体 Menu/Back 键退出；始终展示列表带来的封面与剧名）
                        HStack(alignment: .top, spacing: 40) {
                            // 封面海报：沉浸式电影级入场过渡动画（从列表小卡片尺度向上升腾展开）
                            PosterArtworkView(drama: currentDrama, cornerRadius: 16)
                                .frame(width: 220, height: 320)
                                .clipped()
                                .shadow(
                                    color: Color.black.opacity(appearAnimation ? 0.75 : 0.2),
                                    radius: appearAnimation ? 24 : 6,
                                    x: 0,
                                    y: appearAnimation ? 12 : 3
                                )
                                .scaleEffect(appearAnimation ? 1.0 : 0.72)
                                .offset(y: appearAnimation ? 0 : 36)
                                .animation(.spring(response: 0.52, dampingFraction: 0.75, blendDuration: 0.2), value: appearAnimation)

                            // 标题、标签、简介与动作（紧随封面海报自然错峰滑入）
                            VStack(alignment: .leading, spacing: 18) {
                                Text(currentDrama.title)
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white)

                                HStack(spacing: 12) {
                                    if !currentDrama.releaseLabel.isEmpty {
                                        Text(currentDrama.releaseLabel)
                                            .font(.subheadline)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.red.opacity(0.8))
                                            .clipShape(Capsule())
                                    }

                                    if !currentDrama.heat.isEmpty {
                                        Text("热度：\(currentDrama.heat)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    if !currentDrama.onlineDate.isEmpty {
                                        Text("上线：\(currentDrama.onlineDate)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                // 简介
                                if !currentDrama.description.isEmpty {
                                    Text(currentDrama.description)
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.85))
                                        .lineLimit(isDescriptionExpanded ? nil : 3)
                                        .onTapGesture {
                                            withAnimation {
                                                isDescriptionExpanded.toggle()
                                            }
                                        }
                                }

                                // 动作按钮行（加载完成后平滑淡入展示，加载中展示优雅进度条）
                                if let detail = viewModel.detail {
                                    HStack(spacing: 32) {
                                        // 播放按钮
                                        let resumeEp = viewModel.lastWatchEntry?.episode ?? selectedEpisodeNumber
                                        let resumePos = viewModel.lastWatchEntry?.position ?? 0
                                        let playTitle = viewModel.lastWatchEntry != nil ? "继续播放 第 \(resumeEp) 集" : "立即播放"

                                        TVButton(
                                            title: playTitle,
                                            icon: "play.fill",
                                            isProminent: true,
                                            isExternalFocused: focusedTarget == .play,
                                            onDownCommand: {
                                                if viewModel.seasonItems.count > 1 {
                                                    focus(.season(viewModel.seasonItems.firstIndex(where: { $0.isCurrent }) ?? 0), with: scrollProxy)
                                                } else if detail.episodeChunks.count > 1 {
                                                    focus(.chunk(viewModel.selectedChunkIndex), with: scrollProxy)
                                                } else if let first = detail.episodes.first {
                                                    focus(.episode(first.number), with: scrollProxy)
                                                }
                                            }
                                        ) {
                                            selectedEpisodeNumber = resumeEp
                                            resumePosition = resumePos
                                            playingEpisodeIndex = resumeEp
                                        }
                                        .focused($focusedTarget, equals: .play)
                                        .id("detail_play")
                                        .accessibilityIdentifier("detail.play")

                                        // 追剧按钮
                                        TVButton(
                                            title: viewModel.followState == .none ? "收藏" : "已收藏",
                                            icon: viewModel.followState == .none ? "bookmark" : "bookmark.fill",
                                            isExternalFocused: focusedTarget == .favorite
                                        ) {
                                            viewModel.toggleFavorite()
                                        }
                                        .focused($focusedTarget, equals: .favorite)
                                        .id("detail_favorite")
                                        .accessibilityIdentifier("detail.favorite")

                                        if viewModel.followState != .none {
                                            Menu {
                                                ForEach([FollowState.wishlist, .watching, .watched, .updated]) { state in
                                                    Button(state.label) { viewModel.setFollowState(state) }
                                                }
                                            } label: {
                                                Label(viewModel.followState.label, systemImage: "list.bullet")
                                            }
                                            .focused($focusedTarget, equals: .followState)
                                            .id("detail_follow_state")
                                            .accessibilityIdentifier("detail.followState")
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
                                } else if viewModel.isLoading {
                                    HStack(spacing: 16) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(1.2)
                                        Text("正在载入剧集选集与播放源...")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                    .padding(.top, 16)
                                    .padding(.leading, 6)
                                } else if let error = viewModel.errorMessage {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Text("剧集详情加载出错：\(error)")
                                            .font(.system(size: 18))
                                            .foregroundColor(Color.red.opacity(0.9))
                                        TVButton(title: "重试加载", icon: "arrow.clockwise", isProminent: true) {
                                            Task { await viewModel.loadDetail() }
                                        }
                                    }
                                    .padding(.top, 16)
                                    .padding(.leading, 6)
                                }
                            }
                            .offset(x: appearAnimation ? 0 : 28)
                            .opacity(appearAnimation ? 1.0 : 0.0)
                            .animation(.easeOut(duration: 0.45).delay(0.08), value: appearAnimation)
                        }
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

                                // 当前组内的集数列表网格（采用 8 列并预留上、左、右安全间距）
                                if !detail.episodeChunks.isEmpty && viewModel.selectedChunkIndex < detail.episodeChunks.count {
                                    let currentChunk = detail.episodeChunks[viewModel.selectedChunkIndex]
                                    let rows = stride(from: 0, to: currentChunk.episodes.count, by: 8).map { start in
                                        Array(currentChunk.episodes[start..<min(start + 8, currentChunk.episodes.count)])
                                    }
                                    VStack(spacing: 24) {
                                        ForEach(Array(rows.enumerated()), id: \.offset) { _, episodes in
                                            HStack(spacing: 24) {
                                                ForEach(episodes) { ep in
                                                    let isCurrentEp = (ep.number == selectedEpisodeNumber) || (viewModel.lastWatchEntry?.episode == ep.number)
                                                    TVEpisodeButton(
                                                        episode: ep,
                                                        isCurrent: isCurrentEp,
                                                        isExternalFocused: focusedTarget == .episode(ep.number),
                                                        onUpCommand: {
                                                            let firstEpNum = currentChunk.episodes.first?.number ?? 1
                                                            let offset = ep.number - firstEpNum
                                                            if offset < 8 {

                                                                if detail.episodeChunks.count > 1 {
                                                                    focus(.chunk(viewModel.selectedChunkIndex), with: scrollProxy)
                                                                } else if viewModel.seasonItems.count > 1 {
                                                                    focus(.season(viewModel.seasonItems.firstIndex(where: { $0.isCurrent }) ?? 0), with: scrollProxy)
                                                                } else {
                                                                    focus(.play, with: scrollProxy)
                                                                }
                                                            }
                                                        }
                                                    ) {
                                                        selectedEpisodeNumber = ep.number
                                                        resumePosition = (viewModel.lastWatchEntry?.episode == ep.number) ? (viewModel.lastWatchEntry?.position ?? 0) : 0
                                                        playingEpisodeIndex = ep.number
                                                    }
                                                    .focused($focusedTarget, equals: .episode(ep.number))
                                                    .id("detail_episode_\(ep.number)")
                                                    .accessibilityIdentifier("detail.episode.\(ep.number)")
                                                    .frame(maxWidth: .infinity)
                                                }
                                                if episodes.count < 8 {
                                                    ForEach(episodes.count..<8, id: \.self) { _ in
                                                        Color.clear.frame(maxWidth: .infinity)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 12)
                                    .padding(.horizontal, 8)
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
        case .followState: identifier = "detail_follow_state"
        case .season(let index): identifier = "season_card_\(index)"
        case .chunk(let index): identifier = "detail_chunk_\(index)"
        case .episode(let number): identifier = "detail_episode_\(number)"
        }
        focusedTarget = nil
        proxy.scrollTo(identifier, anchor: .center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focusedTarget = target }
    }

}

/// 紧凑型季度选择卡片（横向排布，无标题，含小海报与明确当前季高亮徽章）
public struct TVSeasonCapsuleCard: View {
    public let item: SeasonItem
    public var isExternalFocused: Bool = false
    public var onUpCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public let action: () -> Void

    public init(
        item: SeasonItem,
        isExternalFocused: Bool = false,
        onUpCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.isExternalFocused = isExternalFocused
        self.onUpCommand = onUpCommand
        self.onDownCommand = onDownCommand
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TVSeasonCapsuleCardLabel(
                item: item,
                externalFocused: isExternalFocused
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            }
        }
    }
}

private struct TVSeasonCapsuleCardLabel: View {
    let item: SeasonItem
    let externalFocused: Bool

    @Environment(\.isFocused) private var envIsFocused

    var isFocused: Bool {
        externalFocused || envIsFocused
    }

    var body: some View {
        HStack(spacing: 12) {
            // 小海报缩略图（36x50，圆角 6，内含 PosterArtworkView）
            PosterArtworkView(drama: item.drama, cornerRadius: 6)
                .frame(width: 36, height: 50)
                .clipped()
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isFocused ? (item.isCurrent ? Color.white : TVTheme.focusedBorderColor) : Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: isFocused ? 19 : 18, weight: .bold))
                    .foregroundColor(titleColor)

                if item.isCurrent {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isFocused ? Color.white : Color.red)
                            .frame(width: 6, height: 6)
                        Text("当前播放")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(isFocused ? Color.white : Color(red: 1.0, green: 0.35, blue: 0.45))
                    }
                } else {
                    Text(item.drama.releaseLabel)
                        .font(.system(size: 13, weight: isFocused ? .semibold : .regular))
                        .foregroundColor(subTitleColor)
                }
            }
            .padding(.trailing, 10)
        }
        .padding(.horizontal, isFocused ? 12 : 10)
        .padding(.vertical, isFocused ? 8 : 6)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderStrokeColor, lineWidth: borderWidth)
        )
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .shadow(color: shadowColor, radius: shadowRadius, y: isFocused ? 4 : 0)
        .animation(TVTheme.focusSpringAnimation, value: isFocused)
    }

    private var titleColor: Color {
        if isFocused {
            return item.isCurrent ? .white : .black
        }
        return .white
    }

    private var subTitleColor: Color {
        if isFocused {
            return item.isCurrent ? .white.opacity(0.9) : Color.black.opacity(0.75)
        }
        return Color.white.opacity(0.65)
    }

    private var borderStrokeColor: Color {
        if isFocused {
            return item.isCurrent ? Color.white : TVTheme.focusedBorderColor
        }
        if item.isCurrent {
            return Color.red.opacity(0.85)
        }
        return Color.white.opacity(0.12)
    }

    private var borderWidth: CGFloat {
        if isFocused {
            return 3.0
        }
        if item.isCurrent {
            return 2.0
        }
        return 1.0
    }

    private var shadowColor: Color {
        if isFocused {
            return item.isCurrent ? Color.red.opacity(0.85) : TVTheme.focusedShadowColor
        }
        if item.isCurrent {
            return Color.red.opacity(0.4)
        }
        return Color.clear
    }

    private var shadowRadius: CGFloat {
        if isFocused {
            return 16.0
        }
        if item.isCurrent {
            return 8.0
        }
        return 0
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            if item.isCurrent {
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.12, blue: 0.22), Color(red: 1.0, green: 0.35, blue: 0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(white: 0.95)
            }
        } else {
            if item.isCurrent {
                Color.red.opacity(0.25)
            } else {
                TVTheme.surfaceCard
            }
        }
    }
}
