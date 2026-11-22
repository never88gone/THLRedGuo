import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/ranking/ranking_models.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/theme/app_gradients.dart';
import 'package:THLRedLook/views/common/widgets.dart';

/// 榜单瀑布流网格展示卡片
class RankingWaterfallCard extends StatelessWidget {
  const RankingWaterfallCard({
    super.key,
    required this.item,
    required this.itemWidth,
    required this.coverHeight,
    required this.repository,
    required this.store,
  });

  final RankingItem item;
  final double itemWidth;
  final double coverHeight;
  final AppRepository repository;
  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (badgeBg, badgeTextColor, badgeLabel) = switch (item.rank) {
      1 => (
        AppGradients.rankingRank1,
        AppColors.white,
        'TOP 1',
      ),
      2 => (
        AppGradients.rankingRank2,
        AppColors.white,
        'TOP 2',
      ),
      3 => (
        AppGradients.rankingRank3,
        AppColors.white,
        'TOP 3',
      ),
      _ => (
        LinearGradient(
          colors: [
            AppColors.black.withValues(alpha: 0.72),
            AppColors.black.withValues(alpha: 0.85),
          ],
        ),
        AppColors.white.withValues(alpha: 0.95),
        '#${item.rank}',
      ),
    };

    return Card(
      key: ValueKey('rank-${item.rank}-${item.drama.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColors.transparent,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onFocusChange: (focused) {
          if (focused) {
            Scrollable.ensureVisible(context, alignment: 0.4);
          }
        },
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => DetailScreen(
              drama: item.drama,
              repository: repository,
              store: store,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: itemWidth,
              height: coverHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DramaCover(
                      drama: item.drama,
                      repository: repository,
                      radius: 8,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.black.withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          color: badgeTextColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.drama.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                if (item.metric.isNotEmpty) ...[
                  const Icon(
                    Icons.local_fire_department_rounded,
                    size: 13,
                    color: AppColors.hongguoRed,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      item.metric,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.hongguoRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else if (item.drama.category.isNotEmpty) ...[
                  Expanded(
                    child: Text(
                      item.drama.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.whiteWithAlpha(0.6)
                            : AppColors.greyDark,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
