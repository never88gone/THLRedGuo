import SwiftUI

struct DramaDetailInfoCard: View {
    let drama: Drama
    let appearAnimation: Bool
    @Binding var isDescriptionExpanded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            // 封面海报：沉浸式电影级入场过渡动画（从列表小卡片尺度向上升腾展开）
            PosterArtworkView(drama: drama, cornerRadius: 16)
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
                Text(drama.title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    if !drama.releaseLabel.isEmpty {
                        Text(drama.releaseLabel)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.8))
                            .clipShape(Capsule())
                    }

                    if !drama.heat.isEmpty {
                        Text("热度：\(drama.heat)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if !drama.onlineDate.isEmpty {
                        Text("上线：\(drama.onlineDate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // 简介
                if !drama.description.isEmpty {
                    Text(drama.description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(isDescriptionExpanded ? nil : 3)
                        .onTapGesture {
                            withAnimation {
                                isDescriptionExpanded.toggle()
                            }
                        }
                }
            }
        }
    }
}
