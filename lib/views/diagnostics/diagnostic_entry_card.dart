import 'package:flutter/material.dart';

import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 诊断记录明细展示卡片组件
class DiagnosticEntryCard extends StatelessWidget {
  const DiagnosticEntryCard({
    super.key,
    required this.entry,
  });

  final SourceDiagnosticEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isFailed = entry.failed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isFailed
              ? colors.error.withValues(alpha: 0.4)
              : (isDark
                    ? AppColors.whiteWithAlpha(0.06)
                    : colors.outlineVariant.withValues(alpha: 0.3)),
          width: isFailed ? 1.0 : 0.8,
        ),
      ),
      color: isFailed
          ? (isDark
                ? AppColors.diagnosticErrorDark
                : colors.errorContainer.withValues(alpha: 0.2))
          : (isDark ? AppColors.darkSurfaceElevated : colors.surface),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行：阶段名称 + 状态/错误标签 + 耗时
            Row(
              children: [
                Icon(
                  isFailed ? Icons.error_rounded : Icons.check_circle_rounded,
                  color: isFailed ? colors.error : AppColors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.stage,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (isFailed && entry.displayTitle.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: colors.error.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      entry.displayTitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colors.error,
                      ),
                    ),
                  ),
                if (entry.elapsedMs > 0)
                  Text(
                    '${entry.elapsedMs}ms',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),

            // 失败详情分析面板
            if (isFailed) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.diagnosticErrorDeeper
                      : AppColors.redShade50.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.error.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.errorMessage.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: colors.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '失败原因：${entry.errorMessage}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.error,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (entry.advice.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 16,
                            color: AppColors.orange,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '排查建议：${entry.advice}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.orangeShade200
                                    : AppColors.brownShade800,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (entry.searchTabsSummary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '分类: ${entry.searchTabsSummary}',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
            if (entry.logId.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(
                'LogID: ${entry.logId}',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
            // 底部元信息行（主机、状态码、时间戳等）
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (entry.host.isNotEmpty)
                  Text(
                    '主机: ${entry.host}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (entry.status > 0)
                  Text(
                    'HTTP: ${entry.status}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (entry.count != null)
                  Text(
                    '${entry.count} 条数据',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                Text(
                  entry.at.toLocal().toString().split('.').first,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
