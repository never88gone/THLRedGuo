import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:THLRedLook/core/diagnostics/diagnostic_log_exporter.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostic_runner.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/core/diagnostics/network_egress_lookup.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class SourceDiagnosticsPage extends StatefulWidget {
  const SourceDiagnosticsPage({super.key, this.diagnostics});
  final SourceDiagnostics? diagnostics;

  @override
  State<SourceDiagnosticsPage> createState() => _SourceDiagnosticsPageState();
}

class _SourceDiagnosticsPageState extends State<SourceDiagnosticsPage> {
  late final recorder = widget.diagnostics ?? SourceDiagnostics.shared;
  final runner = SourceDiagnosticRunner.shared;
  String version = '版本信息读取中';
  late final Future<void> _metadata;
  bool _exporting = false;
  late String sourceHash = () {
    try {
      final script = kPresetJsSources
          .firstWhere((s) => s.id == 'hongguo')
          .loadScriptSync();
      return sha256.convert(utf8.encode(script.trimRight())).toString();
    } catch (_) {
      return '--------';
    }
  }();

  @override
  void initState() {
    super.initState();
    _metadata = Future.wait<void>([
      _loadMetadata(),
      recorder.refreshNetworkEgress(),
    ]).then((_) {});
  }

  Future<void> _loadMetadata() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => version = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      if (mounted) {
        setState(() => version = '1.0.0（构建号读取失败）');
      }
    }

    try {
      final script = await kPresetJsSources
          .firstWhere((s) => s.id == 'hongguo')
          .loadScript();
      if (mounted) {
        setState(() {
          sourceHash = sha256
              .convert(utf8.encode(script.trimRight()))
              .toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _copy() async {
    await _metadata;
    await Clipboard.setData(
      ClipboardData(
        text: recorder.report(version: version, sourceHash: sourceHash),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制详细脱敏诊断报告')));
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await _metadata;
      final completed = await DiagnosticLogExporter.export(
        recorder.report(version: version, sourceHash: sourceHash),
      );
      if (mounted && completed) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已完成诊断日志导出')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日志导出失败，请重试；也可复制报告')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据源诊断'),
        actions: [
          IconButton(
            tooltip: '复制详细诊断报告',
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([recorder, runner]),
        builder: (context, _) {
          final entries = recorder.entries.reversed.toList();
          final failures = entries.where((e) => e.failed).toList();
          final successes = entries.where((e) => !e.failed).toList();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // 1. 顶部基础信息与指纹卡片
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceHighest
                      : colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? AppColors.whiteWithAlpha(0.08)
                        : colors.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.network_check_rounded,
                              color: AppColors.hongguoRed,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '红果官方数据源',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.hongguoRed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.hongguoRed.withValues(
                                alpha: 0.3,
                              ),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'SHA256 ${sourceHash.length >= 8 ? sourceHash.substring(0, 8) : sourceHash}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.hongguoRed,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '应用版本 $version · 保留最近 60 条脱敏记录。使用独立游客会话检查搜索、分页、详情与播放解析，不影响日常游客凭据。可导出日志文件或复制报告后手动反馈，不会自动上传。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      recorder.networkEgress?.summary ?? '出口 IP：正在检测…',
                      key: const ValueKey('source-diagnostics-egress'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${NetworkEgressResult.notice} 来源：${recorder.networkEgress?.provider ?? 'IP.SB / IPWho.is'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. 操作按钮行
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('source-diagnostics-run'),
                    onPressed: runner.running ? null : runner.run,
                    icon: runner.running
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(runner.running ? '检测中…' : '开始检测'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.hongguoRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('source-diagnostics-copy'),
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('复制报告'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('source-diagnostics-export'),
                    onPressed: _exporting ? null : _export,
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(_exporting ? '导出中…' : '导出日志'),
                  ),
                  TextButton.icon(
                    onPressed: runner.running ? null : recorder.clear,
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('清空诊断记录'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. 诊断状态横幅与线性进度条
              if (runner.running) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              Container(
                key: const ValueKey('source-diagnostics-result'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      runner.result.contains('失败') ||
                          runner.result.contains('未通过')
                      ? colors.errorContainer.withValues(alpha: 0.35)
                      : (runner.result.contains('完成') ||
                                runner.result.contains('通过')
                            ? Colors.green.withValues(alpha: 0.12)
                            : (isDark
                                  ? AppColors.darkSurfaceElevated
                                  : colors.surfaceContainerLow)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        runner.result.contains('失败') ||
                            runner.result.contains('未通过')
                        ? colors.error.withValues(alpha: 0.5)
                        : (runner.result.contains('完成') ||
                                  runner.result.contains('通过')
                              ? Colors.green.withValues(alpha: 0.4)
                              : colors.outlineVariant.withValues(alpha: 0.2)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      runner.result.contains('失败') ||
                              runner.result.contains('未通过')
                          ? Icons.error_rounded
                          : (runner.result.contains('完成') ||
                                    runner.result.contains('通过')
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded),
                      color:
                          runner.result.contains('失败') ||
                              runner.result.contains('未通过')
                          ? colors.error
                          : (runner.result.contains('完成') ||
                                    runner.result.contains('通过')
                                ? Colors.green
                                : colors.primary),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        runner.result,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color:
                              runner.result.contains('失败') ||
                                  runner.result.contains('未通过')
                              ? colors.error
                              : colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. 统计指标栏（当有记录时展示）
              if (entries.isNotEmpty) ...[
                Row(
                  children: [
                    _buildStatPill('总记录', '${entries.length}', colors.primary),
                    const SizedBox(width: 8),
                    _buildStatPill('正常', '${successes.length}', Colors.green),
                    const SizedBox(width: 8),
                    _buildStatPill(
                      '异常',
                      '${failures.length}',
                      failures.isNotEmpty ? colors.error : colors.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // 5. 详细记录列表
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: Text('暂无记录，请先复现问题或开始检测。')),
                ),
              for (final entry in entries) _buildDiagnosticCard(context, entry),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticCard(
    BuildContext context,
    SourceDiagnosticEntry entry,
  ) {
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
                ? const Color(0xFF281414)
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
                  color: isFailed ? colors.error : Colors.green,
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
                      ? const Color(0xFF1E0E0E)
                      : Colors.red.shade50.withValues(alpha: 0.7),
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
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '排查建议：${entry.advice}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.orange.shade200
                                    : Colors.brown.shade800,
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
