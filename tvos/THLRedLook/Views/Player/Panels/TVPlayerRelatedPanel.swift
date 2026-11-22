import SwiftUI

/// 播放器相关短剧横向推荐面板（对应 ATV-Bilibili-demo 相关视频流）
public struct TVPlayerRelatedPanel: View {
    @ObservedObject public var viewModel: PlayerViewModel
    @FocusState private var focusedDramaId: String?

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if viewModel.relatedSeasons.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: TVColors.white))
                    Text("正在发现相关推荐短剧...")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(TVColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 20) {
                        ForEach(viewModel.relatedSeasons, id: \.id) { item in
                            relatedDramaButton(item: item)
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 12)
                }
                .frame(height: 200)
            }
        }
    }

    private func relatedDramaButton(item: Drama) -> some View {
        Button(action: {
            viewModel.switchSeasonDrama = item
        }) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    coverImageView(for: item)
                        .frame(width: 240, height: 135)
                        .clipped()
                        .cornerRadius(16)

                    LinearGradient(
                        colors: [TVColors.clear, TVColors.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 50)
                    .cornerRadius(16)

                    if item.episodes > 0 {
                        Text("全 \(item.episodes) 集")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(TVColors.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(TVColors.black.opacity(0.65))
                            .cornerRadius(6)
                            .padding(8)
                    }
                }

                Text(item.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(TVColors.white)
                    .lineLimit(1)
                    .frame(width: 240, alignment: .leading)
            }
            .padding(8)
            .background(TVColors.panelCardBg)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        focusedDramaId == item.id
                            ? TVColors.liquidGlassActiveBorder
                            : TVColors.liquidGlassBorder,
                        lineWidth: focusedDramaId == item.id ? 3 : 1
                    )
            )
            .scaleEffect(focusedDramaId == item.id ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focusedDramaId)
        }
        .buttonStyle(.card)
        .focused($focusedDramaId, equals: item.id)
    }

    @ViewBuilder
    private func coverImageView(for item: Drama) -> some View {
        if !item.cover.isEmpty {
            AsyncImage(url: URL(string: item.cover)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholderGradient(for: item.id)
                }
            }
        } else {
            placeholderGradient(for: item.id)
        }
    }

    private func placeholderGradient(for id: String) -> some View {
        let index = abs(id.hashValue) % TVColors.coverGradients.count
        let colors = TVColors.coverGradients[index]
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 预览
#Preview("TVPlayerRelatedPanel") {
    struct PreviewContainer: View {
        var body: some View {
            let drama = Drama(id: "preview_1", title: "主剧：逆天龙皇", cover: "", episodes: 80)
            let related = [
                Drama(id: "rel_1", title: "战神归来当赘婿", cover: "", episodes: 80),
                Drama(id: "rel_2", title: "我有九个绝色师姐", cover: "", episodes: 95),
                Drama(id: "rel_3", title: "重返1990当首富", cover: "", episodes: 100)
            ]
            let vm = PlayerViewModel(drama: drama, allEpisodes: [])
            vm.relatedSeasons = related
            return TVPlayerRelatedPanel(viewModel: vm)
                .padding(.vertical, 40)
                .background(TVColors.transportBarBg)
        }
    }
    return PreviewContainer()
}
