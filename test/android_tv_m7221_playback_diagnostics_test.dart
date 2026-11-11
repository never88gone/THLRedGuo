import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:THLRedLook/core/player/playback_diagnostics.dart';
import 'package:THLRedLook/views/television/television_controls.dart';
import 'package:THLRedLook/views/danmaku/danmaku_overlay.dart';
import 'package:THLRedLook/models/danmaku/danmaku_models.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Issue #8: PlaybackTechnicalDiagnostics 核心技术指标', () {
    test('生成单行日记日志与完整多行报告格式正确', () {
      final diag = PlaybackTechnicalDiagnostics(
        playerEngine: 'MediaKit (libmpv)',
        decoderName: 'hevc (mediacodec)',
        isHardwareAccelerated: true,
        videoWidth: 1920,
        videoHeight: 1080,
        fps: 25.0,
        droppedFrames: 3,
        bufferDuration: const Duration(seconds: 15, milliseconds: 200),
        bufferingEventsCount: 1,
        requestedQuality: 720,
        actualQuality: 1080,
        availableQualities: const [1080],
        isEncrypted: true,
        mediaHost: 'douyinvod.com',
        timestamp: DateTime(2026, 11, 7, 16, 0),
      );

      final log = diag.toDiaryLog();
      expect(log, contains('[Diag] 后端=MediaKit (libmpv)'));
      expect(log, contains('解码=hevc (mediacodec) (硬解生效)'));
      expect(log, contains('画面=1920x1080@25.0fps'));
      expect(log, contains('掉帧=3'));
      expect(log, contains('缓冲=15.2s(卡顿1次)'));
      expect(log, contains('720P -> 降档/自动匹配至 1080P'));
      expect(log, contains('流=加密(host=douyinvod.com)'));

      final report = diag.toFormattedReport();
      expect(report, contains('【播放实时技术指标与硬件诊断】'));
      expect(report, contains('• 播放器引擎: MediaKit (libmpv)'));
      expect(report, contains('• 实际视频尺寸: 1920x1080'));
      expect(report, contains('• 画面帧率: 25.0 fps'));
      expect(report, contains('• 呈现丢帧统计: 3 帧'));
      expect(report, contains('• 清晰度对应: 720P -> 降档/自动匹配至 1080P (当前集提供: 1080P)'));
      expect(report, contains('DRM/AES-128加密流'));
    });

    test('当请求清晰度与实际清晰度完全一致时说明正确', () {
      const diag = PlaybackTechnicalDiagnostics(
        playerEngine: 'MediaKit (libmpv)',
        decoderName: 'hevc (mediacodec)',
        isHardwareAccelerated: true,
        videoWidth: 1280,
        videoHeight: 720,
        fps: 25.0,
        requestedQuality: 720,
        actualQuality: 720,
        availableQualities: [720, 1080],
      );

      expect(diag.qualityMatchSummary, '720P (请求: 720P)');
    });
  });

  group('Issue #8: 电视端清晰度跨集匹配与状态展示', () {
    testWidgets('当请求 720P 但当前集仅有 1080P 时，提示自动匹配并保留 720P 偏好高亮', (tester) async {
      TelevisionPlaybackSetting? selectedSetting;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedSetting = await showDialog<TelevisionPlaybackSetting>(
                    context: context,
                    builder: (_) => const TelevisionSettingsDialog(
                      speed: 1.0,
                      quality: 720,
                      qualities: [1080],
                      actualQuality: 1080,
                      favorite: false,
                      onFavorite: _noop,
                    ),
                  );
                },
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();

      // 验证提示文本与选项
      expect(find.text('当前集未提供 720P，已自动匹配 1080P'), findsOneWidget);
      expect(find.text('1080P (当前匹配)'), findsOneWidget);
      expect(find.text('720P (偏好锁定)'), findsOneWidget);

      // 点击 1080P
      await tester.tap(find.text('1080P (当前匹配)'));
      await tester.pumpAndSettle();

      expect(selectedSetting, isNotNull);
      expect(selectedSetting!.quality, 1080);
    });
  });

  group('Issue #8: 电视大屏弹幕渲染开销优化', () {
    test('大屏下 (width > 800) 同屏活跃并发数上限被限制为 18', () {
      final items = List<DanmakuItem>.generate(
        50,
        (i) => DanmakuItem(
          id: 'item_$i',
          text: '弹幕测试 $i',
          timeMs: 1000 + i * 50,
        ),
      );

      final flights = planDanmaku(
        items,
        width: 1920,
        rows: 5,
        measure: (text) => text.length * 20.0,
      );

      // 大屏同屏并发被平滑限制在 18 以内，避免老电视 CPU/GPU 拥塞
      expect(flights.length, inInclusiveRange(1, 18));
    });
  });

  group('Issue #8: 播放日记弹窗集成实时技术指标看板', () {
    testWidgets('DiaryService.showDiaryDialog 包含技术指标看板并可记录快照', (tester) async {
      DiaryService.clear();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DiaryService.showDiaryDialog(
                  context,
                  fetchDiagnostics: () async => const PlaybackTechnicalDiagnostics(
                    playerEngine: 'MediaKit (libmpv)',
                    decoderName: 'hevc (mediacodec)',
                    isHardwareAccelerated: true,
                    videoWidth: 1920,
                    videoHeight: 1080,
                    fps: 25.0,
                    droppedFrames: 0,
                    bufferDuration: Duration(seconds: 12),
                    bufferingEventsCount: 0,
                    requestedQuality: 720,
                    actualQuality: 1080,
                    availableQualities: [1080],
                  ),
                ),
                child: const Text('打开日记'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开日记'));
      await tester.pumpAndSettle();

      // 验证实时核心技术指标面板渲染
      expect(find.text('实时核心技术指标'), findsOneWidget);
      expect(find.text('MediaKit (libmpv)'), findsOneWidget);
      expect(find.text('1920x1080 @ 25.0fps'), findsOneWidget);
      expect(find.text('0 帧'), findsOneWidget);

      // 点击记录快照
      await tester.tap(find.text('记录快照'));
      await tester.pump();

      // 验证已存入 entries
      expect(DiaryService.entries.isNotEmpty, isTrue);
      expect(DiaryService.entries.last, contains('[Diag] 后端=MediaKit (libmpv)'));
    });
  });
}

void _noop() {}
