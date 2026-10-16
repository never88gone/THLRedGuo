import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 应用内「日记」日志服务 — 实时记录播放与系统事件，方便在电视与手机端快速排查问题。
class DiaryService {
  static final List<String> _entries = <String>[];
  static const int maxEntries = 500;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 记录一条日记
  static void add(String message) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${(now.millisecond ~/ 100)}';
    final entry = '[$timeStr] $message';
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    revision.value++;
    debugPrint('[Diary] $message');
  }

  /// 获取当前所有日记副本
  static List<String> get entries => List<String>.unmodifiable(_entries);

  /// 清空日记
  static void clear() {
    _entries.clear();
    revision.value++;
  }

  /// 获取合并后的完整日志文本
  static String get fullText => _entries.join('\n');

  /// 复制全部日记到剪贴板
  static Future<void> copyToClipboard(BuildContext context) async {
    final text = fullText;
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('已复制播放日记到剪贴板'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 在界面上弹出交互式日记弹窗（兼容 TV 遥控器与手机触屏）
  static Future<void> showDiaryDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final scrollController = ScrollController();
        return AlertDialog(
          backgroundColor: AppColors.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.darkBorder),
          ),
          title: Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: AppColors.hongguoGold),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '播放调试日记',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, color: AppColors.whiteWithAlpha(0.7)),
                tooltip: '复制全部日记',
                onPressed: () => copyToClipboard(dialogContext),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: AppColors.whiteWithAlpha(0.7)),
                tooltip: '清空日记',
                onPressed: () => clear(),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(dialogContext).size.height * 0.65,
            child: AnimatedBuilder(
              animation: revision,
              builder: (context, _) {
                final list = entries;
                if (list.isEmpty) {
                  return const Center(
                    child: Text(
                      '暂无日记记录',
                      style: TextStyle(color: AppColors.textTertiaryDark),
                    ),
                  );
                }
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.blackWithAlpha(0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.whiteWithAlpha(0.08),
                    ),
                  ),
                  child: Scrollbar(
                    controller: scrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final item = list[list.length - 1 - index]; // 倒序显示最新
                        Color textColor = AppColors.textSecondaryDark;
                        final lower = item.toLowerCase();
                        if (lower.contains('err') ||
                            lower.contains('fail') ||
                            lower.contains('异常') ||
                            lower.contains('失败') ||
                            lower.contains('exception')) {
                          textColor = AppColors.error;
                        } else if (lower.contains('成功') ||
                            lower.contains('ok') ||
                            lower.contains('success')) {
                          textColor = AppColors.success;
                        } else if (lower.contains('open') ||
                            lower.contains('initialize') ||
                            lower.contains('play') ||
                            lower.contains('url')) {
                          textColor = AppColors.info;
                        } else if (lower.contains('warn') ||
                            lower.contains('403') ||
                            lower.contains('404')) {
                          textColor = AppColors.warning;
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: SelectableText(
                            item,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: textColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('一键复制'),
              onPressed: () => copyToClipboard(dialogContext),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
