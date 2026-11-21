import SwiftUI

// MARK: - tvOS 播放器评论与回复双栏抽屉
public struct TVCommentDrawer: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isPresented: Bool

    @State private var comments: [TVCommentItem] = []
    @State private var isLoadingComments: Bool = true
    @State private var commentError: String? = nil
    @State private var totalComments: Int = 0
    @State private var commentCursor: String = ""
    @State private var hasMoreComments: Bool = false

    @State private var selectedComment: TVCommentItem? = nil
    @State private var replies: [TVCommentReplyItem] = []
    @State private var isLoadingReplies: Bool = false
    @State private var replyError: String? = nil
    @State private var totalReplies: Int = 0
    @State private var replyCursor: String = ""
    @State private var hasMoreReplies: Bool = false

    @FocusState private var focusedTarget: CommentFocusTarget?

    public init(viewModel: PlayerViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            TVColors.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            HStack(spacing: 0) {
                if let mainComment = selectedComment {
                    TVCommentReplyPanel(
                        mainComment: mainComment,
                        replies: replies,
                        totalReplies: totalReplies,
                        isLoadingReplies: isLoadingReplies,
                        replyError: replyError,
                        hasMoreReplies: hasMoreReplies,
                        focusedTarget: $focusedTarget,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                selectedComment = nil
                            }
                            focusedTarget = .comment(mainComment.id)
                        },
                        onRetry: { selectComment(mainComment) },
                        onLoadMore: { loadMoreReplies() }
                    )
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

    private func commentListPanel() -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .background(TVColors.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 20)

            Divider()
                .background(TVColors.borderSubtle)

            if isLoadingComments {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView().scaleEffect(1.4)
                    Spacer()
                }
                Spacer()
            } else if let error = commentError {
                Spacer()
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundColor(TVColors.textSecondary)
                        .font(.body)
                    Button("重试") { loadInitialComments() }
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
                ScrollViewReader { _ in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(comments) { comment in
                                let isSelected = (selectedComment?.id == comment.id)
                                let isFocused = (focusedTarget == .comment(comment.id))

                                Button(action: { selectComment(comment) }) {
                                    TVCommentRowCard(comment: comment, isFocused: isFocused)
                                }
                                .buttonStyle(TvCardButtonStyle(isSelected: isSelected, isFocused: isFocused))
                                .focused($focusedTarget, equals: .comment(comment.id))
                                .id(comment.id)
                                .onMoveCommand { dir in
                                    if dir == .left, selectedComment != nil {
                                        if let firstReply = replies.first {
                                            focusedTarget = .reply(firstReply.id)
                                        } else {
                                            focusedTarget = .closeRepliesButton
                                        }
                                    }
                                }
                            }

                            if hasMoreComments {
                                Button("加载更多评论") { loadMoreComments() }
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
}

#Preview {
    TVCommentDrawer(
        viewModel: PlayerViewModel(
            drama: Drama(id: "1", title: "测试短剧", cover: "", episodes: 20, tags: []),
            allEpisodes: [],
            initialEpisodeIndex: 1
        ),
        isPresented: .constant(true)
    )
}
