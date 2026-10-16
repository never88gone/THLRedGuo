import SwiftUI
import Kingfisher

public struct PosterArtworkView: View {
    public let drama: Drama
    public var cornerRadius: CGFloat = 14

    // 根据剧名哈希动态生成丰富的电影级海报渐变配色
    private var posterGradients: [Color] {
        let hash = abs(drama.title.hashValue)
        let paletteIndex = hash % 6
        switch paletteIndex {
        case 0:
            return [Color(red: 0.6, green: 0.1, blue: 0.15), Color(red: 0.15, green: 0.05, blue: 0.08)] // 绯红暗夜
        case 1:
            return [Color(red: 0.15, green: 0.25, blue: 0.6), Color(red: 0.05, green: 0.08, blue: 0.2)] // 极光深蓝
        case 2:
            return [Color(red: 0.55, green: 0.2, blue: 0.55), Color(red: 0.12, green: 0.05, blue: 0.15)] // 霓虹紫魅
        case 3:
            return [Color(red: 0.7, green: 0.45, blue: 0.1), Color(red: 0.2, green: 0.12, blue: 0.05)] // 耀金流光
        case 4:
            return [Color(red: 0.1, green: 0.45, blue: 0.35), Color(red: 0.04, green: 0.15, blue: 0.1)] // 翡翠墨绿
        default:
            return [Color(red: 0.3, green: 0.35, blue: 0.45), Color(red: 0.08, green: 0.1, blue: 0.14)] // 钛灰曜石
        }
    }

    private var normalizedCoverURL: URL? {
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

public struct DramaCardView: View {
    public let drama: Drama
    public var isFocused: Bool = false
    public var watchProgress: Double? = nil
    public var progressText: String? = nil
    public var forceFocused: Bool = false
    public var onUpCommand: (() -> Void)? = nil
    public var onSelect: () -> Void

    public init(
        drama: Drama,
        isFocused: Bool = false,
        isExternalFocused: Bool? = nil,
        watchProgress: Double? = nil,
        progressText: String? = nil,
        forceFocused: Bool = false,
        onUpCommand: (() -> Void)? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.drama = drama
        self.isFocused = isExternalFocused ?? isFocused
        self.watchProgress = watchProgress
        self.progressText = progressText
        self.forceFocused = forceFocused
        self.onUpCommand = onUpCommand
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            DramaCardLabel(
                drama: drama,
                externalFocused: isFocused,
                watchProgress: watchProgress,
                progressText: progressText,
                forceFocused: forceFocused
            )
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            }
        }
    }
}

private struct DramaCardLabel: View {
    let drama: Drama
    let externalFocused: Bool
    let watchProgress: Double?
    let progressText: String?
    let forceFocused: Bool

    @Environment(\.isFocused) private var envIsFocused

    var effectiveFocused: Bool {
        externalFocused || forceFocused || envIsFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                // 高质感海报渲染
                PosterArtworkView(drama: drama, cornerRadius: 14)

                // VIP 徽章
                if drama.isVIP {
                    Text("VIP")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }

                // 底部集数/热度角标
                VStack {
                    Spacer()
                    HStack {
                        Text(drama.displaySubtitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Spacer()
                    }
                    .padding(8)
                }

                // 进度条指示
                if let progress = watchProgress, progress > 0 {
                    VStack {
                        Spacer()
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: TVTheme.primary))
                            .frame(height: 5)
                    }
                }
            }
            .tvFocusBorder(isFocused: effectiveFocused, cornerRadius: 14, scale: TVTheme.cardScale)

            // 剧集标题
            Text(drama.title)
                .font(.system(size: 16, weight: effectiveFocused ? .bold : .medium))
                .foregroundColor(effectiveFocused ? .white : Color.white.opacity(0.85))
                .lineLimit(1)
                .shadow(color: effectiveFocused ? Color.red.opacity(0.4) : Color.clear, radius: 4)

            if let pt = progressText {
                Text(pt)
                    .font(.caption2)
                    .foregroundColor(effectiveFocused ? TVTheme.primary.opacity(0.9) : TVTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .background(Color.clear)
    }
}
