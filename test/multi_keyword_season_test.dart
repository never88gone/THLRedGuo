// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';

void main() {
  test('查找并测试各类多季短剧播放', () async {
    final jsFile = File('assets/sources/hongguo.js');
    final script = await jsFile.readAsString();
    final engine = DartCoreEngine.instance;
    await engine.dispatch({'action': 'initialize', 'directory': Directory.systemTemp.path});
    await engine.dispatch({'action': 'jsSource.saveAndLoad', 'script': script, 'fileName': 'hongguo.js'});
    await engine.dispatch({'action': 'jsSource.setActive', 'source': 'hongguo'});

    final repo = NativeRepository();

    // 测试几个常见关键词
    final keywords = ['战神', '离婚', '归来', '神豪', '千金', '天下', '无双'];
    for (final kw in keywords) {
      final res = await repo.catalog('hongguo', query: kw, page: 1);
      for (final drama in res.items) {
        final seasons = await discoverSeriesSeasons(anchor: drama, repository: repo);
        if (seasons.length > 1) {
          print('\n======================================================');
          print('关键词 [$kw] 发现多季: ${drama.title} (共 ${seasons.length} 季)');
          for (final s in seasons) {
            final detail = await repo.detail(s.drama);
            print('  季 [${s.label}]: ${s.drama.title}');
            print('    id=${s.drama.id}, sourceId=${s.drama.sourceId}');
            print('    episodes=${detail.episodes.length}');
            if (detail.episodes.isNotEmpty) {
              final ep = detail.episodes.first;
              print('    ep1 id=${ep.id}, raw=${ep.raw}');
              try {
                final plan = await repo.resolve(detail.drama, ep);
                print('    >>> 播放解析成功: ${plan.url.substring(0, 40)}...');
              } catch (e) {
                print('    >>> 播放解析【失败】: $e');
              }
            } else {
              print('    >>> 集数为空！');
            }
          }
          return; // 只看第一个多季
        }
      }
    }
  });
}
