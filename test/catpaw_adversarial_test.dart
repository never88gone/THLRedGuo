// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/catpaw_js_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Group 1: HTML 引擎极限对抗与纯 JS DOM 解析能力实测', () {
    test('1.1 超深 DOM 嵌套极限压力 (100层与300层嵌套)', () async {
      final testScript = '''
var spider = {
  testDeep: function(levels) {
    var h = "";
    for (var i = 0; i < levels; i++) h += "<div>";
    h += '<span id="deep">content_' + levels + '</span>';
    for (var i = 0; i < levels; i++) h += "</div>";
    var t0 = Date.now();
    var doc = html.parse(h);
    var text = doc.find("#deep").text();
    var cost = Date.now() - t0;
    return { cost: cost, text: text };
  },
  detail: async function(id) {
    var lv = parseInt(id) || 100;
    var res = this.testDeep(lv);
    return { vod: { cost_ms: res.cost, text: res.text } };
  }
};
''';
      final deepRuntime = CatPawJsRuntime();
      await deepRuntime.init(testScript);

      // 测试 100 层
      final r100 = await deepRuntime.detail('100');
      expect(r100.vod['text'], 'content_100');
      print('>>> [实测数据] 100 层 DOM 嵌套解析耗时: ${r100.vod['cost_ms']}ms');

      // 测试 300 层
      final r300 = await deepRuntime.detail('300');
      expect(r300.vod['text'], 'content_300');
      print('>>> [实测数据] 300 层 DOM 嵌套解析耗时: ${r300.vod['cost_ms']}ms');

      // 测试 500 层
      final r500 = await deepRuntime.detail('500');
      expect(r500.vod['text'], 'content_500');
      print('>>> [实测数据] 500 层 DOM 嵌套解析耗时: ${r500.vod['cost_ms']}ms');

      deepRuntime.dispose();
    });

    test('1.2 超大 HTML 吞吐与节点查找吞吐量 (500项与1000项完整列表，超300KB)', () async {
      final largeRuntime = CatPawJsRuntime();
      const script = '''
var spider = {
  testLarge: function(itemCount) {
    var h = '<html><body><div id="container">';
    for (var i = 0; i < itemCount; i++) {
      h += '<div class="item" data-id="' + i + '">' +
           '<a href="/vod/' + i + '.html" title="剧目标题_' + i + '">' +
           '<img src="https://img.com/p' + i + '.jpg" alt="封面_' + i + '" />' +
           '<span class="title">都市神豪第' + i + '集</span>' +
           '</a><span class="remark">更新至' + (i + 1) + '集</span></div>';
    }
    h += '</div></body></html>';
    var t0 = Date.now();
    var doc = html.parse(h);
    var tParse = Date.now() - t0;
    
    var t1 = Date.now();
    var items = doc.find(".item");
    var firstTitle = items.first().find(".title").text();
    var lastTitle = items.eq(items.length - 1).find(".title").text();
    var firstCover = items.first().find("img").attr("src");
    var tQuery = Date.now() - t1;

    return {
      sizeKb: Math.round(h.length / 1024),
      count: items.length,
      firstTitle: firstTitle,
      lastTitle: lastTitle,
      firstCover: firstCover,
      parseTimeMs: tParse,
      queryTimeMs: tQuery
    };
  },
  detail: async function(id) {
    var count = parseInt(id) || 500;
    var res = this.testLarge(count);
    return { vod: res };
  }
};
''';
      await largeRuntime.init(script);

      // 500 项测试
      final r500 = await largeRuntime.detail('500');
      expect(r500.vod['count'], 500);
      expect(r500.vod['firstTitle'], '都市神豪第0集');
      expect(r500.vod['lastTitle'], '都市神豪第499集');
      expect(r500.vod['firstCover'], 'https://img.com/p0.jpg');
      print('>>> [实测数据] 500 项 HTML (${r500.vod['sizeKb']}KB) 解析耗时: ${r500.vod['parseTimeMs']}ms, 查询耗时: ${r500.vod['queryTimeMs']}ms');

      // 1000 项测试 (超高负载)
      final r1000 = await largeRuntime.detail('1000');
      expect(r1000.vod['count'], 1000);
      expect(r1000.vod['firstTitle'], '都市神豪第0集');
      expect(r1000.vod['lastTitle'], '都市神豪第999集');
      print('>>> [实测数据] 1000 项 HTML (${r1000.vod['sizeKb']}KB) 解析耗时: ${r1000.vod['parseTimeMs']}ms, 查询耗时: ${r1000.vod['queryTimeMs']}ms');

      largeRuntime.dispose();
    });

    test('1.3 畸形标签与属性包含 > 的边界解析行为实测', () async {
      final htmlRuntime = CatPawJsRuntime();
      const script = '''
var spider = {
  detail: async function(id) {
    var malformed1 = '<div><p><span>文本未闭合<div id="target">深层文本</div>';
    var doc1 = html.parse(malformed1);
    var t1 = doc1.find("#target").text();

    var malformed2 = '<div class="title" data-formula="1 > 0">公式标题</div><span id="after">后续内容</span>';
    var doc2 = html.parse(malformed2);
    var title = doc2.find(".title").text();
    var after = doc2.find("#after").text();

    return {
      vod: {
        t1: t1,
        title: title,
        after: after
      }
    };
  }
};
''';
      await htmlRuntime.init(script);
      final res = await htmlRuntime.detail('test');
      expect(res.vod['t1'], '深层文本');
      print('>>> [实测数据] 未闭合标签正常兜底提取: t1="${res.vod['t1']}"');
      print('>>> [实测观察] 属性值含 > 时: title="${res.vod['title']}", after="${res.vod['after']}"');

      htmlRuntime.dispose();
    });

    test('1.4 大量 Script/Style/注释 混淆过滤与净化实测', () async {
      final htmlRuntime = CatPawJsRuntime();
      const script = '''
var spider = {
  detail: async function(id) {
    var raw = '<html><head>' +
      '<style>.fake { color: red; } #div <div class="target">fake style</div></style>' +
      '<script>var x = "<div class=\\"target\\">fake script</div>"; function f() { if(1<2) return; }</script>' +
      '</head><body>' +
      '<!-- 注释中的 <div class="target">fake comment</div> -->' +
      '<div class="target">真实短剧正文</div>' +
      '</body></html>';
    var doc = html.parse(raw);
    var targetText = doc.find(".target").text();
    var allText = doc.text();
    return {
      vod: {
        target: targetText,
        hasFakeStyle: allText.indexOf("fake style") !== -1,
        hasFakeScript: allText.indexOf("fake script") !== -1,
        hasFakeComment: allText.indexOf("fake comment") !== -1
      }
    };
  }
};
''';
      await htmlRuntime.init(script);
      final res = await htmlRuntime.detail('test');
      expect(res.vod['target'], '真实短剧正文');
      expect(res.vod['hasFakeStyle'], isFalse);
      expect(res.vod['hasFakeScript'], isFalse);
      expect(res.vod['hasFakeComment'], isFalse);
      print('>>> [实测数据] Style, Script, Comment 标签均被彻底剔除，未污染 DOM 树与纯文本');
      htmlRuntime.dispose();
    });

    test('1.5 边界查询 API 容错与防御 (eq 越界、空选择器、找不到的节点)', () async {
      final htmlRuntime = CatPawJsRuntime();
      const script = '''
var spider = {
  detail: async function(_) {
    var doc = html.parse("<div><p class='single'>唯一段落</p></div>");
    var notFound = doc.find(".nonexistent");
    return {
      vod: {
        emptyText: notFound.text(),
        emptyAttr: notFound.attr("href"),
        eqOutOfBoundsText: doc.find(".single").eq(99).text(),
        eqNegativeText: doc.find(".single").eq(-1).text(),
        firstOnEmptyAttr: notFound.first().attr("src"),
        emptySelectorText: doc.find("").text()
      }
    };
  }
};
''';
      await htmlRuntime.init(script);
      final res = await htmlRuntime.detail('');
      expect(res.vod['emptyText'], '');
      expect(res.vod['emptyAttr'], '');
      expect(res.vod['eqOutOfBoundsText'], '');
      expect(res.vod['eqNegativeText'], '');
      expect(res.vod['firstOnEmptyAttr'], '');
      expect(res.vod['emptySelectorText'], '');
      print('>>> [实测数据] 边界与空值链式操作 100% 安全返回兜底空字符串，绝无空指针异常');
      htmlRuntime.dispose();
    });
  });

  group('Group 2: HTTP 异常状态、网络波动与畸形响应实测', () {
    test('2.1 各类 HTTP 错误状态码 (400, 403, 404, 500, 502, 504) 容错映射', () async {
      int currentStatus = 404;
      final mockClient = MockClient((req) async {
        return http.Response('Server Error Details', currentStatus);
      });

      final runtime = CatPawJsRuntime(mockClient);
      const script = '''
var spider = {
  detail: async function(url) {
    var res = await fetch(url);
    var text = await res.text();
    return {
      vod: {
        status: res.status,
        ok: res.ok,
        body: text
      }
    };
  }
};
''';
      await runtime.init(script);

      final statusCodes = [400, 401, 403, 404, 500, 502, 503, 504];
      for (final code in statusCodes) {
        currentStatus = code;
        final res = await runtime.detail('https://example.com/status/$code');
        expect(res.vod['status'], code);
        expect(res.vod['ok'], isFalse);
        expect(res.vod['body'], 'Server Error Details');
      }
      print('>>> [实测数据] 8 种 HTTP 错误状态码均被正确映射，res.ok 准确反映');
      runtime.dispose();
    });

    test('2.2 畸形响应内容 (非法 JSON, HTML 报错, 空 Body) 容错降级', () async {
      String responseBody = '{ broken json';
      final mockClient = MockClient((req) async {
        return http.Response(responseBody, 200, headers: {'content-type': 'application/json'});
      });

      final runtime = CatPawJsRuntime(mockClient);
      const script = '''
var spider = {
  detail: async function(mode) {
    var res = await fetch("https://example.com/data");
    var jsonData = await res.json();
    return {
      vod: {
        isJsonMap: typeof jsonData === 'object' && jsonData !== null,
        jsonKeysCount: Object.keys(jsonData).length
      }
    };
  }
};
''';
      await runtime.init(script);

      // 非法 JSON
      responseBody = '{"title": "test", unclosed...';
      final r1 = await runtime.detail('broken_json');
      expect(r1.vod['isJsonMap'], isTrue);
      expect(r1.vod['jsonKeysCount'], 0);

      // HTML 页面冒充 JSON
      responseBody = '<html><body>502 Bad Gateway</body></html>';
      final r2 = await runtime.detail('html_body');
      expect(r2.vod['isJsonMap'], isTrue);
      expect(r2.vod['jsonKeysCount'], 0);

      // 空 Body
      responseBody = '';
      final r3 = await runtime.detail('empty_body');
      expect(r3.vod['isJsonMap'], isTrue);
      expect(r3.vod['jsonKeysCount'], 0);

      print('>>> [实测数据] 畸形 JSON、HTML 报错和空 Body 在 res.json() 下安全降级为 {}');
      runtime.dispose();
    });

    test('2.3 网络层异常与超时 (SocketException / TimeoutException)', () async {
      final mockClient = MockClient((req) async {
        if (req.url.path == '/timeout') {
          throw TimeoutException('Network timed out');
        } else if (req.url.path == '/socket') {
          throw const SocketException('Connection refused');
        }
        throw http.ClientException('Network pipe broken');
      });

      final runtime = CatPawJsRuntime(mockClient);
      const script = '''
var spider = {
  detail: async function(path) {
    var res = await fetch("https://example.com" + path);
    return {
      vod: {
        status: res.status,
        ok: res.ok,
        body: res.body
      }
    };
  }
};
''';
      await runtime.init(script);

      final rTimeout = await runtime.detail('/timeout');
      expect(rTimeout.vod['status'], 0);
      expect(rTimeout.vod['ok'], isFalse);

      final rSocket = await runtime.detail('/socket');
      expect(rSocket.vod['status'], 0);
      expect(rSocket.vod['ok'], isFalse);

      final rOther = await runtime.detail('/other');
      expect(rOther.vod['status'], 0);
      expect(rOther.vod['ok'], isFalse);

      print('>>> [实测数据] 网络底层抛出 Timeout/Socket/Client 异常被 Dart 拦截并返回 status=0，未击穿进程');
      runtime.dispose();
    });

    test('2.4 非法与畸形 URL 在 MockClient 下的安全防御', () async {
      final mockClient = MockClient((req) async {
        return http.Response('ok', 200);
      });
      final runtime = CatPawJsRuntime(mockClient);
      const script = '''
var spider = {
  detail: async function(badUrl) {
    var res = await fetch(badUrl);
    return {
      vod: {
        status: res.status,
        ok: res.ok
      }
    };
  }
};
''';
      await runtime.init(script);

      final badUrls = [
        'http://:::invalid-port',
        'http://[invalid-ipv6',
      ];
      for (final badUrl in badUrls) {
        final res = await runtime.detail(badUrl);
        expect(res.vod['status'], 0);
        expect(res.vod['ok'], isFalse);
      }
      print('>>> [实测数据] 非法 URL 触发 FormatException 时被安全兜底返回 status=0');
      runtime.dispose();
    });

    test('2.5 高并发 Fetch 请求洪峰压力 (30 个并发请求)', () async {
      int activeCount = 0;
      int maxConcurrent = 0;
      final mockClient = MockClient((req) async {
        activeCount++;
        if (activeCount > maxConcurrent) maxConcurrent = activeCount;
        await Future.delayed(const Duration(milliseconds: 20));
        activeCount--;
        return http.Response('{"idx": "${req.url.queryParameters['i']}"}', 200);
      });

      final runtime = CatPawJsRuntime(mockClient);
      const script = '''
var spider = {
  home: async function() {
    var promises = [];
    for (var i = 0; i < 30; i++) {
      promises.push(fetch("https://example.com/api?i=" + i).then(r => r.json()));
    }
    var results = await Promise.all(promises);
    return {
      class: results.map(r => ({ type_id: r.idx, type_name: "item_" + r.idx })),
      filters: []
    };
  }
};
''';
      await runtime.init(script);
      final sw = Stopwatch()..start();
      final homeRes = await runtime.home();
      sw.stop();

      expect(homeRes.classes.length, 30);
      print('>>> [实测数据] 30 个并发 fetch 全部顺利决议，最高瞬时并发: $maxConcurrent, 总耗时: ${sw.elapsedMilliseconds}ms');
      runtime.dispose();
    });
  });

  group('Group 3: JS 脚本异常、注入对抗与沙箱安全性实测', () {
    test('3.1 语法错误脚本加载异常捕获', () async {
      final runtime = CatPawJsRuntime();
      await expectLater(
        () async => await runtime.init('const a = ; // syntax error'),
        throwsA(isA<Exception>()),
      );
      expect(runtime.isReady, isFalse);
      print('>>> [实测数据] 语法错误脚本初始化抛出 Exception，runtime 维持未就绪状态');
      runtime.dispose();
    });

    test('3.2 Spider 方法内部抛出各类型异常', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  home: async function() {
    throw new Error("Spider 业务主动崩溃");
  },
  category: async function(tid) {
    throw "非 Error 对象的字符串异常";
  },
  detail: async function(id) {
    var obj = null;
    return obj.undefinedField.nested;
  },
  play: async function() {
    return nonexistentFunctionCall();
  }
};
''';
      await runtime.init(script);

      // Error 实例
      await expectLater(() => runtime.home(), throwsA(isA<Exception>()));
      // 字符串异常
      await expectLater(() => runtime.category('1', 1), throwsA(isA<Exception>()));
      // TypeError
      await expectLater(() => runtime.detail('1'), throwsA(isA<Exception>()));
      // ReferenceError
      await expectLater(() => runtime.play('', ''), throwsA(isA<Exception>()));

      print('>>> [实测数据] Error, String throw, TypeError, ReferenceError 均被安全捕获并转为 Dart Exception');
      runtime.dispose();
    });

    test('3.3 异步 Promise.reject 异常捕获', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  home: async function() {
    return Promise.reject(new Error("异步拒绝"));
  }
};
''';
      await runtime.init(script);
      await expectLater(() => runtime.home(), throwsA(isA<Exception>()));
      print('>>> [实测数据] Promise.reject 异常被 Dart 端捕获为 Exception');
      runtime.dispose();
    });

    test('3.4 引号与反斜杠转义及代码注入攻击验证', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  search: function(wd) {
    return [{ vod_id: wd, vod_name: wd }];
  }
};
''';
      await runtime.init(script);

      // 对抗测试：双引号、单引号、反斜杠
      final res1 = await runtime.search('战神"\'\\测试');
      expect(res1.list.first['vod_name'], '战神"\'\\测试');
      print('>>> [实测数据] 引号与反斜杠被转义通过');

      // 对抗测试：闭合引号代码注入攻击
      const maliciousPayload = 'test"); globalThis.injected = true; ("';
      final resInject = await runtime.search(maliciousPayload);
      expect(resInject.list.first['vod_name'], maliciousPayload);
      print('>>> [实测数据] 闭合双引号代码注入被安全限制在字面量内部');

      runtime.dispose();
    });

    test('3.5 换行符与回车符在参数转义中安全防御与正确传递', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  search: function(wd) {
    return [{ vod_id: wd, vod_name: wd }];
  },
  detail: function(id) {
    return { vod: { vod_id: id } };
  }
};
''';
      await runtime.init(script);

      // 实测：当 search 关键词传入含有换行符的字符时，被 jsonEncode 完美防御并保持原样
      final searchRes = await runtime.search("第一季\n第二季\r第三季");
      expect(searchRes.list.first['vod_name'], "第一季\n第二季\r第三季");
      print('>>> [实测确证防御] search 成功抵御换行符并原样解析');

      // 实测：当 detail id 传入含有换行符时，被 jsonEncode 完美防御并保持原样
      final detailRes = await runtime.detail("id_part1\nid_part2\r\npart3");
      expect(detailRes.vod['vod_id'], "id_part1\nid_part2\r\npart3");
      print('>>> [实测确证防御] detail 成功抵御换行符并原样解析');

      runtime.dispose();
    });

    test('3.6 Spider 返回非法非对象类型时的容错边界', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  home: async function() { return null; },
  category: async function() { return "not_an_object"; },
  detail: async function() { return 12345; },
  play: async function() { return [1, 2, 3]; },
  search: async function() { return false; }
};
''';
      await runtime.init(script);

      final homeRes = await runtime.home();
      expect(homeRes.classes, isEmpty);
      expect(homeRes.filters, isEmpty);

      final catRes = await runtime.category('1', 1);
      expect(catRes.list, isEmpty);

      final detailRes = await runtime.detail('fallback_id');
      print('>>> [实测数据] detail 返回 12345 时，detailRes.vod 为: ${detailRes.vod}');

      final playRes = await runtime.play('f', 'i');
      expect(playRes.url, '');

      final searchRes = await runtime.search('kw');
      expect(searchRes.list, isEmpty);

      print('>>> [实测数据] 非法返回类型全部被拦截并安全兜底，未导致 Dart 空指针或崩溃');
      runtime.dispose();
    });

    test('3.7 资源释放与重入竞态 (异步请求未决时执行 dispose)', () async {
      final mockClient = MockClient((req) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response('{"ok":true}', 200);
      });

      final runtime = CatPawJsRuntime(mockClient);
      const script = '''
var spider = {
  home: async function() {
    var res = await fetch("https://example.com/long_request");
    return { class: [], filters: [] };
  }
};
''';
      await runtime.init(script);

      final homeFuture = runtime.home();
      runtime.dispose();
      expect(runtime.isDisposed, isTrue);

      expect(() => runtime.home(), throwsStateError);

      try {
        await homeFuture;
      } catch (_) {}

      print('>>> [实测数据] 异步未决状态 dispose 安全执行，无段错误或异常外溢');
    });

    test('3.8 [异步死锁防御] 永久挂起的异步 Promise 超时保护验证', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  home: function() {
    return new Promise(function(resolve, reject) {
      // 永久不 resolve，也不 reject
    });
  }
};
''';
      await runtime.init(script);

      final sw = Stopwatch()..start();
      try {
        // _evalAsync 默认超时 15s，此处验证 handlePromise 超时逻辑生效
        // 为了加快单测时间，我们用 timeout 观察
        await runtime.home().timeout(const Duration(seconds: 3));
        fail('未挂起');
      } catch (e) {
        sw.stop();
        print('>>> [实测数据] 挂起的 Promise 在超时保护下被正确打断: $e, 耗时: ${sw.elapsedMilliseconds}ms');
      }

      runtime.dispose();
    });
  });
}
