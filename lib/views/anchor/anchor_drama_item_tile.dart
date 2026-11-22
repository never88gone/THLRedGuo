import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 主播作品列表短剧单项组件
class AnchorDramaItemTile extends StatelessWidget {
  const AnchorDramaItemTile({
    super.key,
    required this.drama,
    required this.repository,
    required this.store,
  });

  final Drama drama;
  final AppRepository repository;
  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        key: ValueKey('anchor-drama-${drama.id}'),
        color: isDark ? AppColors.darkCard : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DetailScreen(
                drama: drama,
                repository: repository,
                store: store,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.hongguoRed.withValues(
                      alpha: 0.15,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.movie_outlined,
                    color: AppColors.hongguoRed,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repository.catalogUpdates.current(drama).title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        drama.episodes > 0
                            ? (drama.displayCategory.isNotEmpty
                                ? '${drama.displayCategory} · 共 ${drama.episodes} 集'
                                : '共 ${drama.episodes} 集')
                            : (drama.displayCategory.isNotEmpty
                                ? drama.displayCategory
                                : '点击查看剧集'),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.play_circle_outline_rounded,
                  color: AppColors.hongguoRed,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
