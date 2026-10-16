// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/models/catalog/models.dart';

void main() {
  test('验证多季切换及各种集数格式下的播放解析 100% 成功', () async {
    final jsFile = File('assets/sources/hongguo.js');
    final script = await jsFile.readAsString();
    final engine = DartCoreEngine.instance;
    await engine.dispatch({'action': 'initialize', 'directory': Directory.systemTemp.path});
    await engine.dispatch({'action': 'jsSource.saveAndLoad', 'script': script, 'fileName': 'hongguo.js'});
    await engine.dispatch({'action': 'jsSource.setActive', 'source': 'hongguo'});

    final repo = NativeRepository();

    // 1. 测试以往会导致 404 / 无法获取真实播放流的伪造格式
    const testSeriesId = '7648598645096320024';
    final mockDrama = Drama(
      id: 'hongguo:$testSeriesId',
      source: 'hongguo',
      sourceId: testSeriesId,
      title: '发配边关，罪妻开荒养出战神',
    );

    final testCases = [
      // 场景 A: 伪造集数第 1 集 (之前会拼成 /player/seriesId_1 导致 404)
      Episode({'id': '${testSeriesId}_1', 'title': '第 1 集', 'raw': '${testSeriesId}_1'}, 1),
      // 场景 B: 伪造集数第 2 集 (之前会由于没有 vid 导致 404)
      Episode({'id': '${testSeriesId}_2', 'title': '第 2 集', 'raw': '${testSeriesId}_2'}, 2),
      // 场景 C: 携带 /1 路径 (之前会拼成 /player/seriesId/1 导致 404)
      Episode({'id': 'https://hongguoduanju.com/player/$testSeriesId/1', 'title': '第 1 集', 'raw': 'https://hongguoduanju.com/player/$testSeriesId/1'}, 1),
      // 场景 D: 纯集数数字
      Episode({'id': '1', 'title': '第 1 集', 'raw': '1'}, 1),
      // 场景 E: 纯 seriesId
      Episode({'id': testSeriesId, 'title': '第 1 集', 'raw': testSeriesId}, 1),
    ];

    print('=== 开始测试格式兼容与容错 ===');
    for (var i = 0; i < testCases.length; i++) {
      final ep = testCases[i];
      print('测试用例 $i: raw=${ep.raw}');
      final plan = await repo.resolve(mockDrama, ep);
      expect(plan.url, isNotEmpty);
      expect(plan.url.startsWith('http'), isTrue);
      print('  -> 解析成功: ${plan.url}');
    }

    // 2. 真实多季剧集切换测试
    print('\n=== 开始测试真实多季剧集切换与各季解析 ===');
    final searchResult = await repo.catalog('hongguo', query: '战神', page: 1);
    for (final drama in searchResult.items) {
      final seasons = await discoverSeriesSeasons(anchor: drama, repository: repo);
      if (seasons.length > 1) {
        print('找到多季剧: ${drama.title} (共 ${seasons.length} 季)');
        for (final season in seasons.take(3)) {
          print('  -> 切换季: ${season.label} (${season.drama.title})');
          final detail = await repo.detail(season.drama);
          expect(detail.episodes, isNotEmpty);
          // 播放第 1 集
          final ep1 = detail.episodes.first;
          final plan1 = await repo.resolve(detail.drama, ep1);
          expect(plan1.url, isNotEmpty);
          print('     第1集播放成功: ${plan1.url}');

          // 播放第 2 集 (如果存在)
          if (detail.episodes.length > 1) {
            final ep2 = detail.episodes[1];
            final plan2 = await repo.resolve(detail.drama, ep2);
            expect(plan2.url, isNotEmpty);
            print('     第2集播放成功: ${plan2.url}');
          }
        }
        break;
      }
    }
  });
}
