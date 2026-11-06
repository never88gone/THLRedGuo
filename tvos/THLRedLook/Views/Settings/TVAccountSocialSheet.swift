import SwiftUI

// MARK: - 账号社交与创作者面板
public struct TVAccountSocialSheet: View {
    private enum Target: Hashable {
        case like, creator(String), refresh, close
    }
    @ObservedObject private var model = HongguoAccountModel.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Target?
    public let drama: Drama
    public var episode = 1
    @State private var error: String?
    @State private var loading = false
    @State private var didLoad = false

    public init(drama: Drama, episode: Int = 1) {
        self.drama = drama
        self.episode = episode
    }

    private var busy: Bool { loading || model.socialBusy.contains(drama.cleanSourceId) }

    private func canAct(_ creator: HongguoCreator) -> Bool {
        creator.following != nil && (creator.canFollow || creator.following == true) && creator.id != model.account?.id
    }

    private var targets: [Target] {
        guard !busy && model.loggedIn else { return [.close] }
        var result: [Target] = []
        if let data = model.socialState(drama) {
            if data.episode(episode) != nil { result.append(.like) }
            result += data.creators.filter(canAct).map { .creator($0.id) }
        }
        return result + [.refresh, .close]
    }

    public var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 24) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text("点赞与关注")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(TVColors.textPrimary)
                        Text(drama.title)
                            .font(.system(size: 31))
                            .foregroundColor(TVColors.textSecondary)

                        if !model.loggedIn {
                            Text("请先登录红果账号")
                                .foregroundColor(TVColors.textMuted)
                        } else {
                            if loading {
                                ProgressView("正在读取官方账号状态")
                            }
                            if let error {
                                Text(error)
                                    .foregroundStyle(TVColors.activeRed)
                                    .accessibilityIdentifier("account.social.error")
                            }
                            if let data = model.socialState(drama) {
                                if let like = data.episode(episode) {
                                    Button {
                                        run { try await model.setLiked(drama, episode: like, liked: !like.liked) }
                                    } label: {
                                        Label("第 \(like.number) 集 · \(like.liked ? "取消点赞" : "点赞") · \(like.count)", systemImage: like.liked ? "heart.fill" : "heart")
                                    }
                                    .accessibilityIdentifier("account.episode.like")
                                    .focused($focus, equals: .like)
                                    .id(Target.like)
                                    .disabled(busy)
                                } else {
                                    Text("第 \(episode) 集暂未提供点赞状态")
                                        .foregroundColor(TVColors.textSecondary)
                                }

                                Text("创作者／演员")
                                    .font(.system(size: 35, weight: .bold))
                                    .foregroundColor(TVColors.textPrimary)

                                if let issue = data.creatorError {
                                    Text("关注列表获取失败：\(issue)")
                                        .foregroundStyle(TVColors.activeRed)
                                } else if data.creators.isEmpty {
                                    Text("本剧暂无可关注的创作者账号")
                                        .foregroundColor(TVColors.textSecondary)
                                }

                                ForEach(data.creators) { creator in
                                    HStack {
                                        Text(creator.name)
                                            .foregroundColor(TVColors.textPrimary)
                                        Spacer()
                                        Button(creator.following == nil ? "状态不可用" : creator.following! ? "取消关注" : "关注") {
                                            run { try await model.setCreatorFollowing(drama, creator: creator, follow: creator.following != true) }
                                        }
                                        .accessibilityIdentifier("account.creator.\(creator.id)")
                                        .focused($focus, equals: .creator(creator.id))
                                        .disabled(busy || !canAct(creator))
                                    }
                                    .id(Target.creator(creator.id))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 70)
                    .padding(.top, 70)
                    .padding(.bottom, 30)
                }
                .focusSection()

                HStack(spacing: 36) {
                    Button("刷新") { load() }
                        .disabled(busy || !model.loggedIn)
                        .accessibilityIdentifier("account.social.refresh")
                        .focused($focus, equals: .refresh)

                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("account.social.close")
                        .focused($focus, equals: .close)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 70)
                .padding(.bottom, 50)
                .focusSection()
            }
            .font(.system(size: 29))
            .frame(maxWidth: 1200, maxHeight: .infinity)
            .background(TVColors.backgroundGradient.ignoresSafeArea())
            .defaultFocus($focus, .close)
            .onChange(of: focus) { _, target in
                if let target {
                    switch target {
                    case .like, .creator(_): withAnimation { proxy.scrollTo(target, anchor: .center) }
                    case .refresh, .close: break
                    }
                }
            }
        }
        .task(id: drama.id) { load() }
        .onExitCommand { dismiss() }
    }

    private func restoreFocus(_ preferred: Target) {
        let target = targets.contains(preferred) ? preferred : targets[0]
        focus = nil
        DispatchQueue.main.async { focus = target }
    }

    private func load() {
        let preferred: Target = didLoad ? focus ?? .refresh : .like
        didLoad = true
        loading = true
        Task {
            await perform { try await model.loadSocial(drama) }
            loading = false
            restoreFocus(preferred)
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        let preferred = focus ?? .like
        Task {
            await perform(action)
            restoreFocus(preferred)
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview("TVAccountSocialSheet") {
    TVAccountSocialSheet(drama: Drama(id: "test", title: "测试短剧"))
}
