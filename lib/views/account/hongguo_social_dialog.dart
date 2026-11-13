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
  });
  final Drama drama;
  final AppRepository? repository;
  final LocalStore? store;
  final int episode;
  final ValueChanged<Drama>? onOpenDrama;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: HongguoAccountSocial.shared,
    builder: (context, _) {
      final model = HongguoAccountSocial.shared;
      // 未登录状态下不显示点赞与关注按钮
      if (!model.active) {
        return const SizedBox.shrink();
      }

      final data = model.snapshot(drama);
      final like = data?.episode(episode);
      final isLiked = like?.liked == true;
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

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 点赞短剧操作（纯接口请求，无需本地记录）
            Row(
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('account-social-like-btn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: isLiked
                        ? AppColors.hongguoRed.withValues(alpha: 0.15)
                        : null,
                    foregroundColor: isLiked ? AppColors.hongguoRed : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: like == null
                      ? null
                      : () {
                          model.like(drama, like, !isLiked);
                        },
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: isLiked ? AppColors.hongguoRed : null,
                  ),
                  label: Text(
                    isLiked
                        ? ((like?.count ?? 0) > 0
                            ? '已点赞 (${like!.count})'
                            : '已点赞')
                        : ((like?.count ?? 0) > 0
                            ? '点赞 (${like!.count})'
                            : '点赞'),
                  ),
                ),
              ],
            ),
            // 主播入口卡片（点击跳转主播详情页面，并在主播详情页面中进行关注）
            if (anchor != null) ...[
              const SizedBox(height: 10),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: const ValueKey('detail-anchor-entry'),
                  borderRadius: BorderRadius.circular(12),
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                          radius: 14,
                          child: Icon(Icons.person, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '主播 · ${anchor.name}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
