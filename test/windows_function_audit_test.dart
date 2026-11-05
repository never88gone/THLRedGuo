import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';
import 'package:THLRedLook/core/js/js_source_models.dart';
import 'package:THLRedLook/core/js/js_source_service.dart';
import 'package:THLRedLook/core/storage/app_storage.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/pages/downloads/downloads_page.dart';
import 'package:THLRedLook/pages/settings/resource_settings_page.dart';
import 'package:THLRedLook/pages/settings/playback_settings_page.dart';

class _Sources extends AppRepository {
  bool fail = true;
  Completer<void>? gate;
  @override
  Future<int> jsSourceScan() async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('synthetic scan failure');
    return 1;
  }

  @override
  Future<List<JsSourceMeta>> jsSourceList() async => [
    const JsSourceMeta(id: 'hongguo', name: '合成官方源', version: '999.0.0'),
  ];
  @override
  Future<bool> jsSourceSetActive(String source) async {
    if (fail) throw StateError('synthetic source failure');
    return true;
  }

  @override
  Future<bool> jsSourceSaveAndLoad(String script, String fileName) async {
    if (fail) throw StateError('synthetic import failure');
    return true;
  }

  @override
  Future<bool> jsSourceRemove(String source) async {
    if (fail) throw StateError('synthetic removal failure');
    return true;
  }

  @override
  Future<bool> jsSourceClearAll() async {
    if (fail) throw StateError('synthetic clear failure');
    return true;
  }

  @override
  Future<String> jsSourceGetActive() async => 'hongguo';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late DartCoreEngine engine;
  setUp(() async {
    engine = DartCoreEngine.instance;
    SharedPreferences.setMockInitialValues({});
    sandbox = await Directory.systemTemp.createTemp('THL-windows-audit-');
    await engine.dispatch({'action': 'initialize', 'directory': sandbox.path});
  });
  tearDown(() async {
    JsSourceService.current?.dispose();
    debugDefaultTargetPlatformOverride = null;
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'cache cleanup preserves source scripts, downloads, playback and unrelated temp data',
    () async {
      final cache = Directory(p.join(sandbox.path, 'application-cache'));
      final files = <String, int>{
        'pure_core/covers/synthetic-cache.bin': 37,
        'pure_core/sources/hongguo.js': 11,
        'pure_core/source_storage/settings.json': 13,
        'pure_core/downloads/synthetic-video.mp4': 19,
        'encrypted_playback/active.mp4': 23,
        'other-application/keep.bin': 29,
      };
      for (final entry in files.entries) {
        final file = File(p.join(cache.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(List.filled(entry.value, 1));
      }
      final unrelated = File(p.join(sandbox.path, 'other-temp-file.txt'));
      await unrelated.writeAsString('keep');
      final storage = AppCacheStorage(cache);
      expect(await storage.size(), 37);
      expect(await storage.clear(), 37);
      expect(await storage.size(), 0);
      for (final entry in files.entries.skip(1)) {
        expect(await File(p.join(cache.path, entry.key)).length(), entry.value);
      }
      expect(await unrelated.readAsString(), 'keep');
    },
  );

  test(
    'storage counts real files and Windows disk space for Unicode paths',
    () async {
      final directory = await Directory(p.join(sandbox.path, '审计 文件')).create();
      await File(
        p.join(directory.path, 'a.bin'),
      ).writeAsBytes(List.filled(17, 0));
      await File(
        p.join(directory.path, 'b.bin'),
      ).writeAsBytes(List.filled(29, 0));
      expect(await directoryBytes(directory), 46);
      if (Platform.isWindows) {
        expect(availableDiskBytes(directory.path), greaterThan(0));
      }
      final info = await engine.dispatch({'action': 'storage'});
      expect(info['ok'], true);
      expect(info['data']['usedBytes'], 0);
    },
  );

  test(
    'download cannot manufacture a completed job or a 32-byte video',
    () async {
      expect(NativeRepository().supportsDownloads, false);
      final result = await engine.dispatch({
        'action': 'enqueueDownloads',
        'drama': {'id': 'hongguo:synthetic', 'source': 'hongguo'},
        'entries': [
          {
            'index': 1,
            'chapter': {'url': 'https://synthetic.invalid/movie.mp4'},
          },
        ],
      });
      expect(result['ok'], false);
      expect(result['error'], contains('尚未实现'));
      expect(
        (await engine.dispatch({'action': 'downloads'}))['data']['jobs'],
        isEmpty,
      );
      expect(
        await Directory(
          p.join(sandbox.path, 'pure_core', 'downloads'),
        ).list().toList(),
        isEmpty,
      );
    },
  );

  for (final action in [
    'moveDownloads',
    'lan',
    'saveResourceSettings',
    'updateSystemProxy',
    'sourceJob',
    'unknownOperation',
  ]) {
    test(
      '$action reports an unsupported operation instead of success',
      () async {
        final result = await engine.dispatch({'action': action});
        expect(result['ok'], false);
        expect(result['error'], contains('尚未'));
      },
    );
  }

  test(
    'leases count concurrent owners and unmatched ends cannot erase another lease',
    () async {
      Future<int> lease(String id, String command) async =>
          (await engine.dispatch({
                'action': 'workLease',
                'jobId': id,
                'command': command,
              }))['data']['count']
              as int;
      expect(await lease('media', 'start'), 1);
      expect(await lease('media', 'start'), 2);
      expect(await lease('storage', 'start'), 3);
      expect(await lease('unknown', 'end'), 3);
      expect(await lease('media', 'end'), 2);
      expect(await lease('media', 'end'), 1);
      expect(await lease('storage', 'end'), 0);
    },
  );

  test(
    'source paths cannot escape and loading then saving still persists the script',
    () async {
      final script = File('assets/sources/hongguo.js').readAsStringSync();
      for (final fileName in [
        '../outside.js',
        r'..\outside.js',
        'D:/outside.js',
        'bad:stream.js',
      ]) {
        final result = await engine.dispatch({
          'action': 'jsSource.saveAndLoad',
          'script': script,
          'fileName': fileName,
        });
        expect(result['ok'], false, reason: fileName);
      }
      await engine.dispatch({
        'action': 'jsSource.load',
        'script': script,
        'fileName': 'hongguo.js',
      });
      expect(
        (await engine.dispatch({
          'action': 'jsSource.saveAndLoad',
          'script': script,
          'fileName': 'hongguo.js',
        }))['ok'],
        true,
      );
      expect(
        await File(
          p.join(sandbox.path, 'pure_core', 'sources', 'hongguo.js'),
        ).readAsString(),
        script,
      );
    },
  );

  test(
    'missing detail source cannot fabricate episode IDs from an episode count',
    () async {
      final result = await engine.dispatch({
        'action': 'detail',
        'drama': {
          'id': 'missing:synthetic',
          'source': 'missing',
          'episodes': 80,
        },
      });
      expect(result['ok'], false);
      expect(result.containsKey('data'), false);
    },
  );

  test(
    'unknown metadata is not replaced with invented heat or dates',
    () async {
      final result = await engine.dispatch({
        'action': 'metadata',
        'drama': {'id': 'hongguo:synthetic'},
      });
      expect((result['data']['drama'] as Map).containsKey('onlineDate'), false);
      expect((result['data']['drama'] as Map).containsKey('heat'), false);
    },
  );

  test(
    'source initialization can retry after failure and releases loading state',
    () async {
      final repository = _Sources();
      final service = JsSourceService(repository);
      await expectLater(service.initialize(), throwsStateError);
      expect(service.loading, false);
      expect(service.initialized, false);
      repository.fail = false;
      await service.initialize();
      expect(service.initialized, true);
      expect(service.loading, false);
      expect(service.activeSourceId, 'hongguo');
      repository.fail = true;
      for (final operation in <Future<dynamic> Function()>[
        () => service.importScript('synthetic', 'hongguo.js'),
        () => service.removeSource('hongguo'),
        service.reload,
        service.clearAll,
      ]) {
        await expectLater(operation(), throwsStateError);
        expect(service.loading, false);
      }
    },
  );

  for (final size in [
    const Size(640, 480),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('Windows settings and unavailable download layout fit $size', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = NativeRepository()..access = store;
      for (final screen in <Widget>[
        PlaybackSettingsPage(store: store),
        ResourceSettingsScreen(repository: repository, store: store),
        DownloadsScreen(repository: repository, store: store),
      ]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('当前版本尚未提供下载'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
