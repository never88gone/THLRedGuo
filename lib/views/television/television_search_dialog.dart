import 'dart:async';
import 'package:flutter/material.dart';

import 'package:THLRedLook/views/remote/remote_button.dart';
import 'package:THLRedLook/views/remote/remote_target.dart';

class TelevisionSearchDialog extends StatefulWidget {
  const TelevisionSearchDialog({
    super.key,
    required this.initialValue,
    required this.title,
    this.suggestions,
    this.recentSearches = const [],
    this.onCancel,
  });
  final Future<List<String>> Function(String)? suggestions;
  final List<String> recentSearches;
  final VoidCallback? onCancel;
  final String initialValue;
  final String title;

  @override
  State<TelevisionSearchDialog> createState() => _TelevisionSearchDialogState();
}

class _TelevisionSearchDialogState extends State<TelevisionSearchDialog> {
  late String _query = widget.initialValue;
  List<String> _results = [];
  bool _searching = false;
  Timer? _debounce;

  static const _keys = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
  ];

  @override
  void initState() {
    super.initState();
    _fetchSuggestions(_query.trim());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onKeyPress(String char) {
    setState(() => _query += char);
    _onQueryChanged();
  }

  void _onBackspace() {
    if (_query.isNotEmpty) {
      setState(() => _query = _query.substring(0, _query.length - 1));
      _onQueryChanged();
    }
  }

  void _onClear() {
    if (_query.isNotEmpty) {
      setState(() {
        _query = '';
        _results = [];
      });
      _onQueryChanged();
    }
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final trimmed = _query.trim();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _fetchSuggestions(trimmed);
    });
  }

  Future<void> _fetchSuggestions(String text) async {
    if (widget.suggestions == null) return;
    setState(() => _searching = true);
    try {
      final list = await widget.suggestions!(text);
      if (mounted && _query.trim() == text) {
        setState(() {
          _results = list;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted && _query.trim() == text) setState(() => _searching = false);
    }
  }

  void _submit(String text) {
    var target = text.trim();
    if (target.isEmpty) return;
    // 若用户输入纯拼音头字母且已成功联想出短剧，直接点击搜索时优先取第一部短剧全名
    if (_results.isNotEmpty && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(target)) {
      target = _results.first;
    }
    Navigator.pop(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Row(
        children: [
          Icon(Icons.tv_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.title, style: const TextStyle(fontSize: 20)),
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        height: 520,
        child: Column(
          children: [
            // 顶部只读搜索显示条，彻底杜绝系统软键盘弹出
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .5,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: .3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _query.isEmpty ? '按遥控器输入剧名拼音头字母 (如: BFLC)' : _query,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: _query.isEmpty
                            ? FontWeight.normal
                            : FontWeight.bold,
                        color: _query.isEmpty
                            ? theme.hintColor
                            : theme.colorScheme.onSurface,
                        letterSpacing: _query.isEmpty ? 0 : 2,
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty) ...[
                    Text(
                      '${_query.length} 字母',
                      style: TextStyle(color: theme.hintColor, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 主体区域：左侧爱奇艺式字母键盘，右侧智能联想与历史
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧全字母/数字虚拟键盘
                  SizedBox(
                    width: 440,
                    child: Column(
                      children: [
                        Expanded(
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 6,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 1.4,
                                ),
                            itemCount: _keys.length,
                            itemBuilder: (context, index) {
                              final char = _keys[index];
                              return RemoteTarget(
                                key: ValueKey('tv-key-$char'),
                                autofocus: index == 0,
                                radius: 10,
                                padding: EdgeInsets.zero,
                                onPressed: () => _onKeyPress(char),
                                child: Center(
                                  child: Text(
                                    char,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 底部三大功能键
                        Row(
                          children: [
                            Expanded(
                              child: RemoteButton(
                                label: '退格',
                                icon: Icons.backspace_outlined,
                                onPressed: _query.isNotEmpty
                                    ? _onBackspace
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RemoteButton(
                                label: '清空',
                                icon: Icons.delete_outline_rounded,
                                onPressed: _query.isNotEmpty ? _onClear : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RemoteButton(
                                label: '搜索',
                                icon: Icons.search_rounded,
                                selected: true,
                                onPressed: () => _submit(_query),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 20),
                  // 右侧联想与匹配结果
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _query.isEmpty
                              ? '猜你想搜与历史搜索'
                              : (_searching
                                    ? '正在匹配...'
                                    : '匹配结果 (${_results.length})'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: _query.isEmpty
                              ? (_results.isEmpty &&
                                        widget.recentSearches.isEmpty
                                    ? Center(
                                        child: Text(
                                          '暂无历史搜索\n用左侧键盘按首字母搜剧',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: theme.hintColor,
                                          ),
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (final item in {
                                              ..._results,
                                              ...widget.recentSearches,
                                            })
                                              RemoteButton(
                                                key: ValueKey('recent-$item'),
                                                label: item,
                                                onPressed: () => _submit(item),
                                              ),
                                          ],
                                        ),
                                      ))
                              : (_results.isEmpty
                                    ? Center(
                                        child: Text(
                                          _searching
                                              ? '搜索中...'
                                              : '按【搜索】直接查找 “$_query”',
                                          style: TextStyle(
                                            color: theme.hintColor,
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: _results.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 6),
                                        itemBuilder: (context, index) {
                                          final item = _results[index];
                                          return RemoteButton(
                                            key: ValueKey('suggest-$index'),
                                            label: item,
                                            icon: Icons.movie_outlined,
                                            onPressed: () => _submit(item),
                                          );
                                        },
                                      )),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
