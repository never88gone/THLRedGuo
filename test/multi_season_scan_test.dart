// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';

void main() {
  test('扫描首页和分类短剧测试多季切换', () async {
    final jsFile = File('assets/sources/hongguo.js');
    final script = await jsFile.readAsString();
    final engine = DartCoreEngine.instance;
    await engine.dispatch({'action': 'initialize', 'directory': Directory.systemTemp.path});
    await engine.dispatch({'action': 'jsSource.saveAndLoad', 'script': script, 'fileName': 'hongguo.js'});
    await engine.dispatch({'action': 'jsSource.setActive', 'source': 'hongguo'});

    final repo = NativeRepository();

    // 扫描 real-drama
    final catPage = await repo.catalog('hongguo', category: 'real-drama', page: 1);
    print('分类获取到 ${catPage.items.length} 部剧');
    
    int testedCount = 0;
    for (final drama in catPage.items) {
      final seasons = await discoverSeriesSeasons(anchor: drama, repository: repo);
      if (seasons.length > 1) {
        testedCount++;
        print('\n----------------------------------------');
        print('发现多季剧集: ${drama.title} (共 ${seasons.length} 季)');
        for (final s in seasons) {
          final detail = await repo.detail(s.drama);
          print('  [${s.label}] ${s.drama.title} (id: ${s.drama.id}): 集数 = ${detail.episodes.length}');
          if (detail.episodes.isEmpty) {
            print('  >>> 发现无集数异常！<<<');
          }
        }
      }
      if (testedCount >= 3) break;
    }
  });
}
