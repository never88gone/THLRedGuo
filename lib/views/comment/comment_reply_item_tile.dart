import 'package:flutter/material.dart';

import 'package:THLRedLook/models/comment/comment_model.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/emoji/emoji_helper.dart';
import 'package:THLRedLook/views/comment/comment_item_tile.dart';
import 'package:THLRedLook/views/comment/expandable_comment_text.dart';

/// 单条二级回复卡片
class CommentReplyItemTile extends StatelessWidget {
  const CommentReplyItemTile({
    super.key,
    required this.reply,
  });

  final CommentReplyItem reply;

  Widget _buildAvatar(String avatarUrl, String name, {double size = 30}) {
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
    final diggText = CommentItemTile.formatNumber(reply.diggCount);

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
                              EmojiHelper.emojify(reply.userName),
                              style: EmojiHelper.withEmojiFont(
                                const TextStyle(
                                  color: AppColors.white70,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
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
                                  color: AppColors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                EmojiHelper.emojify(reply.replyToUserName),
                                style: EmojiHelper.withEmojiFont(
                                  const TextStyle(
                                    color: AppColors.white60,
                                    fontSize: 13.5,
                                  ),
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
                          color: AppColors.white54,
                        ),
                        if (diggText.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            diggText,
                            style: const TextStyle(
                              color: AppColors.white54,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ExpandableCommentText(
                  text: reply.text,
                  maxLines: 3,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  CommentItemTile.formatTime(reply.createTime),
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
    );
  }
}
