import SwiftUI

/// 播放器选集列表横向卡片面板（对应 ATV-Bilibili-demo 选集/博主视频流）
public struct TVPlayerEpisodesPanel: View {
    @ObservedObject public var viewModel: PlayerViewModel
    @FocusState private var focusedEpisodeIndex: Int?

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(viewModel.allEpisodes, id: \.number) { ep in
                        episodeButton(for: ep)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 12)
            }
            .frame(height: 120)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(viewModel.currentEpisodeIndex, anchor: .center)
                }
            }
        }
    }

    private func episodeButton(for ep: Episode) -> some View {
        let isPlayingCurrent = ep.number == viewModel.currentEpisodeIndex
        return Button(action: {
            Task {
                await viewModel.selectEpisode(number: ep.number)
            }
        }) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    if isPlayingCurrent {
                        Image(systemName: "waveform")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(TVColors.white)
                    }
                    Text("第 \(ep.number) 集")
                        .font(.system(size: 24, weight: isPlayingCurrent ? .bold : .medium))
                        .foregroundColor(TVColors.white)
                }

                if !ep.title.isEmpty, ep.title != "第\(ep.number)集" {
                    Text(ep.title)
                        .font(.system(size: 16))
                        .foregroundColor(TVColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 180, height: 96)
            .background(
                isPlayingCurrent ? AnyView(TVColors.episodeActiveGradient) : AnyView(TVColors.panelCardBg)
            )
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        focusedEpisodeIndex == ep.number
                            ? TVColors.liquidGlassActiveBorder
                            : TVColors.liquidGlassBorder,
                        lineWidth: focusedEpisodeIndex == ep.number ? 3 : 1
                    )
            )
            .scaleEffect(focusedEpisodeIndex == ep.number ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focusedEpisodeIndex)
        }
        .buttonStyle(.card)
        .focused($focusedEpisodeIndex, equals: ep.number)
        .id(ep.number)
    }
}

// MARK: - 预览
#Preview("TVPlayerEpisodesPanel") {
    struct PreviewContainer: View {
        var body: some View {
            let drama = Drama(id: "preview_1", title: "千金归来之真假名媛", cover: "", episodes: 30)
            let eps = (1...30).map { Episode(id: "\($0)", title: "第\($0)集", number: $0) }
            let vm = PlayerViewModel(drama: drama, allEpisodes: eps, initialEpisodeIndex: 5)
            TVPlayerEpisodesPanel(viewModel: vm)
                .padding(.vertical, 40)
                .background(TVColors.transportBarBg)
        }
    }
    return PreviewContainer()
}
