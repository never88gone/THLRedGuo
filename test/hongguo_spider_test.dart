import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/catpaw_js_runtime.dart';

void main() {
  group('官方数据源 (hongguo.js) 自动化规范与链路测试', () {
    late String hongguoScript;

    setUpAll(() async {
      final file = File('assets/sources/hongguo.js');
      expect(file.existsSync(), isTrue, reason: 'assets/sources/hongguo.js 文件必须存在');
      hongguoScript = await file.readAsString();
      expect(hongguoScript, isNotEmpty);
    });

    test('1. 元数据 (meta) 与 CatPawOpen 规范契约验证', () async {
      expect(hongguoScript.contains('id: "hongguo"'), isTrue);
      expect(hongguoScript.contains('name: "官方免费短剧"'), isTrue);
      expect(hongguoScript.contains('version: "1.0.3"'), isTrue);
      expect(hongguoScript.contains('features: ["search", "categories"]'), isTrue);
      expect(hongguoScript.contains('type: "video"'), isTrue);
      expect(hongguoScript.contains('BASE_URL = "https://hongguoduanju.com"'), isTrue);
      expect(hongguoScript.contains('var spider = {'), isTrue);
    });

    test('2. 沙箱加载与 getMeta() 读取元数据测试', () async {
      final runtime = CatPawJsRuntime();
      await runtime.init(hongguoScript);
      expect(runtime.isReady, isTrue);

      final meta = await runtime.getMeta();
      expect(meta['id'], equals('hongguo'));
      expect(meta['name'], equals('官方免费短剧'));
      expect(meta['version'], equals('1.0.3'));
      expect(meta['type'], equals('video'));
      expect(meta['features'], containsAll(['search', 'categories']));

      runtime.dispose();
    });

    test('3. home() 分类列表提取测试', () async {
      final runtime = CatPawJsRuntime();
      await runtime.init(hongguoScript);

      final homeRes = await runtime.home();
      expect(homeRes.classes, isNotEmpty);
      final typeIds = homeRes.classes.map((c) => c['type_id']).toList();
      final typeNames = homeRes.classes.map((c) => c['type_name']).toList();

      expect(typeIds, containsAll(['real-drama', 'comic-drama', 'ai-drama', 'comic']));
      expect(typeNames, containsAll(['真人剧', '漫剧', 'AI剧', '动漫']));

      runtime.dispose();
    });

    test('4. category() 分类目录解析测试 (RouterData 与推荐列表)', () async {
      final fakeRouterData = {
        'loaderData': {
          'root': {
            'recommendList': [
              {
                'series_id_str': '7345678901234567890',
                'series_title': '战神归来当赘婿',
                'series_cover': 'https://p3.example.com/cover1.jpg',
                'episode_cnt': 80,
                'episode_right_text': '全80集',
                'series_intro': '五年前他是一代战神，五年后回归都市隐姓埋名...',
                'tags': ['都市', '战神', '爽文'],
              },
              {
                'series_id_str': '7345678901234567891',
                'series_title': '龙王令之至尊归来',
                'series_cover': 'https://p3.example.com/cover2.jpg',
                'episode_cnt': 100,
                'episode_right_text': '全100集',
                'series_intro': '十万龙王将士恭迎龙王回朝！',
                'tags': ['热血', '至尊'],
              }
            ]
          }
        }
      };

      final fakeHtml = '''
<!DOCTYPE html>
<html>
<head><title>短剧 - 分类</title></head>
<body>
<script>
window._ROUTER_DATA = ${jsonEncode(fakeRouterData)};
</script>
</body>
</html>
''';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/category/')) {
          return http.Response(fakeHtml, 200, headers: {'content-type': 'text/html; charset=utf-8'});
        }
        return http.Response('Not Found', 404);
      });

      final runtime = CatPawJsRuntime(mockClient);
      await runtime.init(hongguoScript);

      final catRes = await runtime.category('real-drama', 1);
      expect(catRes.list.length, equals(2));

      final first = catRes.list.first;
      expect(first['vod_id'], equals('7345678901234567890'));
      expect(first['vod_name'], equals('战神归来当赘婿'));
      expect(first['vod_pic'], equals('https://p3.example.com/cover1.jpg'));
      expect(first['vod_remarks'], equals('全80集'));
      expect(first['vod_content'], contains('一代战神'));
      expect(first['vod_tag'], contains('都市'));

      final second = catRes.list[1];
      expect(second['vod_id'], equals('7345678901234567891'));
      expect(second['vod_name'], equals('龙王令之至尊归来'));
      expect(second['vod_remarks'], equals('全100集'));

      runtime.dispose();
    });

    test('5. detail() 剧集详情与选集生成测试', () async {
      final fakeDetailRouterData = {
        'loaderData': {
          'detail': {
            'seriesDetail': {
              'series_id': '7345678901234567890',
              'series_name': '战神归来当赘婿',
              'series_cover': 'https://p3.example.com/cover1_large.jpg',
              'series_intro': '五年前一代战神横扫八荒，今朝龙隐于渊守护至爱...',
              'vid_list': ['vid_001', 'vid_002', 'vid_003', 'vid_004']
            }
          }
        }
      };

      final fakeDetailHtml = '''
<!DOCTYPE html>
<html>
<head><title>详情页</title></head>
<body>
<script>
window._ROUTER_DATA = ${jsonEncode(fakeDetailRouterData)};
</script>
</body>
</html>
''';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/detail')) {
          return http.Response(fakeDetailHtml, 200, headers: {'content-type': 'text/html; charset=utf-8'});
        }
        return http.Response('Not Found', 404);
      });

      final runtime = CatPawJsRuntime(mockClient);
      await runtime.init(hongguoScript);

      final detailRes = await runtime.detail('7345678901234567890');
      final vod = detailRes.vod;
      expect(vod, isNotEmpty);
      expect(vod['vod_name'], equals('战神归来当赘婿'));
      expect(vod['vod_pic'], equals('https://p3.example.com/cover1_large.jpg'));
      expect(vod['vod_remarks'], equals('全4集'));
      expect(vod['vod_play_from'], equals('官方直链'));

      final playUrl = vod['vod_play_url'] as String;
      expect(playUrl, isNotEmpty);
      final episodes = playUrl.split('#');
      expect(episodes.length, equals(4));
      expect(episodes[0], startsWith('第1集\$https://hongguoduanju.com/player/7345678901234567890/vid_001'));
      expect(episodes[1], startsWith('第2集\$https://hongguoduanju.com/player/7345678901234567890/vid_002'));
      expect(episodes[3], startsWith('第4集\$https://hongguoduanju.com/player/7345678901234567890/vid_004'));

      runtime.dispose();
    });

    test('6. play() 取流解析测试 (提取真实播放直链与防盗链 Headers)', () async {
      final fakePlayerHtml = '''
<!DOCTYPE html>
<html>
<head><title>播放器</title></head>
<body>
<script>
window.__INITIAL_DATA__ = {
  "video": {
    "main_url": "https://v9-dy-y.hongguoduanju.com/video/tos/cn/stream_hd.mp4?auth_key=123456"
  }
};
</script>
</body>
</html>
''';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/player/')) {
          return http.Response(fakePlayerHtml, 200, headers: {'content-type': 'text/html; charset=utf-8'});
        }
        return http.Response('Not Found', 404);
      });

      final runtime = CatPawJsRuntime(mockClient);
      await runtime.init(hongguoScript);

      final playRes = await runtime.play(
        'flag',
        'https://hongguoduanju.com/player/7345678901234567890/vid_001',
      );

      expect(playRes.url, equals('https://v9-dy-y.hongguoduanju.com/video/tos/cn/stream_hd.mp4?auth_key=123456'));
      expect(playRes.header['Referer'], equals('https://hongguoduanju.com/'));
      expect(playRes.header['User-Agent'], isNotEmpty);

      runtime.dispose();
    });

    test('7. search() 搜索联想与结果解析测试', () async {
      final fakeSuggestJson = {
        'code': 0,
        'suggest_list': [
          {
            'name': '重生后被霸总宠上天',
            'series_id': '7345678909999999991',
            'video_data': {
              'series_id': '7345678909999999991',
              'title': '重生后被霸总宠上天',
              'cover_url': 'https://p3.example.com/cover_search1.jpg',
              'episode_cnt': 95,
              'intro': '前世凄惨，重生归来逆袭人生...'
            }
          },
          {
            'name': '真假千金重逢时',
            'series_id': '7345678909999999992',
            'video_data': {
              'series_id': '7345678909999999992',
              'title': '真假千金重逢时',
              'cover_url': 'https://p3.example.com/cover_search2.jpg',
              'episode_cnt': 70,
              'intro': '豪门真千金归来复仇！'
            }
          }
        ]
      };

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/incent_resource/suggestion')) {
          return http.Response(jsonEncode(fakeSuggestJson), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final runtime = CatPawJsRuntime(mockClient);
      await runtime.init(hongguoScript);

      final searchRes = await runtime.search('重生', page: 1);
      expect(searchRes.list.length, equals(2));

      final item1 = searchRes.list[0];
      expect(item1['vod_id'], equals('7345678909999999991'));
      expect(item1['vod_name'], equals('重生后被霸总宠上天'));
      expect(item1['vod_pic'], equals('https://p3.example.com/cover_search1.jpg'));
      expect(item1['vod_remarks'], equals('全95集'));
      expect(item1['vod_content'], contains('逆袭人生'));

      final item2 = searchRes.list[1];
      expect(item2['vod_id'], equals('7345678909999999992'));
      expect(item2['vod_name'], equals('真假千金重逢时'));
      expect(item2['vod_remarks'], equals('全70集'));

      runtime.dispose();
    });

    test('8. 仓库纯净红线验证：assets/sources 仅允许包含 hongguo.js (其余源归属于本地 GitLab thlredguojs)', () {
      final sourcesDir = Directory('assets/sources');
      expect(sourcesDir.existsSync(), isTrue);

      final files = sourcesDir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.DS_Store'))
          .toList();

      final fileNames = files.map((f) => f.uri.pathSegments.last).toList();
      // 验证仅存在且只允许 hongguo.js
      expect(fileNames, equals(['hongguo.js']),
          reason: 'GitHub 仓库 assets/sources 目录严禁混入任何第三方数据源，其余源应保存在本地 GitLab thlredguojs 项目');
    });
  });
}
