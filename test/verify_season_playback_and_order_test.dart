import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';
import 'package:THLRedLook/models/catalog/models.dart';

void main() {
  test('验证多季短剧切季播放流解析与次序恒定', () async {
    final jsFile = File('assets/sources/hongguo.js');
    final script = await jsFile.readAsString();
    final engine = DartCoreEngine.instance;
    await engine.dispatch({'action': 'initialize', 'directory': Directory.systemTemp.path});
    await engine.dispatch({'action': 'jsSource.saveAndLoad', 'script': script, 'fileName': 'hongguo.js'});
    await engine.dispatch({'action': 'jsSource.setActive', 'source': 'hongguo'});

    final repo = NativeRepository();

    // 1. 搜索万妖图录
    final catalog = await repo.catalog('hongguo', query: '万妖图录', page: 1);
    expect(catalog.items, isNotEmpty);

    // 2. 以第 1 个剧为基准计算系列季列表
    final baseEntries = hongguoSeriesEntries(catalog.items.first, catalog.items);
    expect(baseEntries.length, greaterThan(1));

    // 确保季号唯一且严格升序
    final seasons = baseEntries.map((e) => e.season).toList();
    expect(seasons.toSet().length, equals(baseEntries.length), reason: '季号必须完全唯一，不允许重复第1季');
    for (var i = 0; i < seasons.length - 1; i++) {
      expect(seasons[i], lessThan(seasons[i + 1]), reason: '季列表必须严格升序');
    }

    // 3. 验证以每一季作为 anchor 时，计算出的季列表次序和条目必须完全一致
    for (final entry in baseEntries) {
      final entriesWithNewAnchor = hongguoSeriesEntries(
        entry.drama,
        catalog.items,
        lockedEntries: baseEntries,
      );
      final newSeasons = entriesWithNewAnchor.map((e) => e.season).toList();
      expect(newSeasons, equals(seasons), reason: '切换到 ${entry.drama.title} 后，季次序必须与基准严格一致');
    }

    // 4. 验证每一季的第 1 集和第 2 集均能成功获取真实播放流，绝不报错
    for (final entry in baseEntries.take(3)) {
      final detail = await repo.detail(entry.drama);
      expect(detail.episodes, isNotEmpty, reason: '${entry.drama.title} 必须能成功获取分集');
      
      // 测试第 1 集
      final planEp1 = await repo.resolve(entry.drama, detail.episodes.first, quality: 0);
      expect(planEp1.url, isNotEmpty, reason: '${entry.drama.title} 第1集播放流解析失败');
      expect(planEp1.url.startsWith('http'), isTrue);

      // 如果有第 2 集，测试第 2 集
      if (detail.episodes.length > 1) {
        final planEp2 = await repo.resolve(entry.drama, detail.episodes[1], quality: 0);
        expect(planEp2.url, isNotEmpty, reason: '${entry.drama.title} 第2集播放流解析失败');
        expect(planEp2.url.startsWith('http'), isTrue);
      }
    }

    // 5. 验证大整数ID精度保护与历史损坏ID自愈
    final corruptedEp = Episode(
      {
        'id': 'https://hongguoduanju.com/player/${catalog.items.first.cleanSourceId}/7621226646028160000',
        'title': '第 1 集',
        'currentEpisode': 1,
      },
      1,
    );
    final selfHealedPlan = await repo.resolve(catalog.items.first, corruptedEp, quality: 0);
    expect(selfHealedPlan.url, isNotEmpty);
    expect(selfHealedPlan.url.endsWith('000/360p.mp4'), isFalse, reason: '必须自愈提取真实有效vid，绝不可返回末尾000的404直链');
  });
}
