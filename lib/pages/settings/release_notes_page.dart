import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.dateString,
    required this.items,
    required this.raw,
  });

  final String version;
  final DateTime? date;
  final String dateString;
  final List<String> items;
  final String raw;

  static List<ReleaseNote> parse(String markdown) {
    if (markdown.trim().isEmpty) return const [];
    final lines = markdown.split('\n');
    final notes = <ReleaseNote>[];

    String? currentHeader;
    final currentLines = <String>[];

    void commit() {
      if (currentHeader == null) return;
      final header = currentHeader;
      final items = <String>[];
      for (final line in currentLines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('- ') ||
            trimmed.startsWith('* ') ||
            trimmed.startsWith('• ')) {
          final content = trimmed.substring(2).trim();
          if (content.isNotEmpty) items.add(content);
        } else if (RegExp(r'^\d+\.\s+').hasMatch(trimmed)) {
          final content = trimmed.replaceFirst(RegExp(r'^\d+\.\s+'), '').trim();
          if (content.isNotEmpty) items.add(content);
        } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          items.add(trimmed);
        }
      }

      // 提取日期 (如 2026-11-07)
      final dateMatch = RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b')
          .firstMatch(header);
      DateTime? date;
      var dateStr = '';
      if (dateMatch != null) {
        dateStr =
            '${dateMatch.group(1)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(3)!.padLeft(2, '0')}';
        date = DateTime.tryParse(dateStr);
      }

      // 提取版本号 (如 1.0.0)
      final versionMatch = RegExp(
        r'\[?v?(\d+\.\d+(?:\.\d+)?(?:[-+][a-zA-Z0-9_.-]+)?)\]?',
      ).firstMatch(header);
      final version = versionMatch?.group(1) ?? '1.0.0';

      notes.add(
        ReleaseNote(
          version: version,
          date: date,
          dateString: dateStr.isNotEmpty ? dateStr : header,
          items: items,
          raw: currentLines.join('\n'),
        ),
      );
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('## ')) {
        commit();
        currentHeader = trimmed.substring(3).trim();
        currentLines.clear();
      } else if (currentHeader != null) {
        currentLines.add(line);
      }
    }
    commit();

    // 严格按时间倒序排列：时间最新排在最前面
    notes.sort((a, b) {
      if (a.date != null && b.date != null) {
        return b.date!.compareTo(a.date!);
      }
      if (a.date != null) return -1;
      if (b.date != null) return 1;
      return 0;
    });

    return notes;
  }
}

class ReleaseNotesPage extends StatefulWidget {
  const ReleaseNotesPage({super.key});

  @override
  State<ReleaseNotesPage> createState() => _ReleaseNotesPageState();
}

class _ReleaseNotesPageState extends State<ReleaseNotesPage> {
  bool _loading = true;
  String? _error;
  List<ReleaseNote> _notes = const [];

  @override
  void initState() {
    super.initState();
    _loadReleaseNotes();
  }

  Future<void> _loadReleaseNotes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String content;
      try {
        content = await rootBundle.loadString('release.md');
      } catch (_) {
        final localFile = File('release.md');
        if (await localFile.exists()) {
          content = await localFile.readAsString();
        } else {
          rethrow;
        }
      }

      final parsed = ReleaseNote.parse(content);
      if (!mounted) return;
      setState(() {
        _notes = parsed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '未能加载更新内容记录：$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('更新内容'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '重新加载',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadReleaseNotes,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _buildBody(isDark, theme),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark, ThemeData theme) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.hongguoRed,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadReleaseNotes,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.hongguoRed,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_notes.isEmpty) {
      return Center(
        child: Text(
          '暂无更新记录',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? AppColors.greyLight : AppColors.greyDark,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _notes.length + 1,
      itemBuilder: (context, index) {
        if (index == _notes.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '— 已展示全部更新历程 —',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ),
          );
        }

        final note = _notes[index];
        final isLatest = index == 0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Card(
            elevation: 0,
            color: isDark ? AppColors.darkCard : AppColors.greyLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: isLatest
                  ? BorderSide(
                      color: AppColors.hongguoRed.withValues(alpha: 0.35),
                      width: 1.5,
                    )
                  : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isLatest
                              ? AppColors.hongguoRed
                              : (isDark
                                  ? Colors.white12
                                  : Colors.black.withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'v${note.version}',
                          style: TextStyle(
                            color: isLatest ? Colors.white : null,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        note.dateString,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (isLatest)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentSubtle12,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fiber_new_rounded,
                                size: 16,
                                color: AppColors.hongguoRed,
                              ),
                              SizedBox(width: 2),
                              Text(
                                '最新版本',
                                style: TextStyle(
                                  color: AppColors.hongguoRed,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...note.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6, right: 10),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isLatest
                                  ? AppColors.hongguoRed
                                  : (isDark ? Colors.white54 : Colors.black45),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
