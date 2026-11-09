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
    let scrollProxy: ScrollViewProxy
    let onFocus: (DetailFocus) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let detail = detail {
                HStack(spacing: 32) {
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

                    TVButton(
                        title: viewModel.followState == .none ? "追剧" : "已追剧",
                        icon: viewModel.followState == .none ? "bookmark" : "bookmark.fill",
                        isExternalFocused: focusedTarget == .favorite
                    ) {
                        viewModel.toggleFavorite()
                    }
                    .focused($focusedTarget, equals: .favorite)
                    .id("detail_favorite")
                    .accessibilityIdentifier("detail.favorite")
                    .accessibilityLabel(viewModel.followState == .none ? "追剧" : "已追剧(已收藏)")

                    TVAccountSocialButton(drama: viewModel.drama, episode: viewModel.lastWatchEntry?.episode ?? selectedEpisodeNumber)

                    if viewModel.followState != .none && !accountLibrary.loggedIn {
                        Menu {
                            ForEach([FollowState.wishlist, .watching, .watched, .updated]) { state in
                                Button(state.label) { viewModel.setFollowState(state) }
                            }
                            Divider()
                            Button(role: .destructive) {
                                viewModel.setFollowState(.none)
                            } label: {
                                Label("取消追剧", systemImage: "bookmark.slash")
                            }
                        } label: {
                            Label(viewModel.followState.label, systemImage: "list.bullet")
                        }
                        .focused($focusedTarget, equals: .followState)
                        .id("detail_follow_state")
                        .accessibilityIdentifier("detail.followState")
                    }

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
}
