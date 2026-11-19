import SwiftUI

// MARK: - tvOS 播放器评论与回复双栏抽屉
public struct TVCommentDrawer: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isPresented: Bool

    // 一级评论状态
    @State private var comments: [TVCommentItem] = []
    @State private var isLoadingComments: Bool = true
    @State private var commentError: String? = nil
    @State private var totalComments: Int = 0
    @State private var commentCursor: String = ""
    @State private var hasMoreComments: Bool = false

    // 二级回复状态
    @State private var selectedComment: TVCommentItem? = nil
    @State private var replies: [TVCommentReplyItem] = []
    @State private var isLoadingReplies: Bool = false
    @State private var replyError: String? = nil
    @State private var totalReplies: Int = 0
    @State private var replyCursor: String = ""
    @State private var hasMoreReplies: Bool = false

    // 焦点枚举与状态
    enum CommentFocusTarget: Hashable {
        case comment(String)
        case reply(String)
        case closeRepliesButton
    }

    @FocusState private var focusedTarget: CommentFocusTarget?

    public init(viewModel: PlayerViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            // 背景蒙层
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // 双栏并列抽屉主体（左侧为二级回复，最右侧为一级评论）
            HStack(spacing: 0) {
                // MARK: - 左侧二级回复列表面板
                if let mainComment = selectedComment {
                    replyPanel(for: mainComment)
                        .frame(width: 620)
                        .frame(maxHeight: .infinity)
                        .background(TVColors.drawerBackground.opacity(0.98))
                        .overlay(
                            Rectangle()
                                .fill(TVColors.borderSubtle)
                                .frame(width: 1),
                            alignment: .trailing
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // MARK: - 最右侧一级评论列表面板
                commentListPanel()
                    .frame(width: 680)
                    .frame(maxHeight: .infinity)
                    .background(TVColors.drawerBackground)
            }
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onExitCommand {
            handleExit()
        }
        .onAppear {
            loadInitialComments()
        }
    }

    private func handleExit() {
        if selectedComment != nil {
            let lastCommentId = selectedComment?.id
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedComment = nil
            }
            if let id = lastCommentId {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    focusedTarget = .comment(id)
                }
            }
        } else {
            isPresented = false
        }
    }

    // MARK: - 最右侧：一级评论列表面板
    private func commentListPanel() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("评论")
                        .font(.title2)
                        .bold()
                        .foregroundColor(TVColors.textPrimary)
                    Text("共 \(totalComments > 0 ? totalComments : comments.count) 条评论 · 点击查看回复")
                        .font(.subheadline)
                        .foregroundColor(TVColors.textSecondary)
                }
                Spacer()
                Text("按 Menu 返回")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TVColors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 20)

            Divider()
                .background(TVColors.borderSubtle)

            // 内容列表
            if isLoadingComments {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.4)
                    Spacer()
                }
                Spacer()
            } else if let error = commentError {
                Spacer()
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundColor(TVColors.textSecondary)
                        .font(.body)
                    Button("重试") {
                        loadInitialComments()
                    }
                    .buttonStyle(TvButtonStyle(variant: .primary, cornerRadius: 12))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if comments.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("暂无评论，快来抢首评吧～")
                        .foregroundColor(TVColors.textSecondary)
                        .font(.headline)
                    Spacer()
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(comments) { comment in
                                let isSelected = (selectedComment?.id == comment.id)
                                let isFocused = (focusedTarget == .comment(comment.id))

                                Button(action: {
                                    selectComment(comment)
                                }) {
                                    commentRowView(comment: comment, isSelected: isSelected, isFocused: isFocused)
                                }
                                .buttonStyle(TvCardButtonStyle(isSelected: isSelected, isFocused: isFocused))
                                .focused($focusedTarget, equals: .comment(comment.id))
                                .id(comment.id)
                                .onMoveCommand { dir in
                                    switch dir {
                                    case .left:
                                        if selectedComment != nil {
                                            if let firstReply = replies.first {
                                                focusedTarget = .reply(firstReply.id)
                                            } else {
                                                focusedTarget = .closeRepliesButton
                                            }
                                        }
                                    default:
                                        break
                                    }
                                }
                            }

                            if hasMoreComments {
                                Button("加载更多评论") {
                                    loadMoreComments()
                                }
                                .buttonStyle(TvButtonStyle(variant: .plain, cornerRadius: 10))
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 48)
                    }
                }
            }
        }
    }

    // MARK: - 左侧：二级回复列表面板
    private func replyPanel(for mainComment: TVCommentItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部导航与标题
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedComment = nil
                    }
                    focusedTarget = .comment(mainComment.id)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                        Text("收起回复")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(TvButtonStyle(variant: .plain, cornerRadius: 18, isFocused: focusedTarget == .closeRepliesButton))
                .focused($focusedTarget, equals: .closeRepliesButton)
                .onMoveCommand { dir in
                    if dir == .right {
                        focusedTarget = .comment(mainComment.id)
                    }
                }

                Spacer()

                Text("回复 (\(totalReplies > 0 ? totalReplies : replies.count))")
                    .font(.title3)
                    .bold()
                    .foregroundColor(TVColors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 16)

            Divider()
                .background(TVColors.borderSubtle)

            // 置顶主评卡片（深色背景突出上下文）
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    avatarView(url: mainComment.userAvatar, name: mainComment.userName, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mainComment.userName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(TVColors.textPrimary)
                        Text(formatTimestamp(mainComment.createTime))
                            .font(.caption2)
                            .foregroundColor(TVColors.textSecondary)
                    }
                    Spacer()
                    if mainComment.diggCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundColor(TVColors.activeRed)
                            Text(formatNumber(mainComment.diggCount))
                                .font(.caption2)
                                .foregroundColor(TVColors.textSecondary)
                        }
                    }
                }

                Text(mainComment.text)
                    .font(.system(size: 15))
                    .foregroundColor(TVColors.textPrimary)
                    .lineLimit(3)
            }
            .padding(16)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()
                .background(TVColors.borderSubtle)

            // 回复列表内容
            if isLoadingReplies {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.3)
                    Spacer()
                }
                Spacer()
            } else if let error = replyError {
                Spacer()
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundColor(TVColors.textSecondary)
                        .font(.body)
                    Button("重试") {
                        selectComment(mainComment)
                    }
                    .buttonStyle(TvButtonStyle(variant: .primary, cornerRadius: 10))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if replies.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("暂无回复")
                        .foregroundColor(TVColors.textSecondary)
                        .font(.headline)
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(replies) { reply in
                            let isFocused = (focusedTarget == .reply(reply.id))
                            Button(action: {}) {
                                replyRowView(reply: reply, isFocused: isFocused)
                            }
                            .buttonStyle(TvCardButtonStyle(isSelected: false, isFocused: isFocused))
                            .focused($focusedTarget, equals: .reply(reply.id))
                            .id(reply.id)
                            .onMoveCommand { dir in
                                if dir == .right {
                                    focusedTarget = .comment(mainComment.id)
                                }
                            }
                        }

                        if hasMoreReplies {
                            Button("加载更多回复") {
                                loadMoreReplies()
                            }
                            .buttonStyle(TvButtonStyle(variant: .plain, cornerRadius: 10))
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - 单条一级评论行卡片
    private func commentRowView(comment: TVCommentItem, isSelected: Bool, isFocused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                avatarView(url: comment.userAvatar, name: comment.userName, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.userName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isFocused ? .white : TVColors.textPrimary)
                    Text(formatTimestamp(comment.createTime))
                        .font(.caption2)
                        .foregroundColor(TVColors.textSecondary)
                }

                Spacer()

                if comment.diggCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(TVColors.activeRed)
                        Text(formatNumber(comment.diggCount))
                            .font(.caption2)
                            .foregroundColor(TVColors.textSecondary)
                    }
                }
            }

            Text(comment.text)
                .font(.system(size: 15))
                .foregroundColor(isFocused ? .white : Color.white.opacity(0.92))
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if comment.replyCount > 0 {
                HStack {
                    Text("\(comment.replyCount) 条回复 >")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(TVColors.activeRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(TVColors.activeRed.opacity(0.14))
                        .cornerRadius(8)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 单条二级回复行卡片
    private func replyRowView(reply: TVCommentReplyItem, isFocused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                avatarView(url: reply.userAvatar, name: reply.userName, size: 30)

                HStack(spacing: 6) {
                    Text(reply.userName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isFocused ? .white : TVColors.textPrimary)

                    if !reply.replyToUserName.isEmpty {
                        Text("▶")
                            .font(.system(size: 10))
                            .foregroundColor(TVColors.textSecondary)
                        Text(reply.replyToUserName)
                            .font(.system(size: 14))
                            .foregroundColor(TVColors.textSecondary)
                    }
                }

                Spacer()

                if reply.diggCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(TVColors.activeRed)
                        Text(formatNumber(reply.diggCount))
                            .font(.caption2)
                            .foregroundColor(TVColors.textSecondary)
                    }
                }
            }

            Text(reply.text)
                .font(.system(size: 14))
                .foregroundColor(isFocused ? .white : Color.white.opacity(0.90))
                .lineLimit(4)
                .multilineTextAlignment(.leading)

            Text(formatTimestamp(reply.createTime))
                .font(.caption2)
                .foregroundColor(TVColors.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 头像渲染
    private func avatarView(url: String, name: String, size: CGFloat) -> some View {
        Group {
            if let validUrl = URL(string: url), !url.isEmpty {
                AsyncImage(url: validUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        fallbackAvatar(name: name, size: size)
                    }
                }
            } else {
                fallbackAvatar(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func fallbackAvatar(name: String, size: CGFloat) -> some View {
        ZStack {
            Color.white.opacity(0.18)
            Text(name.prefix(1))
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - 数据加载与切换
    private func loadInitialComments() {
        isLoadingComments = true
        commentError = nil
        Task {
            do {
                let page = try await TVCommentService.shared.fetchCommentList(bookId: viewModel.drama.id)
                await MainActor.run {
                    self.comments = page.list
                    self.totalComments = page.total
                    self.hasMoreComments = page.hasMore
                    self.commentCursor = page.cursor
                    self.isLoadingComments = false
                    if let first = page.list.first {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.focusedTarget = .comment(first.id)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.commentError = "获取评论失败，请重试"
                    self.isLoadingComments = false
                }
            }
        }
    }

    private func loadMoreComments() {
        Task {
            do {
                let page = try await TVCommentService.shared.fetchCommentList(bookId: viewModel.drama.id, cursor: commentCursor)
                await MainActor.run {
                    self.comments.append(contentsOf: page.list)
                    self.hasMoreComments = page.hasMore
                    self.commentCursor = page.cursor
                }
            } catch {}
        }
    }

    private func selectComment(_ comment: TVCommentItem) {
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedComment = comment
            replies = []
            totalReplies = comment.replyCount
            isLoadingReplies = true
            replyError = nil
            replyCursor = ""
        }
        Task {
            do {
                let page = try await TVCommentService.shared.fetchCommentReplyList(commentId: comment.id, bookId: viewModel.drama.id)
                await MainActor.run {
                    self.replies = page.list
                    self.totalReplies = page.total > 0 ? page.total : comment.replyCount
                    self.hasMoreReplies = page.hasMore
                    self.replyCursor = page.cursor
                    self.isLoadingReplies = false
                    if let firstReply = page.list.first {
                        self.focusedTarget = .reply(firstReply.id)
                    } else {
                        self.focusedTarget = .closeRepliesButton
                    }
                }
            } catch {
                await MainActor.run {
                    self.replyError = "获取回复失败，请重试"
                    self.isLoadingReplies = false
                }
            }
        }
    }

    private func loadMoreReplies() {
        guard let comment = selectedComment else { return }
        Task {
            do {
                let page = try await TVCommentService.shared.fetchCommentReplyList(commentId: comment.id, bookId: viewModel.drama.id, cursor: replyCursor)
                await MainActor.run {
                    self.replies.append(contentsOf: page.list)
                    self.hasMoreReplies = page.hasMore
                    self.replyCursor = page.cursor
                }
            } catch {}
        }
    }

    private func formatTimestamp(_ ts: Int) -> String {
        guard ts > 0 else { return "" }
        let ms = ts < 10000000000 ? ts * 1000 : ts
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(diff / 60)分钟前" }
        if diff < 86400 { return "\(diff / 3600)小时前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatNumber(_ num: Int) -> String {
        guard num > 0 else { return "" }
        if num < 10000 { return "\(num)" }
        return String(format: "%.1f万", Double(num) / 10000.0)
    }
}

// MARK: - tvOS 专属卡片焦点按钮样式
public struct TvCardButtonStyle: ButtonStyle {
    public let isSelected: Bool
    public let isFocused: Bool

    public init(isSelected: Bool = false, isFocused: Bool = false) {
        self.isSelected = isSelected
        self.isFocused = isFocused
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? Color.white.opacity(0.24) : (isSelected ? TVColors.activeRed.opacity(0.18) : Color.white.opacity(0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white : (isSelected ? TVColors.activeRed : Color.white.opacity(0.10)), lineWidth: isFocused ? 2.5 : 1)
            )
            .shadow(color: isFocused ? TVColors.activeRed.opacity(0.5) : Color.clear, radius: 10)
            .scaleEffect(isFocused ? 1.025 : 1.0)
            .animation(.easeInOut(duration: 0.16), value: isFocused)
    }
}
