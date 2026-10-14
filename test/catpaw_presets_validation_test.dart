import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/catpaw_js_runtime.dart';
import 'package:THLRedLook/js_source_presets.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  group('CatPawOpen 预置 Spider 脚本与真实 JS 沙箱执行验证', () {
    test('预设数据源覆盖红果且无旧私有方法名', () {
      expect(kPresetJsSources.length, equals(1));
      final ids = <String>{};

      for (final preset in kPresetJsSources) {
        expect(preset.fileName.endsWith('.js'), isTrue);
        expect(preset.script, contains('var spider = {'));
        expect(preset.script, contains('meta: meta'));
        expect(preset.script, contains('init: init'));
        expect(preset.script, contains('home: home'));
        expect(preset.script, contains('category: category'));
        expect(preset.script, contains('detail: detail'));
        expect(preset.script, contains('play: play'));
        expect(preset.script, contains('search: search'));

        // 绝无旧私有协议特有方法名
        expect(preset.script.contains('getCatalog'), isFalse, reason: '${preset.fileName} 不应包含 getCatalog');
        expect(preset.script.contains('getDetail'), isFalse, reason: '${preset.fileName} 不应包含 getDetail');
        expect(preset.script.contains('getPlayUrl'), isFalse, reason: '${preset.fileName} 不应包含 getPlayUrl');
        expect(preset.script.contains('getCategories'), isFalse, reason: '${preset.fileName} 不应包含 getCategories');
        expect(preset.script.contains('getSuggestions'), isFalse, reason: '${preset.fileName} 不应包含 getSuggestions');

        final idMatch = RegExp(r'id:\s*["\x27]([^"\x27]+)["\x27]').firstMatch(preset.script);
        expect(idMatch, isNotNull);
        ids.add(idMatch!.group(1)!);
      }

      expect(ids, containsAll(['hongguo']));
    });

    test('全部 5 个预置源在 CatPawJsRuntime 沙箱中均能正确执行生命周期并导出标准接口', () async {
      for (final preset in kPresetJsSources) {
        final runtime = CatPawJsRuntime();
        addTearDown(runtime.dispose);

        await runtime.init(preset.script);
        expect(runtime.isReady, isTrue);

        // 1. 读取元数据
        final meta = await runtime.getMeta();
        expect(meta['id'], isNotEmpty);
        expect(meta['name'], isNotEmpty);

        // 2. 首页分类
        final homeRes = await runtime.home();
        expect(homeRes.classes, isNotEmpty, reason: '${preset.fileName} home() 应返回分类');
        final firstTid = homeRes.classes.first['type_id']?.toString() ?? '';
        expect(firstTid, isNotEmpty);

        // 3. 分类目录（真实抓取，无兜底假数据）
        final catRes = await runtime.category(firstTid, 1);
        expect(catRes.list, isA<List>());

        if (catRes.list.isNotEmpty) {
          final firstVod = catRes.list.first;
          expect(firstVod['vod_id'], isNotNull);
          expect(firstVod['vod_name'], isNotNull);

          // 4. 详情与选集
          final targetId = firstVod['vod_id'].toString();
          final detailRes = await runtime.detail(targetId);
          final vod = detailRes.vod;
          if (vod.isNotEmpty) {
            expect(vod['vod_name'], isNotNull);
            final playUrlStr = vod['vod_play_url']?.toString() ?? '';
            if (playUrlStr.isNotEmpty) {
              expect(playUrlStr, contains(r'$'));

              // 5. 播放地址解析
              final firstEpRaw = playUrlStr.split('#').first;
              final epParts = firstEpRaw.split(r'$');
              final playId = epParts.length > 1 ? epParts[1] : targetId;
              final playRes = await runtime.play('flag', playId);
              expect(playRes.url, isA<String>());
            }
          }
        }

        // 6. 搜索接口
        final searchRes = await runtime.search('测试', page: 1);
        expect(searchRes.list, isA<List>());
      }
    });
  });
}
