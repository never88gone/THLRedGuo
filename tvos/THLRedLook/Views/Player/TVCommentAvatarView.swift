import SwiftUI

// MARK: - 评论头像与通用格式化视图组件
struct TVCommentAvatarView: View {
    let url: String
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let validUrl = URL(string: url), !url.isEmpty {
                AsyncImage(url: validUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        ZStack {
            TVColors.white.opacity(0.18)
            Text(name.prefix(1))
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(TVColors.white)
        }
    }

    static func formatTimestamp(_ ts: Int) -> String {
        guard ts > 0 else { return "" }
        let ms = ts < 10_000_000_000 ? ts * 1000 : ts
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(diff / 60)分钟前" }
        if diff < 86400 { return "\(diff / 3600)小时前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func formatNumber(_ num: Int) -> String {
        guard num > 0 else { return "" }
        if num < 10000 { return "\(num)" }
        return String(format: "%.1f万", Double(num) / 10000.0)
    }
}

#Preview {
    TVCommentAvatarView(url: "", name: "红果用户", size: 48)
        .padding()
        .background(TVColors.background)
}
