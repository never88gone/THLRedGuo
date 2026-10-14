import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/catpaw_js_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CatPawJsRuntime - 初始化与同步 Spider 脚本执行', () {
    test('同步 Spider 执行 home, category, detail, play, search 正常返回', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  home: function(filter) {
    return {
      class: [{ type_id: '1', type_name: '短剧' }, { type_id: '2', type_name: '都市' }],
      filters: [{ key: 'sort', name: '排序', value: [{ n: '最新', v: 'latest' }] }]
    };
  },
  category: function(tid, pg, filter, extend) {
    return {
      page: pg,
      pagecount: 3,
      limit: 10,
      total: 30,
      list: [
        { vod_id: tid + '_101', vod_name: '测试短剧1', vod_pic: 'http://img.com/1.jpg' }
      ]
    };
  },
  detail: function(id) {
    return {
      vod: {
        vod_id: id,
        vod_name: '详情短剧',
        vod_play_from: '线路1',
        vod_play_url: '第1集\$http://video.com/1.m3u8#第2集\$http://video.com/2.m3u8'
      }
    };
  },
  play: function(flag, id, flags) {
    return {
      parse: 0,
      url: 'http://cdn.com/' + id + '.m3u8',
      header: { 'User-Agent': 'CatPawClient' }
    };
  },
  search: function(wd, quick, pg) {
    return {
      list: [
        { vod_id: 's_1', vod_name: '检索短剧: ' + wd }
      ]
    };
  }
};
''';

      await runtime.init(script);
      expect(runtime.isReady, isTrue);

      final homeRes = await runtime.home();
      expect(homeRes.classes.length, 2);
      expect(homeRes.classes[0]['type_name'], '短剧');
      expect(homeRes.filters.length, 1);

      final catRes = await runtime.category('1', 2);
      expect(catRes.page, 2);
      expect(catRes.pageCount, 3);
      expect(catRes.hasMore, isTrue);
      expect(catRes.list.length, 1);
      expect(catRes.list[0]['vod_id'], '1_101');

      final detailRes = await runtime.detail('d_123');
      expect(detailRes.vod['vod_id'], 'd_123');
      expect(detailRes.vod['vod_name'], '详情短剧');
      expect(detailRes.vod['vod_play_url'], contains('第1集'));

      final playRes = await runtime.play('line1', 'ep1');
      expect(playRes.url, 'http://cdn.com/ep1.m3u8');
      expect(playRes.parse, 0);
      expect(playRes.header['User-Agent'], 'CatPawClient');

      final searchRes = await runtime.search('战神');
      expect(searchRes.list.length, 1);
      expect(searchRes.list[0]['vod_name'], '检索短剧: 战神');

      runtime.dispose();
      expect(runtime.isDisposed, isTrue);
    });
  });

  group('CatPawJsRuntime - 异步 Spider 脚本与 Promise 决议', () {
    test('真实 async/await 异步 Spider 接口通过 handlePromise 正常决议且不为空字典', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  home: async function(filter) {
    return new Promise(function(resolve) {
      resolve({
        class: [{ type_id: 'async_tag', type_name: '异步分类' }],
        filters: []
      });
    });
  },
  category: async function(tid, pg, filter, extend) {
    return {
      page: pg,
      pagecount: 1,
      limit: 20,
      total: 1,
      list: [{ vod_id: 'async_' + tid, vod_name: '异步短剧' }]
    };
  },
  detail: async function(id) {
    return {
      list: [{
        vod_id: id,
        vod_name: '异步详情短剧'
      }]
    };
  },
  play: async function(flag, id, flags) {
    return {
      parse: 1,
      url: 'https://async.stream.com/' + id,
      header: { 'Referer': 'https://async.stream.com' }
    };
  },
  search: async function(wd, quick, pg) {
    return [
      { vod_id: 's_async', vod_name: '异步搜索: ' + wd }
    ];
  }
};
''';

      await runtime.init(script);

      final homeRes = await runtime.home();
      expect(homeRes.classes.length, 1);
      expect(homeRes.classes[0]['type_name'], '异步分类');

      final catRes = await runtime.category('99', 1);
      expect(catRes.page, 1);
      expect(catRes.hasMore, isFalse);
      expect(catRes.list.first['vod_id'], 'async_99');

      final detailRes = await runtime.detail('v_99');
      expect(detailRes.vod['vod_name'], '异步详情短剧');

      final playRes = await runtime.play('main', '99');
      expect(playRes.parse, 1);
      expect(playRes.url, 'https://async.stream.com/99');
      expect(playRes.header['Referer'], 'https://async.stream.com');

      final searchRes = await runtime.search('神豪');
      expect(searchRes.list.length, 1);
      expect(searchRes.list.first['vod_name'], '异步搜索: 神豪');

      runtime.dispose();
    });

    test('JS 运行时中未捕获异常能被安全捕获并在 Dart 端抛出清晰错误', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var spider = {
  home: async function() {
    throw new Error('Spider 内部致命错误');
  }
};
''';
      await runtime.init(script);
      await expectLater(runtime.home(), throwsA(isA<Exception>()));
      runtime.dispose();
    });
  });

  group('CatPawJsRuntime - 内置 fetch 垫片与 MockClient 桥接', () {
    test('通过 MockClient 拦截 GET 与 POST 请求，验证 status/ok/text/json 垫片功能', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/categories') {
          expect(request.method, 'GET');
          expect(request.headers['Authorization'], 'Bearer token_123');
          return http.Response(
            jsonEncode({
              'classes': [{'type_id': 'c1', 'type_name': '科幻'}],
              'filters': {}
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/post_search') {
          expect(request.method, 'POST');
          final bodyJson = jsonDecode(request.body);
          expect(bodyJson['keyword'], '穿越');
          return http.Response(
            jsonEncode({
              'list': [{'vod_id': 'trans_1', 'vod_name': '穿越古代当首富'}]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/error') {
          return http.Response('Internal Error', 500);
        }
        return http.Response('Not Found', 404);
      });

      final runtime = CatPawJsRuntime(mockClient);
      const script = '''
var spider = {
  home: async function() {
    var res = await fetch("https://example.com/api/categories", {
      method: "GET",
      headers: { "Authorization": "Bearer token_123" }
    });
    if (!res.ok) throw new Error("fetch failed");
    var data = await res.json();
    return { class: data.classes, filters: data.filters };
  },
  search: async function(wd) {
    var res = await fetch("https://example.com/api/post_search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ keyword: wd })
    });
    var data = await res.json();
    return data;
  },
  play: async function() {
    var res = await fetch("https://example.com/api/error");
    return {
      parse: res.status,
      url: await res.text(),
      header: {}
    };
  }
};
''';

      await runtime.init(script);

      final homeRes = await runtime.home();
      expect(homeRes.classes.length, 1);
      expect(homeRes.classes.first['type_name'], '科幻');

      final searchRes = await runtime.search('穿越');
      expect(searchRes.list.length, 1);
      expect(searchRes.list.first['vod_name'], '穿越古代当首富');

      final playRes = await runtime.play('', '');
      expect(playRes.parse, 500);
      expect(playRes.url, 'Internal Error');

      runtime.dispose();
    });
  });

  group('CatPawJsRuntime - 纯 JS html.parse DOM 引擎', () {
    test('支持标签、类、ID 选择器、层级查找以及 text() 和 attr() 提取', () async {
      final runtime = CatPawJsRuntime();
      const script = '''
var testHtml = `
<html>
  <body>
    <div id="main-content" class="container">
      <h1 class="page-title">热门短剧推荐</h1>
      <div class="list">
        <div class="item" data-id="1001">
          <a class="item-link" href="/vod/1001.html">
            <img class="cover" src="https://img.com/p1.jpg" alt="海报1" />
            <span class="title">第一部短剧</span>
          </a>
          <span class="remark">更新至10集</span>
        </div>
        <div class="item" data-id="1002">
          <a class="item-link" href="/vod/1002.html">
            <img class="cover" src="https://img.com/p2.jpg" alt="海报2" />
            <span class="title">第二部短剧</span>
          </a>
          <span class="remark">已完结</span>
        </div>
      </div>
    </div>
  </body>
</html>
`;

var spider = {
  home: async function() {
    var doc = html.parse(testHtml);
    var h1Text = doc.find('.page-title').text();
    var container = doc.find('#main-content');
    var items = container.find('.item');
    
    var dramaList = [];
    for (var i = 0; i < items.length; i++) {
      var item = items.eq(i);
      var link = item.find('a');
      var href = link.attr('href');
      var img = item.find('img').attr('src');
      var title = item.find('.title').text();
      var remark = item.find('.remark').text();
      dramaList.push({
        vod_id: href,
        vod_name: title,
        vod_pic: img,
        vod_remarks: remark
      });
    }

    return {
      class: [{ type_id: 't1', type_name: h1Text }],
      filters: dramaList
    };
  }
};
''';

      await runtime.init(script);

      final homeRes = await runtime.home();
      expect(homeRes.classes.first['type_name'], '热门短剧推荐');
      expect(homeRes.filters.length, 2);

      final drama1 = homeRes.filters[0];
      expect(drama1['vod_id'], '/vod/1001.html');
      expect(drama1['vod_name'], '第一部短剧');
      expect(drama1['vod_pic'], 'https://img.com/p1.jpg');
      expect(drama1['vod_remarks'], '更新至10集');

      final drama2 = homeRes.filters[1];
      expect(drama2['vod_id'], '/vod/1002.html');
      expect(drama2['vod_name'], '第二部短剧');
      expect(drama2['vod_pic'], 'https://img.com/p2.jpg');
      expect(drama2['vod_remarks'], '已完结');

      runtime.dispose();
    });
  });

  group('CatPawRuntimePool - 数据源隔离、热重载与生命周期', () {
    test('不同 sourceId 拥有相互隔离的全局变量环境', () async {
      final pool = CatPawRuntimePool();

      const scriptA = '''
var BASE_NAME = "源A";
var spider = {
  home: async function() {
    return { class: [{ type_id: 'A', type_name: BASE_NAME }], filters: [] };
  }
};
''';

      const scriptB = '''
var BASE_NAME = "源B";
var spider = {
  home: async function() {
    return { class: [{ type_id: 'B', type_name: BASE_NAME }], filters: [] };
  }
};
''';

      final rtA = await pool.get('source_a', scriptA);
      final rtB = await pool.get('source_b', scriptB);

      final resA = await rtA.home();
      final resB = await rtB.home();

      expect(resA.classes.first['type_name'], '源A');
      expect(resB.classes.first['type_name'], '源B');

      pool.disposeAll();
      expect(pool.isDisposed, isTrue);
    });

    test('相同 sourceId 传入新脚本时触发热重载并替换旧实例', () async {
      final pool = CatPawRuntimePool();

      const scriptV1 = '''
var spider = {
  home: async function() { return { class: [{ type_id: '1', type_name: '版本1' }], filters: [] }; }
};
''';

      const scriptV2 = '''
var spider = {
  home: async function() { return { class: [{ type_id: '2', type_name: '版本2' }], filters: [] }; }
};
''';

      final rt1 = await pool.get('test_source', scriptV1);
      final res1 = await rt1.home();
      expect(res1.classes.first['type_name'], '版本1');

      // 再次传入相同脚本返回同一缓存实例
      final rtSame = await pool.get('test_source', scriptV1);
      expect(identical(rt1, rtSame), isTrue);

      // 传入不同脚本触发热重载
      final rt2 = await pool.get('test_source', scriptV2);
      expect(identical(rt1, rt2), isFalse);
      expect(rt1.isDisposed, isTrue);

      final res2 = await rt2.home();
      expect(res2.classes.first['type_name'], '版本2');

      pool.remove('test_source');
      expect(rt2.isDisposed, isTrue);

      pool.disposeAll();
    });

    test('已销毁实例再次调用抛出 StateError，不会访问底层已释放指针', () async {
      final runtime = CatPawJsRuntime();
      await runtime.init('var spider = { home: function() { return { class: [], filters: [] }; } };');
      runtime.dispose();

      await expectLater(runtime.home(), throwsStateError);
      await expectLater(runtime.init(''), throwsStateError);
    });

    test('未决网络请求在 runtime.dispose() 触发时不发生崩溃或段错误', () async {
      final mockClient = MockClient((req) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response('{"ok":true}', 200);
      });

      final runtime = CatPawJsRuntime(mockClient);
      const script = '''
var spider = {
  home: async function() {
    var res = await fetch("http://delay.com");
    return { class: [], filters: [] };
  }
};
''';
      await runtime.init(script);

      // 发起请求但不等待立即触发销毁
      final future = runtime.home();
      runtime.dispose();

      try {
        await future;
      } catch (_) {}

      expect(runtime.isDisposed, isTrue);
    });
  });
}
