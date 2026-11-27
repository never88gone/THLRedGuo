import SwiftUI

public struct DramaDetailActionBar: View {
    @ObservedObject var viewModel: DetailViewModel
    @ObservedObject var accountLibrary: HongguoAccountModel
    let detail: DramaDetail?
    let appearAnimation: Bool
    @FocusState.Binding var focusedTarget: DetailFocus?
    @Binding var selectedEpisodeNumber: Int
    @Binding var resumePosition: Double
    @Binding var playingEpisodeIndex: Int?
    @Binding var showingDownloadSuccess: Bool
    var onShowAnchor: (() -> Void)? = nil
    let scrollProxy: ScrollViewProxy
    let onFocus: (DetailFocus) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let detail = detail {
                let isUpcoming = detail.episodes.isEmpty && (detail.drama.releaseStatus == "upcoming" || !detail.drama.onlineDate.isEmpty)
                HStack(spacing: 32) {
                    if isUpcoming {
                        let subscribed = accountLibrary.socialState(detail.drama)?.onlineSubscribed ?? false
                        TVButton(
                            title: viewModel.isReserving ? "处理中..." : (subscribed ? "已预约（点击取消）" : "立即预约"),
                            icon: subscribed ? "bell.fill" : "bell",
                            isProminent: !subscribed,
                            isExternalFocused: focusedTarget == .reserve,
                            onDownCommand: {
                                if viewModel.seasonItems.count > 1 {
                                    onFocus(.season(viewModel.seasonItems.firstIndex(where: { $0.isCurrent }) ?? 0))
                                }
                            }
                        ) {
                            viewModel.toggleReserve()
                        }
                        .focused($focusedTarget, equals: .reserve)
                        .id("detail_reserve")
                        .accessibilityIdentifier("detail.reserve")
                    } else {
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
                                    onFocus(.season(viewModel.seasonItems.firstIndex(where: { $0.isCurrent }) ?? 0))
                                } else if detail.episodeChunks.count > 1 {
                                    onFocus(.chunk(viewModel.selectedChunkIndex))
                                } else if let first = detail.episodes.first {
                                    onFocus(.episode(first.number))
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

                        if accountLibrary.loggedIn {
                            let isLiked = viewModel.followState != .none
                            TVButton(
                                title: isLiked ? "已点赞" : "点赞",
                                icon: isLiked ? "heart.fill" : "heart",
                                isExternalFocused: focusedTarget == .favorite
                            ) {
                                viewModel.toggleFavorite()
                            }
                            .focused($focusedTarget, equals: .favorite)
                            .id("detail_favorite")
                            .accessibilityIdentifier("detail.favorite")
                            .accessibilityLabel(isLiked ? "已点赞" : "点赞")
                        }
                    }

                    TVButton(
                        title: "主播",
                        icon: "person.crop.circle",
                        isExternalFocused: focusedTarget == .anchor,
                        onDownCommand: {
                            if viewModel.seasonItems.count > 1 {
                                onFocus(.season(viewModel.seasonItems.firstIndex(where: { $0.isCurrent }) ?? 0))
                            } else if detail.episodeChunks.count > 1 {
                                onFocus(.chunk(viewModel.selectedChunkIndex))
                            } else if let first = detail.episodes.first {
                                onFocus(.episode(first.number))
                            }
                        }
                    ) {
                        onShowAnchor?()
                    }
                    .focused($focusedTarget, equals: .anchor)
                    .id("detail_anchor")
                    .accessibilityIdentifier("detail.anchor")

                    if !isUpcoming {
                        TVButton(
                            title: "缓存全剧",
                            icon: "arrow.down.circle",
                            isExternalFocused: focusedTarget == .download,
                            onDownCommand: {
                                if viewModel.seasonItems.count > 1 {
                                    onFocus(.season(viewModel.seasonItems.firstIndex(where: { $0.isCurrent }) ?? 0))
                                } else if detail.episodeChunks.count > 1 {
                                    onFocus(.chunk(viewModel.selectedChunkIndex))
                                } else if let firstEp = detail.episodes.first {
                                    onFocus(.episode(firstEp.number))
                                }
                            }
                        ) {
                            viewModel.downloadAllEpisodes()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showingDownloadSuccess = true
                            }
                        }
                        .focused($focusedTarget, equals: .download)
                        .id("detail_download")
                        .accessibilityIdentifier("detail.download")
                    }
                }
                .padding(.top, 16)
                .padding(.leading, 6)
                .padding(.trailing, 16)
            } else if viewModel.isLoading {
                HStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: TVColors.white))
                        .scaleEffect(1.2)
                    Text("正在载入剧集选集与播放源...")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(TVColors.white.opacity(0.85))
                }
                .padding(.top, 16)
                .padding(.leading, 6)
            } else if let error = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 14) {
                    Text("剧集详情加载出错：\(error)")
                        .font(.system(size: 18))
                        .foregroundColor(TVColors.red.opacity(0.9))
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
}

#Preview {
    struct PreviewWrapper: View {
        @FocusState var focus: DetailFocus?
        @State var ep = 1
        @State var pos: Double = 0
        @State var playing: Int? = nil
        @State var dl = false
        var body: some View {
            ScrollViewReader { proxy in
                DramaDetailActionBar(
                    viewModel: DetailViewModel(drama: Drama(id: "1", title: "测试", cover: "", episodes: 20, tags: [])),
                    accountLibrary: HongguoAccountModel.shared,
                    detail: nil,
                    appearAnimation: true,
                    focusedTarget: $focus,
                    selectedEpisodeNumber: $ep,
                    resumePosition: $pos,
                    playingEpisodeIndex: $playing,
                    showingDownloadSuccess: $dl,
                    scrollProxy: proxy,
                    onFocus: { _ in }
                )
            }
            .padding(40)
            .background(TVColors.background)
        }
    }
    return PreviewWrapper()
}
