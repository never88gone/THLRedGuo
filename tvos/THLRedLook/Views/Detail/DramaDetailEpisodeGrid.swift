import SwiftUI

struct DramaDetailEpisodeGrid: View {
    let currentChunk: EpisodeChunk
    let selectedEpisodeNumber: Int
    let lastWatchEpisode: Int?
    @FocusState.Binding var focusedTarget: DetailFocus?
    let onUpFallback: (Episode) -> Void
    let onSelectEpisode: (Episode) -> Void

    var body: some View {
        let rows = stride(from: 0, to: currentChunk.episodes.count, by: 8).map { start in
            Array(currentChunk.episodes[start..<min(start + 8, currentChunk.episodes.count)])
        }
        VStack(spacing: 24) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, episodes in
                HStack(spacing: 24) {
                    ForEach(episodes) { ep in
                        let isCurrentEp = (ep.number == selectedEpisodeNumber) || (lastWatchEpisode == ep.number)
                        TVEpisodeButton(
                            episode: ep,
                            isCurrent: isCurrentEp,
                            isExternalFocused: focusedTarget == .episode(ep.number),
                            onUpCommand: {
                                let firstEpNum = currentChunk.episodes.first?.number ?? 1
                                let offset = ep.number - firstEpNum
                                if offset < 8 {
                                    onUpFallback(ep)
                                }
                            }
                        ) {
                            onSelectEpisode(ep)
                        }
                        .focused($focusedTarget, equals: .episode(ep.number))
                        .id("detail_episode_\(ep.number)")
                        .accessibilityIdentifier("detail.episode.\(ep.number)")
                        .frame(maxWidth: .infinity)
                    }
                    if episodes.count < 8 {
                        ForEach(episodes.count..<8, id: \.self) { _ in
                            TVColors.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @FocusState var focus: DetailFocus?
        var body: some View {
            DramaDetailEpisodeGrid(
                currentChunk: EpisodeChunk(
                    title: "1-10",
                    range: 0..<10,
                    episodes: (1...10).map { Episode(id: "\($0)", title: "第 \($0) 集", number: $0) }
                ),
                selectedEpisodeNumber: 1,
                lastWatchEpisode: 1,
                focusedTarget: $focus,
                onUpFallback: { _ in },
                onSelectEpisode: { _ in }
            )
            .padding(40)
            .background(TVColors.background)
        }
    }
    return PreviewWrapper()
}
