import 'package:flutter/material.dart';

import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/models/comment/comment_model.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

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
      backgroundColor: Colors.transparent,
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

  String _formatTime(int timestamp) {
    if (timestamp <= 0) return '';
    final timeMs = timestamp < 10000000000 ? timestamp * 1000 : timestamp;
    final date = DateTime.fromMillisecondsSinceEpoch(timeMs);
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatNumber(int count) {
    if (count <= 0) return '';
    if (count < 10000) return count.toString();
    return '${(count / 10000).toStringAsFixed(1)}万';
  }

  Widget _buildAvatar(String avatarUrl, String name, {double size = 36}) {
    final hasUrl = avatarUrl.trim().isNotEmpty && avatarUrl.startsWith('http');
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        color: const Color(0x33FFFFFF),
        child: hasUrl
            ? Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildFallbackAvatar(name, size),
              )
            : _buildFallbackAvatar(name, size),
      ),
    );
  }

  Widget _buildFallbackAvatar(String name, double size) {
    return Center(
      child: Text(
        name.isNotEmpty ? name.substring(0, 1) : '果',
        style: TextStyle(
          color: Colors.white70,
          fontSize: size * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isReplyView = _selectedComment != null;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x1AFFFFFF), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          if (isReplyView) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selectedComment = null),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '全部评论',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Text(
              '回复 (${_totalReplies > 0 ? _totalReplies : _replies.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
          ] else ...[
            const SizedBox(width: 32),
            const Spacer(),
            Text(
              '评论 (${_totalComments > 0 ? _totalComments : _comments.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
          ],
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(CommentItem comment) {
    final diggText = _formatNumber(comment.diggCount);
    return InkWell(
      onTap: () => _selectComment(comment),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(comment.userAvatar, comment.userName, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          comment.userName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.favorite_border_rounded,
                            size: 15,
                            color: Colors.white54,
                          ),
                          if (diggText.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              diggText,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _ExpandableCommentText(
                    text: comment.text,
                    maxLines: 3,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _formatTime(comment.createTime),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      if (comment.replyCount > 0) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x1FFFFFFF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${comment.replyCount} 条回复 >',
                            style: const TextStyle(
                              color: AppColors.hongguoRed,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyItem(CommentReplyItem reply) {
    final diggText = _formatNumber(reply.diggCount);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(reply.userAvatar, reply.userName, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              reply.userName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (reply.replyToUserName.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                '▶',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                reply.replyToUserName,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.favorite_border_rounded,
                          size: 14,
                          color: Colors.white54,
                        ),
                        if (diggText.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            diggText,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                _ExpandableCommentText(
                  text: reply.text,
                  maxLines: 3,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTime(reply.createTime),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
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
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.hongguoRed,
                foregroundColor: Colors.white,
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
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      controller: _commentScrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _comments.length + (_loadingMoreComments ? 1 : 0),
      separatorBuilder: (context, index) => const Divider(
        color: Color(0x0FFFFFFF),
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
        return _buildCommentItem(_comments[index]);
      },
    );
  }

  Widget _buildRepliesList() {
    final mainComment = _selectedComment;
    if (mainComment == null) return const SizedBox.shrink();

    return Column(
      children: [
        // 置顶展示主评
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.28,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0x14FFFFFF),
              border: Border(
                bottom: BorderSide(color: Color(0x1FFFFFFF), width: 0.8),
              ),
            ),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvatar(mainComment.userAvatar, mainComment.userName, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mainComment.userName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        _ExpandableCommentText(
                          text: mainComment.text,
                          maxLines: 3,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatTime(mainComment.createTime),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 回复列表
        Expanded(
          child: _loadingReplies
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.hongguoRed),
                )
              : _replyError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _replyError!,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.hongguoRed,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _selectComment(mainComment),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : _replies.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无回复',
                            style: TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                        )
                      : ListView.separated(
                          controller: _replyScrollController,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _replies.length + (_loadingMoreReplies ? 1 : 0),
                          separatorBuilder: (context, index) => const Divider(
                            color: Color(0x0FFFFFFF),
                            height: 1,
                            indent: 56,
                          ),
                          itemBuilder: (context, index) {
                            if (index >= _replies.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.hongguoRed,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return _buildReplyItem(_replies[index]);
                          },
                        ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final sheetHeight = mediaQuery.size.height * 0.72;

    return Container(
      height: sheetHeight,
      margin: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _selectedComment == null
                  ? _buildCommentsList()
                  : _buildRepliesList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 支持超过 maxLines（默认 3 行）折叠与展开收起的多行评论文本组件
class _ExpandableCommentText extends StatefulWidget {
  const _ExpandableCommentText({
    required this.text,
    this.maxLines = 3,
    this.style,
  });

  final String text;
  final int maxLines;
  final TextStyle? style;

  @override
  State<_ExpandableCommentText> createState() => _ExpandableCommentTextState();
}

class _ExpandableCommentTextState extends State<_ExpandableCommentText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableCommentText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.style ??
        const TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.4,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return Text(
            widget.text,
            style: textStyle,
            maxLines: _expanded ? null : widget.maxLines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          );
        }

        final span = TextSpan(text: widget.text, style: textStyle);
        final tp = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxWidth);

        final bool isExceeded = tp.didExceedMaxLines;

        if (!isExceeded) {
          return Text(
            widget.text,
            style: textStyle,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: textStyle,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? '收起' : '展开全文',
                      style: const TextStyle(
                        color: AppColors.hongguoRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: AppColors.hongguoRed,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
