import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/ranking/ranking_models.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';

/// 榜单常规纵向列表条目组件
class RankingListTile extends StatelessWidget {
  const RankingListTile({
    super.key,
    required this.item,
    required this.repository,
    required this.store,
  });

  final RankingItem item;
  final AppRepository repository;
  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('rank-${item.rank}-${item.drama.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: InkWell(
        key: ValueKey('rank-${item.rank}-${item.drama.id}-tap'),
        borderRadius: BorderRadius.circular(12),
        onFocusChange: (focused) {
          if (focused) {
            Scrollable.ensureVisible(context, alignment: .4);
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
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '${item.rank}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: item.rank <= 3
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                height: 108,
                child: DramaCover(
                  drama: item.drama,
                  repository: repository,
                  radius: 8,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.drama.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (item.drama.category.isNotEmpty)
                      Text(
                        item.drama.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (item.metric.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department_rounded,
                              size: 14,
                              color: AppColors.hongguoRed,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              item.metric,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.hongguoRed,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
