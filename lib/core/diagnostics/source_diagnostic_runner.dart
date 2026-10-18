import 'package:flutter/foundation.dart';

import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';
import 'source_diagnostics.dart';

class SourceDiagnosticRunner extends ChangeNotifier {
  static final shared = SourceDiagnosticRunner();
  bool running = false;
  String result = '尚未检测';

  Future<void> run() async {
    if (running) return;
    running = true;
    result = '正在检查游客注册、搜索、分页和详情…';
    notifyListeners();
    final recorder = SourceDiagnostics.shared;
    final context = '主动检测 ${DateTime.now().toUtc().toIso8601String()}';
    final runtime = CatPawJsRuntime(null, recorder, context);
    var stage = '初始化';
    try {
      await runtime.init(
        kPresetJsSources.firstWhere((s) => s.id == 'hongguo').script,
      );
      stage = '搜索第一页';
      final first = await runtime.search('短剧');
      recorder.add(
        SourceDiagnosticEntry(
          at: DateTime.now().toUtc(),
          context: context,
          stage: stage,
          count: first.list.length,
        ),
      );
      if (first.hasMore) {
        stage = '搜索分页';
        final next = await runtime.search('短剧', page: 2);
        recorder.add(
          SourceDiagnosticEntry(
            at: DateTime.now().toUtc(),
            context: context,
            stage: stage,
            count: next.list.length,
          ),
        );
      }
      if (first.list.isNotEmpty) {
        stage = '详情解析';
        final id = first.list.first['vod_id']?.toString() ?? '';
        final detail = await runtime.detail(id);
        if ((detail.vod['vod_play_url']?.toString() ?? '').isEmpty) {
          throw const CatPawSourceFailure('详情缺少分集', code: 'MISSING_EPISODE');
        }
      }
      result =
          '检测完成：注册、搜索${first.hasMore ? '、分页' : ''}${first.list.isNotEmpty ? '、详情' : '（无结果）'}通过';
    } catch (error) {
      final code = error is CatPawSourceFailure
          ? SourceDiagnostics.safeCode(error.code)
          : 'DIAGNOSTIC_FAILED';
      recorder.add(
        SourceDiagnosticEntry(
          at: DateTime.now().toUtc(),
          context: context,
          stage: stage,
          errorCode: code.isEmpty ? 'DIAGNOSTIC_FAILED' : code,
        ),
      );
      result = '检测失败：$stage，请查看下方记录';
    } finally {
      runtime.dispose();
      running = false;
      notifyListeners();
    }
  }
}
