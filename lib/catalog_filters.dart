import 'dart:math';

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_layout.dart';
import 'models.dart';
import 'remote_widgets.dart';

class CatalogFilters extends StatefulWidget {
  const CatalogFilters({
    super.key,
    required this.categories,
    required this.category,
    required this.onCategory,
    required this.onRetry,
    this.error,
    this.leading,
    this.trailing,
  });

  final List<CatalogCategory> categories;
  final String category;
  final String? error;
  final ValueChanged<String> onCategory;
  final VoidCallback onRetry;
  final Widget? leading;
  final Widget? trailing;

  @override
  State<CatalogFilters> createState() => _CatalogFiltersState();
}

class _CatalogFiltersState extends State<CatalogFilters> {
  final _anchors = <String, GlobalKey>{};

  @override
  void didUpdateWidget(covariant CatalogFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final anchor = _anchors[widget.category]?.currentContext;
        if (mounted && anchor != null) {
          Scrollable.ensureVisible(
            anchor,
            alignment: .4,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final television = AppLayout.isTelevision(context);
    return SizedBox(
      height: television
          ? 64
          : max(52, MediaQuery.textScalerOf(context).scale(14) + 28),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('catalog-categories'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (widget.leading != null) widget.leading!,
                  for (final entry in widget.categories)
                    Padding(
                      key: _anchors.putIfAbsent(entry.id, GlobalKey.new),
                      padding: const EdgeInsets.only(right: 6),
                      child: television
                          ? RemoteButton(
                              key: ValueKey('category-${entry.id}'),
                              label: entry.name,
                              selected: entry.id == widget.category,
                              onPressed: () => widget.onCategory(entry.id),
                              onFocus: () => widget.onCategory(entry.id),
                            )
                          : ChoiceChip(
                              key: ValueKey('category-${entry.id}'),
                              label: Text(entry.name),
                              selected: entry.id == widget.category,
                              showCheckmark: false,
                              onSelected: (_) => widget.onCategory(entry.id),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              selectedColor: AppColors.hongguoRed,
                              backgroundColor: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0x1FFFFFFF)
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              labelStyle: TextStyle(
                                fontWeight: entry.id == widget.category ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 13,
                                color: entry.id == widget.category
                                    ? AppColors.white
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              side: BorderSide(
                                color: entry.id == widget.category
                                    ? AppColors.hongguoRed
                                    : (Theme.of(context).brightness == Brightness.dark
                                        ? const Color(0x26FFFFFF)
                                        : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                                width: 0.8,
                              ),
                              elevation: entry.id == widget.category ? 3 : 0,
                              shadowColor: entry.id == widget.category ? const Color(0x66FF2442) : null,
                            ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.error != null)
            IconButton(
              tooltip: widget.error,
              onPressed: widget.onRetry,
              icon: Icon(
                Icons.refresh_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}
