import SwiftUI
import Kingfisher

public struct PosterArtworkView: View {
    public let drama: Drama
    public var cornerRadius: CGFloat = 14

    // 根据剧名哈希动态生成丰富的电影级海报渐变配色
    private var posterGradients: [Color] {
        let hash = abs(drama.title.hashValue)
        let paletteIndex = hash % TVColors.coverGradients.count
        return TVColors.coverGradients[paletteIndex]
    }

    private var normalizedCoverURL: URL? {
        guard ProcessInfo.processInfo.environment["DISABLE_REMOTE_IMAGES"] != "1" else { return nil }
        var str = drama.cover.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        if str.hasPrefix("//") {
            str = "https:" + str
        }
        if let u = URL(string: str) {
            return u
        }
        if let encoded = str.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let u = URL(string: encoded) {
            return u
        }
        return nil
    }

    public init(drama: Drama, cornerRadius: CGFloat = 14) {
        self.drama = drama
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                fallbackArtwork
                    .frame(width: geo.size.width, height: geo.size.height)

                if let url = normalizedCoverURL {
                    KFImage(url)
                        .placeholder { fallbackArtwork }
                        .fade(duration: 0.25)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .aspectRatio(0.68, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    // 高品质艺术剧照占位海报
    private var fallbackArtwork: some View {
        ZStack {
            // 背景渐变与光晕
            LinearGradient(
                colors: posterGradients,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 背景微光装饰
            VStack {
                HStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 80, height: 80)
                        .blur(radius: 20)
                    Spacer()
                }
                Spacer()
            }

            // 剧集海报主体排版
            VStack(spacing: 8) {
                // 顶部胶片标志与标签
                HStack {
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("糖葫芦剧场")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    if !drama.category.isEmpty {
                        Text(drama.category)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                Spacer()

                // 中间大图标
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 42, weight: .light))
                    .foregroundColor(.white.opacity(0.35))
                    .shadow(color: .black.opacity(0.4), radius: 6)

                Spacer()

                // 底部立体剧名展示
                VStack(spacing: 4) {
                    Text(drama.title)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black, radius: 4, x: 0, y: 2)

                    if !drama.tags.isEmpty {
                        Text(drama.tags.joined(separator: " · "))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }
}
