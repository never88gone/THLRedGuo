import 'package:flutter/material.dart';

import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/models/comment/comment_model.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/comment/comment_item_tile.dart';
import 'package:THLRedLook/views/comment/comment_reply_sheet_view.dart';

/// 视频播放页面底部的评论与回复一体化浮层
class CommentSheetView extends StatefulWidget {
  const CommentSheetView({
    super.key,
    required this.bookId,
    required this.accountService,
  });

  final String bookId;
  final HongguoAccountService accountService;

  static Future<void> show({
    required BuildContext context,
    required String bookId,
    required HongguoAccountService accountService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.transparent,
      isScrollControlled: true,
      builder: (_) => CommentSheetView(
        bookId: bookId,
        accountService: accountService,
      ),
    );
  }

  @override
  State<CommentSheetView> createState() => _CommentSheetViewState();
}

class _CommentSheetViewState extends State<CommentSheetView> {
  // 一级评论状态
  final ScrollController _commentScrollController = ScrollController();
  final List<CommentItem> _comments = [];
  bool _loadingComments = true;
  bool _loadingMoreComments = false;
  bool _hasMoreComments = false;
  String _commentCursor = '';
  int _totalComments = 0;
  String? _commentError;

  // 二级回复状态
  CommentItem? _selectedComment;
  final ScrollController _replyScrollController = ScrollController();
  final List<CommentReplyItem> _replies = [];
  bool _loadingReplies = false;
  bool _loadingMoreReplies = false;
  bool _hasMoreReplies = false;
  String _replyCursor = '';
  int _totalReplies = 0;
  String? _replyError;

  @override
  void initState() {
    super.initState();
    _loadInitialComments();
    _commentScrollController.addListener(_onCommentScroll);
    _replyScrollController.addListener(_onReplyScroll);
  }

  @override
  void dispose() {
    _commentScrollController.dispose();
    _replyScrollController.dispose();
    super.dispose();
  }

  void _onCommentScroll() {
    if (_commentScrollController.position.extentAfter < 200 &&
        !_loadingComments &&
        !_loadingMoreComments &&
        _hasMoreComments) {
      _loadMoreComments();
    }
  }

  void _onReplyScroll() {
    if (_replyScrollController.position.extentAfter < 200 &&
        !_loadingReplies &&
        !_loadingMoreReplies &&
        _hasMoreReplies &&
        _selectedComment != null) {
      _loadMoreReplies();
    }
  }

  Future<void> _loadInitialComments() async {
    setState(() {
      _loadingComments = true;
      _commentError = null;
    });
    try {
      final page = await widget.accountService.fetchCommentList(
        bookId: widget.bookId,
        count: 20,
      );
      if (!mounted) return;
      setState(() {
        _comments.clear();
        _comments.addAll(page.list);
        _totalComments = page.total;
        _hasMoreComments = page.hasMore;
        _commentCursor = page.cursor;
        _loadingComments = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingComments = false;
        _commentError = '获取评论列表失败，请重试';
      });
    }
  }

  Future<void> _loadMoreComments() async {
    setState(() => _loadingMoreComments = true);
    try {
      final page = await widget.accountService.fetchCommentList(
        bookId: widget.bookId,
        cursor: _commentCursor,
        count: 20,
      );
      if (!mounted) return;
      setState(() {
        _comments.addAll(page.list);
        _hasMoreComments = page.hasMore;
        _commentCursor = page.cursor;
        _loadingMoreComments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMoreComments = false);
    }
  }

  Future<void> _selectComment(CommentItem comment) async {
    setState(() {
      _selectedComment = comment;
      _replies.clear();
      _loadingReplies = true;
      _replyError = null;
      _replyCursor = '';
      _totalReplies = comment.replyCount;
    });
    try {
      final page = await widget.accountService.fetchCommentReplyList(
        commentId: comment.id,
        bookId: widget.bookId,
        count: 20,
      );
      if (!mounted) return;
      setState(() {
        _replies.addAll(page.list);
        _totalReplies = page.total > 0 ? page.total : comment.replyCount;
        _hasMoreReplies = page.hasMore;
        _replyCursor = page.cursor;
        _loadingReplies = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingReplies = false;
        _replyError = '获取回复列表失败，请重试';
      });
    }
  }

  Future<void> _loadMoreReplies() async {
    final comment = _selectedComment;
    if (comment == null) return;
    setState(() => _loadingMoreReplies = true);
    try {
      final page = await widget.accountService.fetchCommentReplyList(
        commentId: comment.id,
        bookId: widget.bookId,
        cursor: _replyCursor,
        count: 20,
      );
      if (!mounted) return;
      setState(() {
        _replies.addAll(page.list);
        _hasMoreReplies = page.hasMore;
        _replyCursor = page.cursor;
        _loadingMoreReplies = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMoreReplies = false);
    }
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.white10, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32),
          const Spacer(),
          Text(
            '评论 (${_totalComments > 0 ? _totalComments : _comments.length})',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.white70, size: 22),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    if (_loadingComments) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.hongguoRed),
      );
    }
    if (_commentError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _commentError!,
              style: const TextStyle(color: AppColors.white70),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.hongguoRed,
                foregroundColor: AppColors.white,
              ),
              onPressed: _loadInitialComments,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      return const Center(
        child: Text(
          '暂无评论，快来抢首评吧～',
          style: TextStyle(color: AppColors.white54, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      controller: _commentScrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _comments.length + (_loadingMoreComments ? 1 : 0),
      separatorBuilder: (context, index) => const Divider(
        color: AppColors.white06,
        height: 1,
        indent: 64,
      ),
      itemBuilder: (context, index) {
        if (index >= _comments.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.hongguoRed,
                ),
              ),
            ),
          );
        }
        final comment = _comments[index];
        return CommentItemTile(
          comment: comment,
          onTap: () => _selectComment(comment),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final sheetHeight = mediaQuery.size.height * 0.72;
    final selectedComment = _selectedComment;

    return Container(
      height: sheetHeight,
      margin: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: AppColors.black54,
            blurRadius: 16,
            spreadRadius: 4,
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: selectedComment == null
            ? Column(
                key: const ValueKey('comments-main-list'),
                children: [
                  _buildHeader(),
                  Expanded(child: _buildCommentsList()),
                ],
              )
            : CommentReplySheetView(
                key: ValueKey('replies-${selectedComment.id}'),
                mainComment: selectedComment,
                replies: _replies,
                loadingReplies: _loadingReplies,
                loadingMoreReplies: _loadingMoreReplies,
                replyError: _replyError,
                scrollController: _replyScrollController,
                onRetry: () => _selectComment(selectedComment),
                onBack: () => setState(() => _selectedComment = null),
                onClose: () => Navigator.of(context).pop(),
                totalReplies: _totalReplies,
              ),
      ),
    );
  }
}
