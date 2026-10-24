import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DartCoreEngine engine;
  final script =
      File('assets/sources/hongguo.js').readAsStringSync() +
      r'''
function syntheticCell(offset, selectors) {
  return {
    cell_id_str:'synthetic',cell_data:[],next_offset:offset+6,has_more:true,
    session_id:'synthetic-session',
    cell_selector:selectors?{outer_row:{items:['all','playlet','motion_comic','ai_playlet'].map(id=>({selector_item_id:id,show_name:id,is_selected:id==='all'}))}}:undefined,
    video_data:Array.from({length:6},(_,i)=>({series_id_str:'7688558312157088'+String(100+offset+i),title:'合成剧'+(offset+i),episode_cnt:20}))
  };
}
globalThis.fetch = async function(url) {
  const path=String(url);
  let data;
  if(path.includes('/service/2/device_register/')) data={device_id_str:'7345678901234567100',install_id_str:'7345678901234567200'};
  else if(path.includes('/bookmall/tab/v')) data={code:0,data:{tab_item:[{tab_type:8,cell_data:[syntheticCell(0,true)]}]}};
  else if(path.includes('/bookmall/cell/change/v')) {
    const offset=Number(/[?&]offset=(\d+)/.exec(path)?.[1]||0);
    data={code:0,data:{cell_view:syntheticCell(offset,false),next_offset:offset+6,has_more:true,session_id:'synthetic-session'}};
  } else if(path.includes('/search/tab/v')) data={code:0,search_tabs:[{tab_type:29,has_more:false,next_offset:0,data:[{video_data:[{series_id:'7688558312157088001',title:'合成搜索剧'}]}]}]};
  else throw new Error('Unexpected synthetic endpoint');
  return {status:200,headers:{},text:async()=>JSON.stringify(data)};
};
''';
  setUpAll(() async {
    engine = DartCoreEngine.instance;
    final loaded = await engine.dispatch({
      'action': 'jsSource.load',
      'script': script,
      'fileName': 'hongguo.js',
    });
    expect(loaded['ok'], true);
  });
  test(
    'categories use the App menu rather than legacy static choices',
    () async {
      final result = await engine.dispatch({
        'action': 'categories',
        'source': 'hongguo',
      });
      expect(result['ok'], true);
      expect(
        ((result['data'] as Map)['items'] as List).map((row) => row['id']),
        [
          'app:discover:all',
          'app:discover:playlet',
          'app:discover:motion_comic',
          'app:discover:ai_playlet',
        ],
      );
    },
  );
  for (final genre in ['all', 'playlet', 'motion_comic', 'ai_playlet']) {
    test(
      'Flutter $genre first batch fills viewport and next page keeps cursor',
      () async {
        Future<Map> page(int number) async {
          final result = await engine.dispatch({
            'action': 'catalog',
            'source': 'hongguo',
            'category': 'app:discover:$genre',
            'page': number,
          });
          expect(result['ok'], true, reason: result.toString());
          return result['data'] as Map;
        }

        final first = await page(1);
        expect(first['items'], hasLength(12));
        expect(first['hasMore'], true);
        final cached = await engine.dispatch({
          'action': 'cached',
          'source': 'hongguo',
          'category': 'app:discover:$genre',
        });
        expect((cached['data'] as Map)['items'], hasLength(12));
        final second = await page(2);
        expect(second['items'], hasLength(6));
        final ids = [
          for (final row in [
            ...first['items'] as List,
            ...second['items'] as List,
          ])
            row['id'],
        ];
        expect(ids.toSet(), hasLength(18));
        expect(
          (second['items'] as List).first['sourceId'],
          '7688558312157088112',
        );
      },
    );
  }
  test(
    'search returns its available first result without catalog batch filling',
    () async {
      final result = await engine.dispatch({
        'action': 'catalog',
        'source': 'hongguo',
        'query': '合成搜索',
        'page': 1,
      });
      expect(result['ok'], true);
      expect((result['data'] as Map)['items'], hasLength(1));
      expect((result['data'] as Map)['hasMore'], false);
    },
  );
  test(
    'official category failure remains retryable and does not return legacy menu',
    () async {
      await engine.dispatch({
        'action': 'jsSource.load',
        'script':
            '$script\nspider.home=async function(){throw new Error(\'合成官方分类失败\')};',
        'fileName': 'hongguo.js',
      });
      final result = await engine.dispatch({
        'action': 'categories',
        'source': 'hongguo',
      });
      expect(result['ok'], false);
      expect(result['error'], contains('合成官方分类失败'));
    },
  );
}
