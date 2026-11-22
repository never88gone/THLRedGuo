import SwiftUI

// MARK: - 账号社交面板（已废弃：点赞与关注职责已正交分离，剧集/视频为点赞，主播为关注）
public struct TVAccountSocialSheet: View {
    public let drama: Drama
    public var episode = 1

    public init(drama: Drama, episode: Int = 1) {
        self.drama = drama
        self.episode = episode
    }

    public var body: some View {
        EmptyView()
    }
}

#Preview {
    TVAccountSocialSheet(
        drama: Drama(id: "1", title: "测试", cover: "", episodes: 10, tags: [])
    )
}
