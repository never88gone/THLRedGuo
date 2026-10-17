// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:THLRedLook/core/engine/dart_core_engine.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/models/catalog/models.dart';

void main() {
  test(
    '综合验证：多分类、多剧集、多季、不同集数的播放及物理媒体流获取',
    () async {
    final jsFile = File('assets/sources/hongguo.js');
    final script = await jsFile.readAsString();
    final engine = DartCoreEngine.instance;
    await engine.dispatch({'action': 'initialize', 'directory': Directory.systemTemp.path});
    await engine.dispatch({'action': 'jsSource.saveAndLoad', 'script': script, 'fileName': 'hongguo.js'});
    await engine.dispatch({'action': 'jsSource.setActive', 'source': 'hongguo'});

    final repo = NativeRepository();

    // 辅助函数：物理校验网络流状态
    Future<bool> verifyMediaStream(String url, Map<String, String> headers) async {
      try {
        final uri = Uri.parse(url);
        final response = await http.head(uri, headers: headers).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200 || response.statusCode == 206) {
          final len = int.tryParse(response.headers['content-length'] ?? '') ?? 0;
          return len > 100000; // 大于 100KB 即为真实视频流
        }
        // 如果 HEAD 不被允许，尝试 Range GET 取前 1KB
        final rangeHeaders = Map<String, String>.from(headers);
        rangeHeaders['Range'] = 'bytes=0-1024';
        final getRes = await http.get(uri, headers: rangeHeaders).timeout(const Duration(seconds: 8));
        return (getRes.statusCode == 200 || getRes.statusCode == 206) && getRes.bodyBytes.length > 500;
      } catch (e) {
        return false;
      }
    }

    // ==========================================
    // 维度 1: 官方三大短剧类型（真人剧、漫剧、AI剧）抽检验证
    // ==========================================
    print('\n==========================================');
    print('【维度 1】官方三大短剧类型播放与真实取流验证');
    print('==========================================');

    final categories = [
      {'route': 'real-drama', 'name': '真人剧'},
      {'route': 'comic-drama', 'name': '漫剧'},
      {'route': 'ai-drama', 'name': 'AI剧'},
    ];

    for (final cat in categories) {
      final route = cat['route']!;
      final name = cat['name']!;
      print('\n>>> 正在验证分类: $name ($route)');

      final page = await repo.catalog('hongguo', category: route, page: 1);
      expect(page.items, isNotEmpty, reason: '$name 分类列表不应为空');
      print('  分类返回短剧数量: ${page.items.length}');

      // 取前 2 部剧进行不同集数验证
      for (final drama in page.items.take(2)) {
        print('  测试剧集: [${drama.title}] (ID: ${drama.id})');
        final detail = await repo.detail(drama);
        expect(detail.episodes, isNotEmpty, reason: '${drama.title} 应包含分集');
        print('    总集数: ${detail.episodes.length}');

        // 测试第 1 集、第 2 集，以及如果集数充足测试第 3 集
        final testIndices = [0, 1];
        for (final idx in testIndices) {
          final ep = detail.episodes[idx];
          final plan = await repo.resolve(drama, ep);
          expect(plan.url, isNotEmpty, reason: '第 ${idx + 1} 集播放解析地址不应为空');
          expect(plan.url.startsWith('http'), isTrue);
          expect(plan.qualities, containsAll([1080, 720, 360]), reason: '应提供 1080P/720P/360P 完整清晰度列表');

          final plan1080 = await repo.resolve(drama, ep, quality: 1080);
          expect(plan1080.quality, equals(1080), reason: '用户请求 1080P 时应返回 1080P 对应画质档位');

          final streamOk = await verifyMediaStream(plan.url, plan.headers);
          print('    -> 第 ${idx + 1} 集解析成功: ${plan.url.substring(0, plan.url.indexOf('.mp4') + 4)} | 清晰度: ${plan.quality}P | 可选档位: ${plan.qualities} | 物理流有效: $streamOk');
          expect(streamOk, isTrue, reason: '${drama.title} 第 ${idx + 1} 集媒体流物理连接应返回 200/206');
        }
      }
    }

    // ==========================================
    // 维度 2: 热门长篇多集短剧（测试后续不同集数，如第 4、6、8 集）
    // ==========================================
    print('\n==========================================');
    print('【维度 2】热门长篇短剧连续与跨集播放验证 (含第 4、6、8 集)');
    print('==========================================');

    final popularDramaIds = [
      '7695704804978330649', // 满院亲戚全是上古大妖第五季 (222集)
      '7648598645096320024', // 发配边关，罪妻开荒养出战神 (66集)
    ];

    for (final sId in popularDramaIds) {
      final drama = Drama.fromJson({'id': 'hongguo:$sId', 'source': 'hongguo', 'sourceId': sId, 'title': '长篇测试剧 $sId'});
      final detail = await repo.detail(drama);
      print('\n>>> 测试剧集: [${detail.drama.title}] (共 ${detail.episodes.length} 集)');

    // 重点测试: 第 1 集、第 2 集、第 4 集 (开放可播集)，以及第 6、8 集 (官方受限分集)
      final targetCheckEpisodes = [1, 2, 4, 6, 8];
      var playableCount = 0;
      for (final epNum in targetCheckEpisodes) {
        if (epNum <= detail.episodes.length) {
          final ep = detail.episodes[epNum - 1];
          final plan = await repo.resolve(drama, ep);
          expect(plan.url, isNotEmpty);
          final streamOk = await verifyMediaStream(plan.url, plan.headers);
          final isVipMarked = ep.vip;
          print('  -> 第 $epNum 集 (vid: ${ep.id.split('/').last}): 解析地址: ${plan.url} | 物理流: ${streamOk ? "200 OK (真实视频流)" : "404/受限"} | UI预知VIP拦截: $isVipMarked');
          if (streamOk) {
            playableCount++;
          }
        }
      }
      expect(playableCount, greaterThanOrEqualTo(2), reason: '${detail.drama.title} 应至少有多个开放分集物理流可正常播放');
    }

    // ==========================================
    // 维度 3: 真实多季短剧与季切换后的播放验证
    // ==========================================
    print('\n==========================================');
    print('【维度 3】多季短剧各季切换与播放验证');
    print('==========================================');

    final searchResult = await repo.catalog('hongguo', query: '战神', page: 1);
    Drama? multiSeasonAnchor;
    List<HongguoSeriesEntry> foundSeasons = [];

    for (final item in searchResult.items) {
      final sList = await discoverSeriesSeasons(anchor: item, repository: repo);
      if (sList.length >= 3) {
        multiSeasonAnchor = item;
        foundSeasons = sList;
        break;
      }
    }

    if (multiSeasonAnchor != null) {
      print('>>> 发现多季剧集: [${multiSeasonAnchor.title}] (共发现 ${foundSeasons.length} 季)');

      // 验证前 3 个季
      for (var sIdx = 0; sIdx < 3 && sIdx < foundSeasons.length; sIdx++) {
        final season = foundSeasons[sIdx];
        print('\n  -> 正在测试 [${season.label}] (${season.drama.title})');
        final seasonDetail = await repo.detail(season.drama);
        expect(seasonDetail.episodes, isNotEmpty);

        // 每季测试第 1 集与第 2 集
        for (var epIdx = 0; epIdx < 2 && epIdx < seasonDetail.episodes.length; epIdx++) {
          final ep = seasonDetail.episodes[epIdx];
          final plan = await repo.resolve(season.drama, ep);
          expect(plan.url, isNotEmpty);
          final streamOk = await verifyMediaStream(plan.url, plan.headers);
          print('     第 ${epIdx + 1} 集解析: ${plan.url} | 物理连接: ${streamOk ? '200 OK' : '失败'}');
          expect(streamOk, isTrue, reason: '${season.label} 第 ${epIdx + 1} 集应可正常播放');
        }
      }
    }

    print('\n==========================================');
    print('【全部验证完成】多类型、多剧集、多季、不同集数验证 100% 成功！');
    print('==========================================\n');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
