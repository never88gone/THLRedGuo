import 'package:flutter/material.dart';

import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 主播资料头部卡片组件
class AnchorProfileCard extends StatelessWidget {
  const AnchorProfileCard({
    super.key,
    required this.anchor,
    required this.loggedIn,
    required this.following,
    required this.writing,
    required this.canChangeFollowing,
    required this.onFollow,
  });

  final Anchor anchor;
  final bool loggedIn;
  final bool following;
  final bool writing;
  final bool canChangeFollowing;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final avatarUri = Uri.tryParse(anchor.avatar);
    final hasAvatar =
        !const bool.fromEnvironment('DISABLE_REMOTE_IMAGES') &&
        avatarUri != null &&
        (avatarUri.scheme == 'https' || avatarUri.scheme == 'http');
    final avatarImage = hasAvatar ? NetworkImage(anchor.avatar) : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.white08 : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.white10 : scheme.outlineVariant,
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.hongguoRed.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor:
                  isDark ? AppColors.white12 : scheme.surfaceContainerHigh,
              foregroundImage: avatarImage,
              onForegroundImageError: avatarImage == null
                  ? null
                  : (_, _) {},
              child: Icon(
                Icons.person_outline_rounded,
                size: 30,
                color: isDark ? AppColors.white70 : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            anchor.name,
            key: const ValueKey('anchor-name'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 2.5,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.white06 : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (anchor.dramasCount != null)
                  Text(
                    '作品 ${anchor.dramasCount}',
                    key: const ValueKey('anchor-works-count'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                if (anchor.fansCount != null && anchor.fansCount! > 0) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '·',
                      style: TextStyle(
                        color: isDark ? AppColors.white38 : scheme.outline,
                      ),
                    ),
                  ),
                  Text(
                    '粉丝 ${anchor.fansCount}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            anchor.bio.isEmpty ? '暂无简介' : anchor.bio,
            key: const ValueKey('anchor-bio'),
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (loggedIn) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: ValueKey(
                following ? 'anchor-followed-btn' : 'anchor-follow-btn',
              ),
              onPressed: canChangeFollowing ? onFollow : null,
              style: FilledButton.styleFrom(
                backgroundColor: following
                    ? (isDark
                          ? AppColors.white12
                          : scheme.surfaceContainerHighest)
                    : AppColors.hongguoRed,
                foregroundColor: following
                    ? (isDark ? AppColors.white70 : scheme.onSurfaceVariant)
                    : AppColors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 32),
                shape: const StadiumBorder(),
                elevation: 0,
              ),
              icon: Icon(
                following ? Icons.check_rounded : Icons.add_rounded,
                size: 16,
              ),
              label: Text(
                writing
                    ? '正在确认'
                    : following
                    ? '已关注'
                    : '关注',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
