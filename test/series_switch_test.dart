// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/models/catalog/models.dart';

void main() {
  setUpAll(() async {
    final jsFile = File('assets/sources/hongguo.js');
    final script = await jsFile.readAsString();
    final engine = DartCoreEngine.instance;
    await engine.dispatch({'action': 'initialize', 'directory': Directory.systemTemp.path});
    await engine.dispatch({'action': 'jsSource.saveAndLoad', 'script': script, 'fileName': 'hongguo.js'});
    await engine.dispatch({'action': 'jsSource.setActive', 'source': 'hongguo'});
  });

  test('Drama.fromJson 能够自动清洗带前缀和为空的 sourceId', () {
    final d1 = Drama.fromJson({
      'id': 'hongguo:7648598645096320024',
      'source': 'hongguo',
      'sourceId': 'hongguo:7648598645096320024',
      'title': '测试剧集1',
    });
    expect(d1.sourceId, '7648598645096320024');
    expect(d1.cleanSourceId, '7648598645096320024');

    final d2 = Drama.fromJson({
      'id': 'hongguo:7648598645096320024',
      'source': 'hongguo',
      'sourceId': '',
      'title': '测试剧集2',
    });
    expect(d2.sourceId, '7648598645096320024');
    expect(d2.cleanSourceId, '7648598645096320024');

    final d3 = Drama(
      id: 'hongguo:7648598645096320024',
      source: 'hongguo',
      sourceId: 'hongguo:7648598645096320024',
      title: '直接构造带前缀',
    );
    expect(d3.cleanSourceId, '7648598645096320024');
  });

  test('带前缀或空 sourceId 时 NativeRepository.detail 均能正确获取集数', () async {
    final repo = NativeRepository();

    // 1. 模拟带前缀 sourceId
    final dramaWithPrefix = Drama(
      id: 'hongguo:7648598645096320024',
      source: 'hongguo',
      sourceId: 'hongguo:7648598645096320024',
      title: '发配边关，罪妻开荒养出战神',
    );

    final detail1 = await repo.detail(dramaWithPrefix);
    expect(detail1.episodes.isNotEmpty, isTrue);
    expect(detail1.episodes.length, greaterThanOrEqualTo(50));

    // 2. 模拟空 sourceId
    final dramaWithEmpty = Drama(
      id: 'hongguo:7648598645096320024',
      source: 'hongguo',
      sourceId: '',
      title: '发配边关，罪妻开荒养出战神',
    );

    final detail2 = await repo.detail(dramaWithEmpty);
    expect(detail2.episodes.isNotEmpty, isTrue);
    expect(detail2.episodes.length, greaterThanOrEqualTo(50));

    // 3. 验证播放解析
    print('episode raw: ${detail1.episodes.first.raw}');
    final playbackRes = await repo.resolve(
      detail1.drama,
      detail1.episodes.first,
    );
    print('playbackRes url: ${playbackRes.url}');
    expect(playbackRes.url.isNotEmpty, isTrue);
  });

  test('网络接口无返回或空剧集时，根据已知集数兜底绝不抛出 Cannot add to an unmodifiable list', () async {
    final repo = NativeRepository();
    final mockSeasonDrama = Drama(
      id: 'hongguo:9999999999999999999',
      source: 'hongguo',
      sourceId: '9999999999999999999',
      title: '假定网络异常或暂无播放列表的第2季',
      episodes: 80, // 已知有80集
    );

    // 以前这里会抛出 Cannot add to an unmodifiable list
    final detail = await repo.detail(mockSeasonDrama);
    expect(detail.episodes.length, 80);
    expect(detail.episodes.first.number, 1);
    expect(detail.episodes.last.number, 80);
    expect(detail.episodes.first.title, '第 1 集');
  });
}
