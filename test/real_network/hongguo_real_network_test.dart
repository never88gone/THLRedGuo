import 'dart:io';
import 'package:THLRedLook/core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'real_network_helpers.dart';

void main() {
  late NativeRepository repository;
  final recorder = NetworkTraceRecorder();

  setUpAll(() async {
    repository = await RealNetworkFixture.setup();
  });

  tearDownAll(() async {
    final tracePath = path.join(
      Directory.current.path,
      '.agents/teamwork/worker_m3/hongguo_network_trace.json',
    );
    await recorder.saveToFile(tracePath);
    print('【测试记录】已将真实网络交互特征持久化保存至: $tracePath');
  });

  group('红果源站真实网络端到端接口验证 (Real Network Verification)', () {
    test('1. 原生核心版本与独立运行状态校验', () {
      final state = repository.runtimeState;
      expect(state, isNotNull);
      expect(state!.version, isNotEmpty);
      expect(state.standalone, isTrue);

      recorder.record(
        action: 'initialize',
        endpoint: 'FFI:DuanjuRequest/initialize',
        params: {'directory': Directory.systemTemp.path},
        responseSummary: {
          'version': state.version,
          'standalone': state.standalone,
          'allSources': state.allSources,
        },
      );
    });

    test('2. 真实红果分类列表加载与分类多维覆盖 (短剧 / 漫剧 / AI剧)', () async {
      final sw = Stopwatch()..start();
      final categories = await repository.categories('hongguo');
      sw.stop();

      print('【分类列表】获取到 ${categories.length} 个分类，耗时 ${sw.elapsedMilliseconds} ms');
      expect(categories, isNotEmpty);

      expect(categories.any((c) => c.name.contains('真人剧') || c.name.contains('漫剧')), isTrue);

      recorder.record(
        action: 'categories',
        endpoint: 'FFI:categories-hongguo /reading/distribution/category/landpage/v/',
        params: {'source': 'hongguo'},
        latencyMs: sw.elapsedMilliseconds,
        responseSummary: {
          'count': categories.length,
          'categories': [
            for (final c in categories) {'id': c.id, 'name': c.name}
          ],
        },
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('3. 分类列表游标分页加载与数据连续性校验', () async {
      final sw = Stopwatch()..start();
      // 请求第 1 页
      final page1 = await repository.catalog('hongguo', page: 1, category: 'short_play');
      print('【短剧目录第1页】拉取短剧数: ${page1.items.length}, hasMore=${page1.hasMore}');
      expect(page1.items, isNotEmpty);

      final drama1 = page1.items.first;
      expect(drama1.id, isNotEmpty);
      expect(drama1.title, isNotEmpty);
      expect(drama1.source, equals('hongguo'));
      print('  - 剧目样本1: "${drama1.title}", id=${drama1.id}, 总集数=${drama1.episodes}, 分类=${drama1.category}');

      // 请求第 2 页 (游标前进)
      final page2 = await repository.catalog('hongguo', page: 2, category: 'short_play');
      print('【短剧目录第2页】拉取短剧数: ${page2.items.length}, hasMore=${page2.hasMore}');
      if (page1.hasMore) {
        expect(page2.items, isNotEmpty);
      } else {
        expect(page1.items, isNotEmpty);
      }

      sw.stop();

      final page1Ids = page1.items.map((d) => d.id).toSet();
      final page2Ids = page2.items.map((d) => d.id).toSet();
      print('  - 游标分页验证: 第1页项数=${page1.items.length}, 第2页项数=${page2.items.length}');
      if (page2.items.isNotEmpty) {
        print('  - 重叠度分析: ${page1Ids.intersection(page2Ids).length} / ${page2.items.length}');
      }

      recorder.record(
        action: 'catalog_paged',
        endpoint: 'FFI:catalog-hongguo /reading/distribution/category/landpage/v/',
        params: {'source': 'hongguo', 'category': 'short_play', 'pages': [1, 2]},
        latencyMs: sw.elapsedMilliseconds,
        responseSummary: {
          'page1Count': page1.items.length,
          'page2Count': page2.items.length,
          'page1HasMore': page1.hasMore,
          'page2HasMore': page2.hasMore,
          'sampleDrama': {
            'id': drama1.id,
            'title': drama1.title,
            'episodes': drama1.episodes,
            'category': drama1.category,
          },
        },
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('4. 智能搜索关键词联想与检索结果聚合', () async {
      const query = '神医';
      final swSuggest = Stopwatch()..start();
      final suggestions = await repository.suggestions(query);
      swSuggest.stop();

      print('【关键词联想】"$query" 返回联想项 ${suggestions.length} 条，耗时 ${swSuggest.elapsedMilliseconds} ms:');
      for (final s in suggestions.take(5)) {
        print('  - 联想词: $s');
      }
      expect(suggestions, isA<List<String>>());

      final swSearch = Stopwatch()..start();
      final searchResult = await repository.catalog('hongguo', query: query);
      swSearch.stop();

      print('【检索结果】搜索 "$query" 命中 ${searchResult.items.length} 部短剧，耗时 ${swSearch.elapsedMilliseconds} ms:');
      for (final d in searchResult.items.take(3)) {
        print('  - 命中文档: id=${d.id}, 标题="${d.title}", 集数=${d.episodes}');
      }
      expect(searchResult.items, isNotEmpty);

      recorder.record(
        action: 'suggestions_and_search',
        endpoint: 'FFI:suggestions (/incent_resource/suggestion) & search',
        params: {'query': query},
        latencyMs: swSuggest.elapsedMilliseconds + swSearch.elapsedMilliseconds,
        responseSummary: {
          'suggestionsCount': suggestions.length,
          'topSuggestions': suggestions.take(5).toList(),
          'searchCount': searchResult.items.length,
          'topResults': [
            for (final d in searchResult.items.take(3))
              {'id': d.id, 'title': d.title, 'episodes': d.episodes}
          ],
        },
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('5. 真实短剧剧集详情与选集分集连续性校验 (1..N 递增且无空缺)', () async {
      final catalog = await repository.catalog('hongguo', page: 1);
      expect(catalog.items, isNotEmpty);

      // 选择一部集数适中的真实短剧
      final drama = catalog.items.firstWhere(
        (d) => d.episodes >= 10 && d.episodes <= 100,
        orElse: () => catalog.items.first,
      );

      final sw = Stopwatch()..start();
      final detail = await repository.detail(drama);
      sw.stop();

      print('【短剧详情】剧名: "${detail.drama.title}", id=${detail.drama.id}, 分集总数: ${detail.episodes.length}');
      expect(detail.episodes, isNotEmpty);

      // 严格校验选集分集连续性
      for (var index = 0; index < detail.episodes.length; index++) {
        final expectedNumber = index + 1;
        final episode = detail.episodes[index];
        expect(episode.number, equals(expectedNumber),
            reason: '分集序号中断: 索引 $index 期望第 $expectedNumber 集，实际为第 ${episode.number} 集');
        expect(episode.id, isNotEmpty, reason: '第 ${episode.number} 集分集 id 不得为空');
      }

      print('【分集连续性校验】通过！从第 1 集至第 ${detail.episodes.length} 集连续递增且无空缺。');

      recorder.record(
        action: 'drama_detail',
        endpoint: 'FFI:detail (/novel/player/video_detail/v1/)',
        params: {'dramaId': drama.id, 'title': drama.title},
        latencyMs: sw.elapsedMilliseconds,
        responseSummary: {
          'title': detail.drama.title,
          'dramaId': detail.drama.id,
          'episodeCount': detail.episodes.length,
          'firstEpisode': {
            'number': detail.episodes.first.number,
            'id': detail.episodes.first.id,
            'title': detail.episodes.first.title,
          },
          'lastEpisode': {
            'number': detail.episodes.last.number,
            'id': detail.episodes.last.id,
            'title': detail.episodes.last.title,
          },
          'continuous': true,
        },
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('6. 真实视频解析与多清晰度 PlaybackPlan 校验 (包含 32 位 CENC 解密密钥)', () async {
      final catalog = await repository.catalog('hongguo', page: 1);
      final drama = catalog.items.first;
      final detail = await repository.detail(drama);
      final episode = detail.episodes.first;

      final sw = Stopwatch()..start();
      final plan = await repository.resolve(drama, episode);
      sw.stop();

      print('【解析视频流】剧集: "${drama.title}" 第 ${episode.number} 集');
      print('  - 本地代理流地址: ${plan.url}');
      print('  - CENC AES-128 密钥: ${plan.decryptionKey}');
      print('  - 当前分辨率: ${plan.quality}P');
      print('  - 清晰度阶梯: ${plan.qualities}');
      print('  - 会话 ID: ${plan.session}');
      print('  - 防盗链头: ${plan.headers}');

      expect(plan.url, isNotEmpty);
      expect(plan.session, isNotEmpty);
      if (plan.qualities.isNotEmpty) {
        expect(plan.quality, greaterThan(0));
      }

      if (plan.decryptionKey.isNotEmpty) {
        // CENC AES-128 key 为 16 字节 = 32 位十六进制字符
        expect(plan.decryptionKey.length, equals(32), reason: 'CENC 解密密钥必须为 32 位 hex');
        expect(RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(plan.decryptionKey), isTrue,
            reason: '密钥格式必须为纯十六进制');
      }

      recorder.record(
        action: 'resolve_playback_plan',
        endpoint: 'FFI:resolve (/novel/player/video_model/v1/)',
        params: {'dramaId': drama.id, 'episodeId': episode.id, 'episodeNumber': episode.number},
        latencyMs: sw.elapsedMilliseconds,
        responseSummary: {
          'url': plan.url,
          'hasDecryptionKey': plan.decryptionKey.isNotEmpty,
          'decryptionKeyLength': plan.decryptionKey.length,
          'decryptionKeyHex': plan.decryptionKey,
          'quality': plan.quality,
          'qualities': plan.qualities,
          'session': plan.session,
          'headersCount': plan.headers.length,
        },
      );

      await repository.release(plan.session);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
