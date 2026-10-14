import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/dart_core_engine.dart';
import 'package:THLRedLook/models/ranking/ranking_models.dart';

void main() {
  group('真实榜单与推荐引擎分发验证', () {
    late DartCoreEngine engine;

    setUp(() {
      engine = DartCoreEngine.instance;
    });

    test('RankingBoard.sourceForID 正确匹配所有预设榜单及通用前缀', () {
      expect(RankingBoard.sourceForID('hongguo-hot'), equals('hongguo'));
      expect(RankingBoard.sourceForID('hongguo-new'), equals('hongguo'));
      expect(RankingBoard.sourceForID('hongguo-search'), equals('hongguo'));
      expect(RankingBoard.sourceForID('hanxiaoquan-hot'), equals('hanxiaoquan'));
      expect(RankingBoard.sourceForID('yeguo-hot'), equals('yeguo'));
      expect(RankingBoard.sourceForID('huangdou-hot'), equals('huangdou'));
      expect(RankingBoard.sourceForID('dsd-hot'), equals('dsd'));
      expect(RankingBoard.sourceForID('customsource-top'), equals('customsource'));
    });

    test('未导入数据源时，榜单请求如实返回空态并提示导入，严禁假数据', () async {
      final res = await engine.dispatch({
        'action': 'rankings',
        'board': 'hongguo-hot',
        'page': 1,
      });
      expect(res['ok'], isTrue);
      final data = res['data'] as Map<String, dynamic>;
      final items = data['items'] as List;
      expect(items, isEmpty);
      expect(data['warning'], contains('请先在数据源管理中导入并启用'));
    });

    test('未导入数据源时，推荐请求如实返回空态并提示导入，严禁假数据', () async {
      final res = await engine.dispatch({
        'action': 'recommendations',
        'category': 'short_play',
        'page': 1,
      });
      expect(res['ok'], isTrue);
      final data = res['data'] as Map<String, dynamic>;
      final items = data['items'] as List;
      expect(items, isEmpty);
      expect(data['warning'], contains('请先在数据源管理中导入并启用'));
    });

    test('导入数据源脚本后，榜单与推荐可通过 Spider 正确抓取真实数据结构', () async {
      // 模拟注册一个标准 CatPawOpen Spider 脚本
      const testSpiderJs = '''
// { id: 'hongguo', name: '红果短剧', version: '1.0.0' }
async function category(tid, pg, filter, extend) {
  return {
    page: 1,
    pagecount: 2,
    limit: 20,
    total: 40,
    list: [
      {
        vod_id: "7001",
        vod_name: "热播剧测试一",
        vod_pic: "https://example.com/cover1.jpg",
        vod_remarks: "全80集",
        vod_content: "这是第一部测试热播剧"
      },
      {
        vod_id: "7002",
        vod_name: "热播剧测试二",
        vod_pic: "https://example.com/cover2.jpg",
        vod_remarks: "更新至45集",
        vod_content: "这是第二部测试热播剧"
      }
    ]
  };
}
var spider = {
  category: category
};
''';

      final saveRes = await engine.dispatch({
        'action': 'jsSource.load',
        'script': testSpiderJs,
      });
      expect(saveRes['ok'], isTrue);

      // 验证真实榜单调用
      final rankRes = await engine.dispatch({
        'action': 'rankings',
        'board': 'hongguo-hot',
        'page': 1,
      });
      expect(rankRes['ok'], isTrue);
      final rankData = rankRes['data'] as Map<String, dynamic>;
      expect(rankData['items'], isA<List>());
      final rankItems = rankData['items'] as List;
      expect(rankItems.length, equals(2));
      expect(rankItems[0]['rank'], equals(1));
      expect(rankItems[0]['drama']['title'], equals('热播剧测试一'));
      expect(rankItems[0]['metric'], equals('全80集'));
      expect(rankItems[1]['rank'], equals(2));
      expect(rankItems[1]['drama']['title'], equals('热播剧测试二'));

      // 验证真实推荐调用
      final recRes = await engine.dispatch({
        'action': 'recommendations',
        'category': 'short_play',
        'source': 'hongguo',
        'page': 1,
      });
      expect(recRes['ok'], isTrue);
      final recData = recRes['data'] as Map<String, dynamic>;
      expect(recData['items'], isA<List>());
      final recItems = recData['items'] as List;
      expect(recItems.length, equals(2));
      expect(recItems[0]['title'], equals('热播剧测试一'));
      expect(recItems[1]['title'], equals('热播剧测试二'));
    });
  });
}
