import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:THLRedLook/core/diagnostics/source_diagnostic_runner.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';

class SourceDiagnosticsPage extends StatefulWidget {
  const SourceDiagnosticsPage({super.key});

  @override
  State<SourceDiagnosticsPage> createState() => _SourceDiagnosticsPageState();
}

class _SourceDiagnosticsPageState extends State<SourceDiagnosticsPage> {
  final recorder = SourceDiagnostics.shared;
  final runner = SourceDiagnosticRunner.shared;
  String version = '版本信息读取中';
  late final sourceHash = sha256
      .convert(
        utf8.encode(
          kPresetJsSources
              .firstWhere((s) => s.id == 'hongguo')
              .script
              .trimRight(),
        ),
      )
      .toString();

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
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
  }

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(
        text: recorder.report(version: version, sourceHash: sourceHash),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制脱敏诊断报告')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('数据源诊断')),
    body: AnimatedBuilder(
      animation: Listenable.merge([recorder, runner]),
      builder: (context, _) {
        final entries = recorder.entries.reversed.toList();
        final failures = entries.where((e) => e.failed && e.host.isNotEmpty);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('红果官方数据源', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('应用 $version · 源指纹 ${sourceHash.substring(0, 12)}'),
            const SizedBox(height: 12),
            const Text(
              '保留最近 60 条脱敏记录。主动检测使用独立游客会话检查注册、搜索、分页和详情，不读取图片或视频，不影响收藏、历史和当前数据源。报告仅保留在本次应用进程中，由你手动复制反馈。',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const ValueKey('source-diagnostics-run'),
                  onPressed: runner.running ? null : runner.run,
                  icon: const Icon(Icons.network_check),
                  label: Text(runner.running ? '检测中…' : '开始检测'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('source-diagnostics-copy'),
                  onPressed: _copy,
                  icon: const Icon(Icons.copy),
                  label: const Text('复制报告'),
                ),
                TextButton(
                  onPressed: runner.running ? null : recorder.clear,
                  child: const Text('清空诊断记录'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              runner.result,
              key: const ValueKey('source-diagnostics-result'),
            ),
            if (runner.running) const LinearProgressIndicator(),
            if (failures.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(SourceDiagnostics.advice(failures.first)),
              ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('暂无记录，请先复现问题或开始检测。'),
              ),
            for (final entry in entries)
              Card(
                child: ListTile(
                  leading: Icon(
                    entry.failed
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    color: entry.failed
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  title: Text(entry.stage),
                  subtitle: SelectableText(entry.text),
                ),
              ),
          ],
        );
      },
    ),
  );
}
