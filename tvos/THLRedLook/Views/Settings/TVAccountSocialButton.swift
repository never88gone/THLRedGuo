import SwiftUI

// MARK: - 账号社交互动按钮（点赞与创作者）
public struct TVAccountSocialButton: View {
    @ObservedObject private var account = HongguoAccountModel.shared
    let drama: Drama
    var episode = 1
    @State private var showing = false

    public init(drama: Drama, episode: Int = 1) {
        self.drama = drama
        self.episode = episode
    }

    public var body: some View {
        if account.loggedIn && drama.source == "hongguo" {
            Button {
                showing = true
            } label: {
                Label("点赞与关注", systemImage: "heart")
            }
            .accessibilityIdentifier("account.social.open")
            .sheet(isPresented: $showing) {
                TVAccountSocialSheet(drama: drama, episode: episode)
            }
        }
    }
}

#Preview("TVAccountSocialButton") {
    TVAccountSocialButton(drama: Drama(id: "test", title: "测试短剧"))
        .padding(50)
        .background(TVColors.background)
}
