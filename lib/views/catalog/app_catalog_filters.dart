import 'package:flutter/material.dart';

import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/catalog/catalog_filters.dart';

class AppCatalogFilters extends StatelessWidget {
  const AppCatalogFilters({
    super.key,
    required this.categories,
    required this.category,
    required this.onCategory,
    required this.onRetry,
    this.error,
    this.leading,
  });

  final List<CatalogCategory> categories;
  final String category;
  final ValueChanged<String> onCategory;
  final VoidCallback onRetry;
  final String? error;
  final Widget? leading;

  Future<void> _chooseFilter(BuildContext context, CatalogCategory tab) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            ListTile(
              title: Text('${tab.name}分类'),
              trailing: TextButton(
                onPressed: () => Navigator.pop(context, tab.id),
                child: const Text('全部'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  for (final group in tab.filterGroups) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        group.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in group.items)
                          ChoiceChip(
                            key: ValueKey('app-filter-${item.id}'),
                            label: Text(item.name),
                            selected: category == item.id,
                            onSelected: (_) => Navigator.pop(context, item.id),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) onCategory(selected);
  }

  @override
  Widget build(BuildContext context) {
    final tab =
        categories
            .where(
              (item) =>
                  category == item.id || category.startsWith('${item.id}:'),
            )
            .firstOrNull ??
        categories.first;
    final sections = categories.map((item) => item.section).toSet();
    final selectedFilter = tab.filterGroups
        .expand((group) => group.items)
        .where((item) => item.id == category)
        .firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CatalogFilters(
          key: const ValueKey('app-discover-sections'),
          categories: [
            for (final section in sections) CatalogCategory(section, section),
          ],
          category: tab.section,
          onCategory: (section) => onCategory(
            categories.firstWhere((item) => item.section == section).id,
          ),
          onRetry: onRetry,
          error: error,
          leading: leading,
        ),
        CatalogFilters(
          key: const ValueKey('app-discover-tabs'),
          categories: categories
              .where((item) => item.section == tab.section)
              .toList(),
          category: tab.id,
          onCategory: onCategory,
          onRetry: onRetry,
          trailing: tab.filterGroups.isEmpty
              ? null
              : TextButton.icon(
                  key: const ValueKey('app-discover-filter'),
                  onPressed: () => _chooseFilter(context, tab),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(selectedFilter?.name ?? '分类'),
                ),
        ),
      ],
    );
  }
}
