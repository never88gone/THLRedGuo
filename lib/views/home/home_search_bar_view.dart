import 'package:flutter/material.dart';

import 'package:THLRedLook/views/search/search_input.dart';

/// 首页搜索框与历史搜索词组合视图
class HomeSearchBarView extends StatelessWidget {
  const HomeSearchBarView({
    super.key,
    required this.groupId,
    required this.controller,
    required this.hint,
    required this.suggestions,
    required this.recentSearches,
    required this.onChanged,
    required this.onCancelSuggestions,
    required this.onSearch,
    required this.onClearRecentSearches,
  });

  final String groupId;
  final TextEditingController controller;
  final String hint;
  final Future<List<String>> Function(String)? suggestions;
  final List<String> recentSearches;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancelSuggestions;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearRecentSearches;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: SearchInput(
            key: ValueKey('search-$groupId'),
            controller: controller,
            autofocus: true,
            hint: hint,
            suggestions: suggestions,
            onChanged: onChanged,
            onCancel: onCancelSuggestions,
            onSearch: onSearch,
          ),
        ),
        if (controller.text.trim().isEmpty && recentSearches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final query in recentSearches)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.history_rounded,
                                size: 16,
                              ),
                              label: Text(query),
                              onPressed: () => onSearch(query),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '清空最近搜索',
                  onPressed: onClearRecentSearches,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
