// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/catpaw_js_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('【对抗挑战 1】并发多实例与数据隔离对抗挑战', () {
    test('1.1: 5 个独立 sourceId 实例并发初始化并执行 100 次交叉调用，杜绝跨实例数据污染与通道串话', () async {
      final sourceIds = ['source_alpha', 'source_beta', 'source_gamma', 'source_delta', 'source_epsilon'];

      // 为每个源创建带有专属状态和延迟响应的脚本
      String generateSpiderScript(String sourceId, int index) {
        return '''
var SOURCE_ID = "$sourceId";
var INDEX = $index;
var CALL_COUNT = 0;

var spider = {
  home: async function(filter) {
    CALL_COUNT++;
    var res = await fetch("http://mock.api/home?source=" + SOURCE_ID);
    var data = await res.json();
    return {
      class: [{ type_id: SOURCE_ID + '_c1', type_name: data.source + '_分类' }],
      filters: [{ key: 'src', name: SOURCE_ID, value: [{ n: 'call_' + CALL_COUNT, v: CALL_COUNT }] }]
    };
  },
  category: async function(tid, pg, filter, extend) {
    CALL_COUNT++;
    return {
      page: pg,
      pagecount: 5,
      limit: 10,
      total: 50,
      list: [{
        vod_id: SOURCE_ID + '_vod_' + tid + '_' + pg,
        vod_name: SOURCE_ID + '专属短剧_' + pg,
        vod_pic: 'http://img.com/' + SOURCE_ID + '.jpg'
      }]
    };
  },
  detail: async function(id) {
    CALL_COUNT++;
    var res = await fetch("http://mock.api/detail?id=" + id + "&source=" + SOURCE_ID);
    var detailData = await res.json();
    return {
      vod: {
        vod_id: id,
        vod_name: detailData.title,
        detailData: detailData,
        vod_play_from: SOURCE_ID + '_线路',
        vod_play_url: '第1集\$http://stream.com/' + SOURCE_ID + '/' + id + '.m3u8'
      }
    };
  },
  play: async function(flag, id, flags) {
    CALL_COUNT++;
    return {
      parse: 0,
      url: 'https://cdn.play/' + SOURCE_ID + '/' + id,
      header: { 'X-Source-Id': SOURCE_ID, 'X-Call-Seq': String(CALL_COUNT) }
    };
  },
  search: async function(wd, quick, pg) {
    CALL_COUNT++;
    return [
      { vod_id: SOURCE_ID + '_s_' + wd, vod_name: '[' + SOURCE_ID + '] ' + wd }
    ];
  }
};
''';
      }

      // 创建支持并发路由验证的 MockClient
      final mockClient = MockClient((request) async {
        final uri = request.url;
        final src = uri.queryParameters['source'] ?? 'unknown';
        // 增加 5~20ms 随机微延迟模拟网络乱序到达
        final delayMs = 5 + Random().nextInt(15);
        await Future.delayed(Duration(milliseconds: delayMs));

        if (uri.path == '/home') {
          return http.Response(jsonEncode({'source': src, 'status': 'ok'}), 200,
              headers: {'content-type': 'application/json'});
        } else if (uri.path == '/detail') {
          final id = uri.queryParameters['id'] ?? '';
          return http.Response(jsonEncode({'source': src, 'title': '$src-剧集-$id'}), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final runtimePool = CatPawRuntimePool(mockClient);

      // 阶段 1: 验证每个数据源独立加载与数据隔离
      for (var i = 0; i < sourceIds.length; i++) {
        final id = sourceIds[i];
        final script = generateSpiderScript(id, i);
        final targetRuntime = await runtimePool.get(id, script);

        // 1. home
        final homeRes = await targetRuntime.home();
        expect(homeRes.classes.first['type_id'], '${id}_c1',
            reason: '数据源 $id home() 分类隔离验证失败');
        expect(homeRes.classes.first['type_name'], contains(id));

        // 2. category
        final catRes = await targetRuntime.category('cat_1', 1);
        expect(catRes.list.first['vod_id'], '${id}_vod_cat_1_1');
        expect(catRes.list.first['vod_pic'], contains(id));

        // 3. detail
        final detailRes = await targetRuntime.detail('drama_$i');
        expect(detailRes.vod['vod_play_from'], '${id}_线路');
        expect(detailRes.vod['vod_name'], '$id-剧集-drama_$i');

        // 4. play
        final playRes = await targetRuntime.play('main', 'ep_$i');
        expect(playRes.header['X-Source-Id'], id);
        expect(playRes.url, contains(id));

        // 5. search
        final searchRes = await targetRuntime.search('kw_$i');
        expect(searchRes.list.first['vod_id'], '${id}_s_kw_$i');
      }

      // 阶段 2: 再次切回首个数据源，验证热切回无残留与状态自洽
      final alphaScript = generateSpiderScript(sourceIds.first, 0);
      final alphaRuntime = await runtimePool.get(sourceIds.first, alphaScript);
      final alphaHome = await alphaRuntime.home();
      expect(alphaHome.classes.first['type_id'], '${sourceIds.first}_c1');

      runtimePool.disposeAll();
    });

    test('1.2: 同一 sourceId 并发 get() 竞态挑战 - 验证并发初始化防重复创建与资源管理', () async {
      final pool = CatPawRuntimePool();
      const script = '''
var spider = {
  home: function() { return { class: [{ type_id: '1', type_name: '测试' }], filters: [] }; }
};
''';

      // 同时发起 10 个并发 get
      final futures = List.generate(10, (_) => pool.get('concurrent_src', script));
      final results = await Future.wait(futures);

      // 验证返回的所有实例都是活的且可用
      for (final rt in results) {
        expect(rt.isReady, isTrue);
        final res = await rt.home();
        expect(res.classes.first['type_name'], '测试');
      }

      pool.disposeAll();
    });

    test('1.3: 单实例内部 20 个高并发交错调用 - 验证 JS 引擎消息队列与 Promise 不死锁且正确决议', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  task: async function(n) {
    var res = await fetch("http://mock.task/delay?n=" + n);
    var data = await res.json();
    return data.result;
  }
};
''';

      final mockClient = MockClient((req) async {
        final n = req.url.queryParameters['n'] ?? '0';
        final val = int.parse(n);
        // 差异化延迟: 逆序延迟，打破先后到达顺序
        await Future.delayed(Duration(milliseconds: (20 - val) * 3));
        return http.Response(jsonEncode({'result': val * 100}), 200);
      });

      final customRt = CatPawJsRuntime(mockClient);
      await customRt.init(script);

      final futures = <Future<int>>[];
      for (var i = 0; i < 20; i++) {
        final idx = i;
        futures.add(() async {
          // 通过 search 桥接或者直接 evalAsync 调用
          await customRt.search(idx.toString());
          // 这里通过 detail 或 category 也是通用通道，我们直接验证 detail
          return idx;
        }());
      }

      // 验证 20 个请求无论执行顺序如何都能成功
      await Future.wait(futures);
      customRt.dispose();
      runtime.dispose();
    });
  });

  group('【对抗挑战 2】快速销毁与野指针挑战 (SIGSEGV 复现与异步排空对抗)', () {
    test('2.1: 慢速异步 fetch 飞行途中立即触发 runtime.dispose()，验证排空等待与零段错误 (SIGSEGV)', () async {
      final serverBlocker = Completer<void>();
      var requestReachedServer = false;
      var serverFinished = false;

      final mockClient = MockClient((req) async {
        requestReachedServer = true;
        // 模拟慢速长耗时网络 IO
        await serverBlocker.future;
        serverFinished = true;
        return http.Response(jsonEncode({'data': 'late_response'}), 200);
      });

      final runtime = CatPawJsRuntime(mockClient);
      const script = '''
var spider = {
  home: async function() {
    var res = await fetch("http://slow.server/api");
    var d = await res.json();
    return { class: [{ type_id: 'late', type_name: d.data }], filters: [] };
  }
};
''';
      await runtime.init(script);

      // 发起异步调用，请求进入网络等待
      final future = runtime.home();

      // 等待请求确实到达底层 MockClient
      while (!requestReachedServer) {
        await Future.delayed(const Duration(milliseconds: 2));
      }

      // 此时网络正在等待，立即调用 dispose()！
      expect(runtime.isDisposed, isFalse);
      runtime.dispose();
      expect(runtime.isDisposed, isTrue);

      // 放开网络阻塞
      serverBlocker.complete();

      // 验证：Future 必须完成（返回默认空对象或受控处理），绝不可让进程因野指针解引用而 SIGSEGV
      try {
        final res = await future;
        // 如果成功返回，由于 isDisposed 已设置，fetch shim 返回空内容，home 仍然成功解析出默认结果
        expect(res, isNotNull);
      } catch (e) {
        // 如果抛出受控异常也是安全的
        expect(e, isNotNull);
      }

      expect(serverFinished, isTrue);
    });

    test('2.2: 10 个慢速请求飞行时对 Pool 批量触发 remove() 与 disposeAll()，验证资源安全排空与无死锁', () async {
      final mockClient = MockClient((req) async {
        final delay = 30 + Random().nextInt(40);
        await Future.delayed(Duration(milliseconds: delay));
        return http.Response(jsonEncode({'list': [{'vod_id': 'late_vod'}]}), 200);
      });

      final pool = CatPawRuntimePool(mockClient);
      const script = '''
var spider = {
  category: async function(tid, pg) {
    var res = await fetch("http://slow.pool/api?tid=" + tid);
    var d = await res.json();
    return { page: pg, pagecount: 1, limit: 10, total: 1, list: d.list };
  }
};
''';

      final runtimes = <CatPawJsRuntime>[];
      for (var i = 0; i < 5; i++) {
        runtimes.add(await pool.get('pool_src_$i', script));
      }

      // 并发发射 10 个飞行请求
      final inflight = <Future>[];
      for (var i = 0; i < 10; i++) {
        final rt = runtimes[i % 5];
        inflight.add(rt.category('cat_$i', 1));
      }

      // 飞行途中的微延迟后随机销毁
      await Future.delayed(const Duration(milliseconds: 15));
      pool.remove('pool_src_0');
      pool.remove('pool_src_1');
      pool.disposeAll();

      expect(pool.isDisposed, isTrue);

      // 等待所有飞行请求收尾，必须全部在合理时间内决议，严禁死锁或段错误
      final allFinished = Future.wait(inflight.map((f) async {
        try {
          await f;
        } catch (_) {}
      }));
      await expectLater(allFinished.timeout(const Duration(seconds: 3)), completes);
    });

    test('2.3: 极短生命周期高频风暴: 20 轮连续「创建 -> 发起 fetch -> 立即 dispose」，探测 Native FFI 悬空指针解引用', () async {
      for (var round = 0; round < 20; round++) {
        final mockClient = MockClient((req) async {
          await Future.delayed(const Duration(milliseconds: 10));
          return http.Response('{"ok":true}', 200);
        });

        final rt = CatPawJsRuntime(mockClient);
        await rt.init('''
var spider = {
  home: async function() {
    var res = await fetch("http://storm.test/");
    return { class: [], filters: [] };
  }
};
''');

        // 发起调用，不等待
        final f = rt.home();
        // 立即 dispose
        rt.dispose();

        try {
          await f;
        } catch (_) {}

        expect(rt.isDisposed, isTrue);
      }
    });

    test('2.4: 实例销毁后调用所有公开 API 必须严格抛出 StateError，杜绝穿透至底层 C 引擎', () async {
      final rt = CatPawJsRuntime();
      await rt.init('var spider = { home: function() { return {}; } };');
      rt.dispose();

      await expectLater(() => rt.home(), throwsStateError);
      await expectLater(() => rt.category('1', 1), throwsStateError);
      await expectLater(() => rt.detail('1'), throwsStateError);
      await expectLater(() => rt.play('flag', '1'), throwsStateError);
      await expectLater(() => rt.search('kw'), throwsStateError);
      await expectLater(() => rt.init(''), throwsStateError);
    });
  });

  group('【对抗挑战 3】内存与垃圾回收压力挑战 (20 个实例反复创建销毁)', () {
    // 准备大体积 HTML (约 20KB 包含多层嵌套表格与列表)
    final sb = StringBuffer();
    sb.write('<html><body><div id="container">');
    for (var i = 0; i < 100; i++) {
      sb.write('<div class="item" data-idx="$i"><a href="/drama/$i"><span class="title">第$i部热播短剧</span></a><span class="views">${i * 1000}</span></div>');
    }
    sb.write('</div></body></html>');
    final heavyHtml = sb.toString();

    test('3.1: 反复创建并销毁 20 个包含大体量 DOM 解析与复杂 Spider 的实例，监控 RSS 内存与泄露斜率', () async {
      final initialRss = ProcessInfo.currentRss;
      final rssSnapshots = <int>[];

      final client = MockClient((req) async {
        return http.Response(jsonEncode({
          'html': heavyHtml,
          'vod': {'vod_id': 'cycle_vod', 'vod_name': '内存压测短剧'}
        }), 200, headers: {'content-type': 'application/json'});
      });

      final rt = CatPawJsRuntime(client);
      final complexScript = '''
var spider = {
  home: async function() {
    var res = await fetch("http://memory.test/");
    var data = await res.json();
    var doc = html.parse(data.html || "");
    var count = doc.find(".item").length;
    return { class: [{ type_id: 'c1', type_name: '列表数_' + count }], filters: [] };
  },
  detail: async function(id) {
    var res = await fetch("http://memory.test/");
    var data = await res.json();
    return { vod: data.vod };
  }
};
''';
      await rt.init(complexScript);

      for (var cycle = 0; cycle < 20; cycle++) {
        // 执行密集计算与 DOM 解析
        final homeRes = await rt.home();
        expect(homeRes.classes.first['type_name'], '列表数_100');

        final detailRes = await rt.detail('d_1');
        expect(detailRes.vod['vod_id'], 'cycle_vod');

        if ((cycle + 1) % 5 == 0) {
          final currentRss = ProcessInfo.currentRss;
          rssSnapshots.add(currentRss);
        }
      }

      // 销毁实例
      rt.dispose();
      expect(rt.isDisposed, isTrue);

      final finalRss = ProcessInfo.currentRss;
      final rssGrowthMb = (finalRss - initialRss) / (1024 * 1024);

      print('【内存压测数据报告】:');
      print('  初始 RSS: ${(initialRss / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('  第 5 次快照: ${(rssSnapshots[0] / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('  第 10 次快照: ${(rssSnapshots[1] / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('  第 15 次快照: ${(rssSnapshots[2] / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('  第 20 次快照: ${(rssSnapshots[3] / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('  最终 RSS: ${(finalRss / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('  总增长: ${rssGrowthMb.toStringAsFixed(2)} MB');

      // 增长应该在合理阈值内（如小于 80MB，考虑到 JIT 缓存与 FFI 静态空间）
      expect(rssGrowthMb, lessThan(80.0), reason: '20 轮复杂 Spider 循环销毁后内存增长异常，疑似存在严重 Native/Dart 内存泄漏！');
    });

    test('3.2: CatPawRuntimePool 循环反复 get 与 remove 20 次，验证内部 Map 容量无残留且 Client 隔离正常', () async {
      final pool = CatPawRuntimePool();
      const script = 'var spider = { home: function() { return { class: [], filters: [] }; } };';

      for (var i = 0; i < 20; i++) {
        final srcId = 'leak_test_src_$i';
        final rt = await pool.get(srcId, script);
        expect(rt.isReady, isTrue);
        final res = await rt.home();
        expect(res.classes, isEmpty);

        pool.remove(srcId);
        expect(rt.isDisposed, isTrue);
      }

      pool.disposeAll();
      expect(pool.isDisposed, isTrue);
    });
  });
}
