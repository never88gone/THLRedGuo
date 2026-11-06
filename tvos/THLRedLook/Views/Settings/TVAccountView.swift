import SwiftUI

// MARK: - 电视端账号管理入口视图
public struct TVAccountView: View {
    @ObservedObject private var accountModel = HongguoAccountModel.shared
    @State private var showingLoginSheet = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(accountModel.loggedIn ? TVColors.activeRed : TVColors.textMuted)

                VStack(alignment: .leading, spacing: 4) {
                    Text(accountModel.loggedIn ? (accountModel.account?.nickname.isEmpty == false ? accountModel.account!.nickname : "红果用户") : "未登录红果账号")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(TVColors.textPrimary)
                    Text(accountModel.loggedIn ? "已连接红果账号，追剧与历史双向同步" : "登录后可同步手机书架、观看历史与播放进度")
                        .font(.system(size: 15))
                        .foregroundColor(TVColors.textSecondary)
                }
                Spacer()

                Button(accountModel.loggedIn ? "切换账号" : "扫码登录") {
                    showingLoginSheet = true
                }
                .buttonStyle(TvButtonStyle(variant: .primary))
            }
            .padding(24)
            .background(TVColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .sheet(isPresented: $showingLoginSheet) {
            TVLoginOptionsView()
        }
    }
}

#Preview("TVAccountView") {
    TVAccountView()
        .padding(50)
        .background(TVColors.background)
}
