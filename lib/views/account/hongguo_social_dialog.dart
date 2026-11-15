import 'package:flutter/material.dart';
import '../../core/account/hongguo_account_social.dart';
import '../../core/bridge/core_bridge.dart';
import '../../core/store/local_store.dart';
import '../../models/catalog/models.dart';
import '../../pages/anchor/anchor_detail_page.dart';
import '../../utils/theme/app_colors.dart';

class HongguoSocialButton extends StatelessWidget {
  const HongguoSocialButton({
    super.key,
    required this.drama,
    this.repository,
    this.store,
    this.episode = 1,
    this.onOpenDrama,
    this.likeOnly = false,
    this.anchorOnly = false,
  });
  final Drama drama;
  final AppRepository? repository;
  final LocalStore? store;
  final int episode;
  final ValueChanged<Drama>? onOpenDrama;
  final bool likeOnly;
  final bool anchorOnly;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      HongguoAccountSocial.shared,
      ?store,
    ]),
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;

      final model = HongguoAccountSocial.shared;
      if (!model.active) {
        return const SizedBox.shrink();
      }
      final data = model.snapshot(drama);
      final like = data?.episode(episode);
      final isLiked = like?.liked ?? false;
      final creator = data?.creators.firstOrNull;

      final Anchor? anchor = creator != null
          ? Anchor(
              id: creator.id,
              name: creator.name,
              isFollowed: creator.following == true,
              officialFollowing: creator.following,
              canFollow: creator.canFollow,
              relativeType: creator.relativeType,
            )
          : null;

      final likeBtn = Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('account-social-like-btn'),
          onTap: () {
            if (like != null) {
              model.like(drama, like, !isLiked);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isLiked
                  ? AppColors.hongguoRed.withValues(alpha: 0.16)
                  : (isDark
                      ? const Color(0x14FFFFFF)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.8)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isLiked
                    ? AppColors.hongguoRed.withValues(alpha: 0.5)
                    : (isDark
                        ? const Color(0x26FFFFFF)
                        : scheme.outlineVariant.withValues(alpha: 0.5)),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 14,
                  color: isLiked
                      ? AppColors.hongguoRed
                      : (isDark ? Colors.white70 : scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Text(
                  isLiked
                      ? (like != null && like.count > 0
                          ? '已赞 ${like.count}'
                          : '已赞')
                      : (like != null && like.count > 0
                          ? '点赞 ${like.count}'
                          : '点赞'),
                  style: TextStyle(
                    color: isLiked
                        ? AppColors.hongguoRed
                        : (isDark ? Colors.white : scheme.onSurface),
                    fontSize: 11.5,
                    fontWeight: isLiked ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      Widget? anchorEntry;
      if (anchor != null) {
        final anchorAvatarUri = Uri.tryParse(anchor.avatar);
        final hasAnchorAvatar =
            !const bool.fromEnvironment('DISABLE_REMOTE_IMAGES') &&
            anchorAvatarUri != null &&
            (anchorAvatarUri.scheme == 'https' ||
                anchorAvatarUri.scheme == 'http');
        final anchorAvatarImage =
            hasAnchorAvatar ? NetworkImage(anchor.avatar) : null;

        anchorEntry = Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('detail-anchor-entry'),
            borderRadius: BorderRadius.circular(13),
            onTap: () {
              if (repository != null && store != null) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AnchorDetailPage(
                      anchor: anchor,
                      repository: repository!,
                      store: store!,
                      initialDramas: [drama],
                      onOpenDrama: onOpenDrama,
                    ),
                  ),
                );
              }
            },
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0x14FFFFFF)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: isDark
                      ? const Color(0x1AFFFFFF)
                      : scheme.outlineVariant.withValues(alpha: 0.5),
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 8,
                    backgroundColor: AppColors.hongguoRed.withValues(alpha: 0.2),
                    foregroundImage: anchorAvatarImage,
                    onForegroundImageError: anchorAvatarImage == null
                        ? null
                        : (_, _) {},
                    child: const Icon(
                      Icons.person,
                      size: 11,
                      color: AppColors.hongguoRed,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '主播 · ${anchor.name}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: isDark ? Colors.white : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: isDark ? Colors.white54 : scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      }

      if (likeOnly) {
        return likeBtn;
      }
      if (anchorOnly) {
        return anchorEntry ?? const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            likeBtn,
            ?anchorEntry,
          ],
        ),
      );
    },
  );
}

Future<void> showHongguoSocialDialog(
  BuildContext context,
  Drama drama,
  int episode,
) async {
  final model = HongguoAccountSocial.shared;
  if (!model.active) return;
  final data = model.snapshot(drama);
  if (data == null) {
    await model.load(drama);
  }
}
