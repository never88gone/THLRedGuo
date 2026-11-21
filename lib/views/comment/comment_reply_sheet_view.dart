import 'package:flutter/material.dart';

import 'package:THLRedLook/models/comment/comment_model.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/comment/comment_item_tile.dart';
import 'package:THLRedLook/views/comment/comment_reply_item_tile.dart';
import 'package:THLRedLook/views/comment/expandable_comment_text.dart';

/// 评论二级回复列表浮层视图
class CommentReplySheetView extends StatelessWidget {
  const CommentReplySheetView({
    super.key,
    required this.mainComment,
    required this.replies,
    required this.loadingReplies,
    required this.loadingMoreReplies,
    required this.replyError,
    required this.scrollController,
    required this.onRetry,
    required this.onBack,
    required this.onClose,
    required this.totalReplies,
  });

  final CommentItem mainComment;
  final List<CommentReplyItem> replies;
  final bool loadingReplies;
  final bool loadingMoreReplies;
  final String? replyError;
  final ScrollController scrollController;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final int totalReplies;

  Widget _buildAvatar(String avatarUrl, String name, {double size = 36}) {
    final hasUrl = avatarUrl.trim().isNotEmpty && avatarUrl.startsWith('http');
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        color: AppColors.white20,
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
          color: AppColors.white70,
          fontSize: size * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: AppColors.white,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '全部评论',
                    style: TextStyle(
                      color: AppColors.white,
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
            '回复 (${totalReplies > 0 ? totalReplies : replies.length})',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.white70, size: 22),
            onPressed: onClose,
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        // 置顶展示主评
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.28,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.white08,
              border: Border(
                bottom: BorderSide(color: AppColors.white12, width: 0.8),
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
                            color: AppColors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        ExpandableCommentText(
                          text: mainComment.text,
                          maxLines: 3,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          CommentItemTile.formatTime(mainComment.createTime),
                          style: const TextStyle(
                            color: AppColors.white38,
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
          child: loadingReplies
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.hongguoRed),
                )
              : replyError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            replyError!,
                            style: const TextStyle(color: AppColors.white70),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.hongguoRed,
                              foregroundColor: AppColors.white,
                            ),
                            onPressed: onRetry,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : replies.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无回复',
                            style: TextStyle(color: AppColors.white54, fontSize: 14),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: replies.length + (loadingMoreReplies ? 1 : 0),
                          separatorBuilder: (context, index) => const Divider(
                            color: AppColors.white06,
                            height: 1,
                            indent: 56,
                          ),
                          itemBuilder: (context, index) {
                            if (index >= replies.length) {
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
                            return CommentReplyItemTile(reply: replies[index]);
                          },
                        ),
        ),
      ],
    );
  }
}
