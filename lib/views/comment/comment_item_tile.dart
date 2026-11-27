import 'package:flutter/material.dart';

import 'package:THLRedLook/models/comment/comment_model.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/emoji/emoji_helper.dart';
import 'package:THLRedLook/views/comment/expandable_comment_text.dart';

/// 单条一级评论列表卡片
class CommentItemTile extends StatelessWidget {
  const CommentItemTile({
    super.key,
    required this.comment,
    this.onTap,
  });

  final CommentItem comment;
  final VoidCallback? onTap;

  static String formatTime(int timestamp) {
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

  static String formatNumber(int count) {
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

  @override
  Widget build(BuildContext context) {
    final diggText = formatNumber(comment.diggCount);

    return InkWell(
      onTap: onTap,
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
                          EmojiHelper.emojify(comment.userName),
                          style: EmojiHelper.withEmojiFont(
                            const TextStyle(
                              color: AppColors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
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
                            color: AppColors.white54,
                          ),
                          if (diggText.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              diggText,
                              style: const TextStyle(
                                color: AppColors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ExpandableCommentText(
                    text: comment.text,
                    maxLines: 3,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        formatTime(comment.createTime),
                        style: const TextStyle(
                          color: AppColors.white38,
                          fontSize: 12.5,
                        ),
                      ),
                      if (comment.replyCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white12,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${comment.replyCount} 条回复 >',
                            style: const TextStyle(
                              color: AppColors.hongguoRed,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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
}
