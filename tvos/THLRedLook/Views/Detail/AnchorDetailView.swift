import SwiftUI

/// 主播页面主视图（查看短剧主播与关注主播）
public struct AnchorDetailView: View {
    @ObservedObject private var followStore = AnchorFollowStore.shared
    @Environment(\.dismiss) private var dismiss
    public let initialAnchor: Anchor
    public let relatedDrama: Drama?
    @State private var anchor: Anchor
    @State private var selectedDrama: Drama?

    public init(anchor: Anchor, relatedDrama: Drama? = nil) {
        self.initialAnchor = anchor
        self.relatedDrama = relatedDrama
        self._anchor = State(initialValue: anchor)
    }

    private var isFollowed: Bool {
        followStore.isFollowed(anchorId: anchor.id)
    }

    public var body: some View {
        ZStack {
            TVColors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // 顶部主播信息栏与关注按钮
                AnchorHeaderView(
                    anchor: anchor,
                    isFollowed: isFollowed,
                    onToggleFollow: {
                        Task {
                            await followStore.toggleFollow(anchor: anchor, drama: relatedDrama)
                        }
                    },
                    onBack: {
                        dismiss()
                    }
                )

                Divider()
                    .background(Color.white.opacity(0.12))
                    .padding(.horizontal, 60)

                // 主播参演作品网格
                AnchorDramaGridView(
                    dramas: anchor.dramas,
                    onSelectDrama: { drama in
                        selectedDrama = drama
                    }
                )
            }
        }
        .fullScreenCover(item: $selectedDrama) { drama in
            DramaDetailView(drama: drama)
        }
        .task {
            // 加载完整的主播详情与短剧列表
            let fullAnchor = await AnchorService.shared.fetchAnchorDetail(
                anchorId: initialAnchor.id,
                currentDrama: relatedDrama
            )
            self.anchor = fullAnchor
        }
        .onExitCommand {
            dismiss()
        }
    }
}

#Preview("AnchorDetailView") {
    AnchorDetailView(
        anchor: Anchor(
            id: "anchor_preview",
            name: "热播主播",
            intro: "主演多部破亿短剧，演技细腻生动。"
        )
    )
}
