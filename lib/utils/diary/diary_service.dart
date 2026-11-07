import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/core/player/playback_diagnostics.dart';

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

  /// 在界面上弹出交互式日记弹窗（兼容 TV 遥控器与手机触屏，支持实时诊断数据面板）
  static Future<void> showDiaryDialog(
    BuildContext context, {
    Future<PlaybackTechnicalDiagnostics?> Function()? fetchDiagnostics,
  }) {
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
            height: MediaQuery.of(dialogContext).size.height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (fetchDiagnostics != null)
                  FutureBuilder<PlaybackTechnicalDiagnostics?>(
                    future: fetchDiagnostics(),
                    builder: (context, snapshot) {
                      final diag = snapshot.data;
                      if (diag == null) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.darkCard,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.hongguoRed.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.speed_rounded,
                                  size: 16,
                                  color: AppColors.hongguoGold,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '实时核心技术指标',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.white,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {
                                    DiaryService.add(diag.toDiaryLog());
                                    ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                                      const SnackBar(
                                        content: Text('已将诊断快照写入日记'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.whiteWithAlpha(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '记录快照',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                _DiagBadge(label: '引擎', value: diag.playerEngine),
                                _DiagBadge(
                                  label: '解码',
                                  value:
                                      '${diag.decoderName} (${diag.isHardwareAccelerated ? "硬解生效" : "软解"})',
                                  highlight: diag.isHardwareAccelerated,
                                ),
                                _DiagBadge(
                                  label: '画面',
                                  value:
                                      '${diag.videoSizeText} @ ${diag.fps != null && diag.fps! > 0 ? "${diag.fps!.toStringAsFixed(1)}fps" : "未知"}',
                                ),
                                _DiagBadge(
                                  label: '呈现掉帧',
                                  value: '${diag.droppedFrames} 帧',
                                  isWarn: diag.droppedFrames > 20,
                                ),
                                _DiagBadge(
                                  label: '缓冲健康',
                                  value:
                                      '${(diag.bufferDuration.inMilliseconds / 1000).toStringAsFixed(1)}s (卡顿: ${diag.bufferingEventsCount}次)',
                                  isWarn: diag.bufferingEventsCount > 0,
                                ),
                                _DiagBadge(
                                  label: '清晰度对应',
                                  value: diag.qualityMatchSummary,
                                ),
                                _DiagBadge(
                                  label: '流媒体',
                                  value:
                                      '${diag.isEncrypted ? "AES-128加密" : "明文"} (host: ${diag.mediaHost ?? "未知"})',
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                Expanded(
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
        ],
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

class _DiagBadge extends StatelessWidget {
  const _DiagBadge({
    required this.label,
    required this.value,
    this.highlight = false,
    this.isWarn = false,
  });

  final String label;
  final String value;
  final bool highlight;
  final bool isWarn;

  @override
  Widget build(BuildContext context) {
    Color bg = AppColors.white.withValues(alpha: 0.06);
    Color fg = AppColors.white.withValues(alpha: 0.85);
    Color labelColor = AppColors.white.withValues(alpha: 0.5);

    if (highlight) {
      bg = AppColors.hongguoGold.withValues(alpha: 0.15);
      fg = AppColors.hongguoGold;
      labelColor = AppColors.hongguoGold.withValues(alpha: 0.7);
    } else if (isWarn) {
      bg = AppColors.warning.withValues(alpha: 0.15);
      fg = AppColors.warning;
      labelColor = AppColors.warning.withValues(alpha: 0.7);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight || isWarn
              ? fg.withValues(alpha: 0.3)
              : AppColors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: labelColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
