import SwiftUI

public struct TVPictureInPictureCoordinatorPreviewView: View {
    @ObservedObject var coordinator = TVPictureInPictureCoordinator.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Text("画中画全局协调器预览")
                .font(.title2)
                .bold()
                .foregroundColor(TVColors.textPrimary)

            HStack(spacing: 16) {
                Text("硬件支持: \(coordinator.isPictureInPictureSupported ? "是" : "否")")
                Text("活跃状态: \(coordinator.isPictureInPictureActive ? "进行中" : "未激活")")
            }
            .font(.callout)
            .foregroundColor(TVColors.textSecondary)

            if let session = coordinator.currentSession {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前剧集: \(session.drama.title)")
                    Text("集数: 第 \(session.episodeIndex) 集")
                    Text("当前进度: \(Int(session.currentPosition)) 秒")
                }
                .padding()
                .background(TVColors.surfaceCard)
                .cornerRadius(12)
            }
        }
        .padding(40)
        .background(TVColors.background)
    }
}

#Preview {
    TVPictureInPictureCoordinatorPreviewView()
}
