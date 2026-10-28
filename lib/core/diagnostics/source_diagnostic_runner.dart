import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';
import 'source_diagnostics.dart';

class SourceDiagnosticRunner extends ChangeNotifier {
  static final shared = SourceDiagnosticRunner();
  SourceDiagnosticRunner({
    this.diagnostics,
    this.runtimeFactory,
    this.scriptLoader,
  });
  final SourceDiagnostics? diagnostics;
  final CatPawJsRuntime Function(SourceDiagnostics, String)? runtimeFactory;
  final Future<String> Function()? scriptLoader;
  bool running = false;
  String result = '尚未检测';
  int successCount = 0;
  int failureCount = 0;

  Future<void> run() async {
    if (running) return;
    running = true;
    successCount = 0;
    failureCount = 0;
    result = '正在执行网络连接、JS引擎、搜索、详情与播放解析全链路诊断…';
    notifyListeners();

    final recorder = diagnostics ?? SourceDiagnostics.shared;
    final network = recorder.refreshNetworkEgress(force: true);
    final context = '主动检测 ${DateTime.now().toUtc().toIso8601String()}';
    final runtime =
        runtimeFactory?.call(recorder, context) ??
        CatPawJsRuntime(null, recorder, context, false);

    var currentStage = 'JS 脚本与引擎初始化';
    final stopwatch = Stopwatch()..start();

    try {
      // 1. JS 脚本加载与引擎初始化
      currentStage = 'JS 脚本与引擎初始化';
      stopwatch.reset();
      stopwatch.start();
      final script =
          await (scriptLoader?.call() ??
              kPresetJsSources
                  .firstWhere((s) => s.id == 'hongguo')
                  .loadScript());
      await runtime.init(script);
      successCount++;
      recorder.add(
        SourceDiagnosticEntry(
          at: DateTime.now().toUtc(),
          context: context,
          stage: currentStage,
          elapsedMs: stopwatch.elapsedMilliseconds,
          count: 1,
        ),
      );

      // 2. 搜索第一页探测
      currentStage = '短剧搜索与检索';
      stopwatch.reset();
      stopwatch.start();
      final first = await runtime.search('短剧');
      if (first.list.isEmpty) {
        throw const CatPawSourceFailure(
          '诊断搜索未取得短剧样本，尚未验证分页、详情与播放解析',
          code: 'SEARCH_EMPTY',
        );
      }
      successCount++;
      recorder.add(
        SourceDiagnosticEntry(
          at: DateTime.now().toUtc(),
          context: context,
          stage: currentStage,
          elapsedMs: stopwatch.elapsedMilliseconds,
          count: first.list.length,
        ),
      );

      // 3. 搜索分页探测（若支持分页）
      if (first.hasMore) {
        currentStage = '搜索分页与游标';
        stopwatch.reset();
        stopwatch.start();
        final next = await runtime.search('短剧', page: 2);
        successCount++;
        recorder.add(
          SourceDiagnosticEntry(
            at: DateTime.now().toUtc(),
            context: context,
            stage: currentStage,
            elapsedMs: stopwatch.elapsedMilliseconds,
            count: next.list.length,
          ),
        );
      }

      // 4. 详情与分集数据探测
      CatPawDetailResult? detailResult;
      String sampleVodId = '';
      if (first.list.isNotEmpty) {
        currentStage = '剧集详情与分集解析';
        stopwatch.reset();
        stopwatch.start();

        // 优先筛选标注有完整集数的短剧作为健康探测样本
        final candidates = <String>[];
        for (final item in first.list) {
          final id = item['vod_id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final total = (item['vod_total'] as num?)?.toInt() ?? 0;
          final remarks = item['vod_remarks']?.toString() ?? '';
          if (total > 0 || (remarks.contains('集') && !remarks.contains('0集'))) {
            candidates.add(id);
          }
        }
        if (candidates.isEmpty) {
          for (final item in first.list) {
            final id = item['vod_id']?.toString() ?? '';
            if (id.isNotEmpty) candidates.add(id);
          }
        }

        CatPawSourceFailure? lastFailure;
        for (final candId in candidates.take(3)) {
          try {
            final res = await runtime.detail(candId);
            final playUrl = res.vod['vod_play_url']?.toString() ?? '';
            if (playUrl.isNotEmpty) {
              detailResult = res;
              sampleVodId = candId;
              break;
            }
          } catch (e) {
            if (e is CatPawSourceFailure) {
              lastFailure = e;
            }
          }
        }

        if (detailResult == null) {
          throw lastFailure ??
              const CatPawSourceFailure(
                '剧集详情返回的数据中缺少分集播放列表 (vod_play_url 为空)',
                code: 'MISSING_EPISODE',
              );
        }

        successCount++;
        recorder.add(
          SourceDiagnosticEntry(
            at: DateTime.now().toUtc(),
            context: context,
            stage: currentStage,
            elapsedMs: stopwatch.elapsedMilliseconds,
            count: 1,
          ),
        );
      }

      // 5. 播放流解析探针测试
      if (detailResult != null && sampleVodId.isNotEmpty) {
        final playUrl = detailResult.vod['vod_play_url']?.toString() ?? '';
        // 尝试提取第一集的播放标识
        final parts = playUrl.split('#');
        if (parts.isNotEmpty) {
          final firstEpisode = parts.first;
          final segs = firstEpisode.split(r'$');
          final episodeId = segs.length > 1 ? segs[1] : segs[0];
          if (episodeId.isNotEmpty) {
            currentStage = '播放流媒体解析探针';
            stopwatch.reset();
            stopwatch.start();
            final playResult = await runtime.play('play', episodeId);
            if (playResult.url.isEmpty) {
              throw const CatPawSourceFailure(
                '站源播放接口未能成功解析出有效媒体流播放地址',
                code: 'NO_STREAM_URL',
              );
            }
            successCount++;
            recorder.add(
              SourceDiagnosticEntry(
                at: DateTime.now().toUtc(),
                context: context,
                stage: currentStage,
                elapsedMs: stopwatch.elapsedMilliseconds,
                count: 1,
              ),
            );
          }
        }
      }

      result = '检测完成：脚本、搜索${first.hasMore ? '、分页' : ''}、详情、播放解析通过';
    } catch (error) {
      failureCount++;
      final analysis = SourceDiagnostics.analyzeError(error);
      recorder.add(
        SourceDiagnosticEntry(
          at: DateTime.now().toUtc(),
          context: context,
          stage: currentStage,
          elapsedMs: stopwatch.elapsedMilliseconds,
          errorCategory: analysis.category,
          errorTitle: analysis.title,
          errorMessage: analysis.message,
          advice: analysis.advice,
          errorCode: analysis.code,
        ),
      );
      result =
          '检测失败：【$currentStage】阶段发生【${analysis.title}】\n失败原因：${analysis.message}';
    } finally {
      await network;
      runtime.dispose();
      running = false;
      notifyListeners();
    }
  }
}
