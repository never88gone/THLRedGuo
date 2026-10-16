import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/dart_core_engine.dart';
import 'package:THLRedLook/core_bridge.dart';

void main() {
  test('测试搜索万妖图录并排查播放问题', () async {
    final jsFile = File('assets/sources/hongguo.js');
    final script = await jsFile.readAsString();
    final engine = DartCoreEngine.instance;
    await engine.dispatch({'action': 'initialize', 'directory': Directory.systemTemp.path});
    await engine.dispatch({'action': 'jsSource.saveAndLoad', 'script': script, 'fileName': 'hongguo.js'});
    await engine.dispatch({'action': 'jsSource.setActive', 'source': 'hongguo'});

    final repo = NativeRepository();

    print('=== 1. 执行搜索：万妖图录 ===');
    final catalog = await repo.catalog('hongguo', query: '万妖图录', page: 1);
    print('搜索到 ${catalog.items.length} 个结果:');
    for (final drama in catalog.items) {
      print('  - 剧名: ${drama.title}, id: ${drama.id}, sourceId: ${drama.sourceId}, episodes: ${drama.episodes}');
    }

    expect(catalog.items, isNotEmpty);

    for (final drama in catalog.items.take(2)) {
      print('\n=== 2. 获取详情: ${drama.title} ===');
      final detail = await repo.detail(drama);
      print('  剧集总数: ${detail.episodes.length}');
      if (detail.episodes.isEmpty) {
        print('  [警告] 没有集数！');
        continue;
      }

      print('  第1集: id=${detail.episodes.first.id}, raw=${detail.episodes.first.raw}');
      try {
        final plan = await repo.resolve(detail.drama, detail.episodes.first);
        print('  >>> 第1集取流结果: url=${plan.url}, headers=${plan.headers}');
      } catch (e, st) {
        print('  >>> [错误] 第1集取流失败: $e');
        print('  堆栈: $st');
      }

      if (detail.episodes.length > 1) {
        try {
          final plan2 = await repo.resolve(detail.drama, detail.episodes[1]);
          print('  >>> 第2集取流结果: url=${plan2.url}');
        } catch (e) {
          print('  >>> [错误] 第2集取流失败: $e');
        }
      }
    }
  });
}
