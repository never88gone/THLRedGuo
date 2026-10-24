import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/core/sync/icloud_sync_service.dart';
import 'package:THLRedLook/models/catalog/models.dart';

void main() => runICloudRegressionTests();

void runICloudRegressionTests({String? fixtureJson}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('duanju/icloud.regression');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LocalStore store;
  late ICloudSyncService service;
  late Map<String, String> cloud;
  late List<String> writes;
  late Map<String, dynamic> fixture;
  Future<void> Function(String)? beforeRead;
  var available = true;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = LocalStore(prefs);
    await prefs.setBool(ICloudSyncService.prefSyncEnabled, true);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    service = ICloudSyncService.testing(channel);
    fixture =
        jsonDecode(
              fixtureJson ??
                  File(
                    'test/fixtures/icloud_flutter_v1.json',
                  ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    cloud = {
      ICloudSyncService.keyHistory: jsonEncode(fixture['history']),
      ICloudSyncService.keyFollows: jsonEncode(fixture['follows']),
      ICloudSyncService.keySettings: jsonEncode(fixture['settings']),
    };
    writes = [];
    beforeRead = null;
    available = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      final key = args?['key'] as String?;
      switch (call.method) {
        case 'synchronize':
          return available;
        case 'getString':
          final value = cloud[key];
          await beforeRead?.call(key!);
          return value;
        case 'setString':
          writes.add(key!);
          cloud[key] = args!['value'] as String;
          return true;
      }
      return null;
    });
  });

  tearDown(() async {
    await ICloudSyncService.instance.setSyncEnabled(false, store);
    service.dispose();
    store.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'shared fixture matches Flutter serializer with exact long ID and UTC fractions',
    () {
      final entry = WatchEntry.fromJson(
        Map<String, dynamic>.from((fixture['history'] as List).single as Map),
      );
      expect(entry.toJson(), (fixture['history'] as List).single);
      expect(entry.drama.cleanSourceId, '7688558312157088793');
      expect(entry.updatedAt.microsecond, 456);
    },
  );

  test(
    'tvOS compatible payload merges favorites and history without echo upload',
    () async {
      final history = jsonDecode(cloud[ICloudSyncService.keyHistory]!) as List;
      (history.single as Map)['updatedAt'] = '2026-10-24T08:05:01Z';
      (history.single as Map)['drama'].remove('metadataSchema');
      cloud[ICloudSyncService.keyHistory] = jsonEncode(history);
      final follows = jsonDecode(cloud[ICloudSyncService.keyFollows]!) as Map;
      (follows['follows'] as Map)['hongguo:7688558312157088793'] = 'wishlist';
      cloud[ICloudSyncService.keyFollows] = jsonEncode(follows);
      await service.syncWithCloud(store);
      expect(store.history.single.episode, 3);
      expect(store.history.single.position, 45.25);
      expect(store.favorites.single.id, 'hongguo:7688558312157088793');
      expect(store.playbackPreferences.danmaku, false);
      await service.syncWithCloud(store);
      expect(writes, isEmpty);
    },
  );

  test(
    'new local history is uploaded once and the next pull does not rewrite metadata',
    () async {
      final remote = WatchEntry.fromJson(
        Map<String, dynamic>.from((fixture['history'] as List).single as Map),
      );
      await store.saveWatch(
        WatchEntry(
          drama: remote.drama,
          episode: 7,
          position: 61,
          duration: 120,
          updatedAt: remote.updatedAt.add(const Duration(hours: 1)),
        ),
      );
      await service.syncWithCloud(store);
      expect(
        (jsonDecode(cloud[ICloudSyncService.keyHistory]!) as List)
            .single['episode'],
        7,
      );
      expect(
        writes.where((key) => key == ICloudSyncService.keyHistory),
        hasLength(1),
      );
      final count = writes.length;
      await service.syncWithCloud(store);
      expect(writes.length, count);
    },
  );

  test(
    'notification while reading triggers a second pull with the latest progress',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var held = false;
      beforeRead = (key) async {
        if (key == ICloudSyncService.keyHistory && !held) {
          held = true;
          entered.complete();
          await release.future;
        }
      };
      final pending = service.syncWithCloud(store);
      await entered.future;
      final history = jsonDecode(cloud[ICloudSyncService.keyHistory]!) as List;
      (history.single as Map)['episode'] = 9;
      (history.single as Map)['updatedAt'] = '2026-10-24T09:05:01.123456Z';
      cloud[ICloudSyncService.keyHistory] = jsonEncode(history);
      await service.syncWithCloud(store);
      release.complete();
      await pending;
      for (
        var i = 0;
        i < 100 && (service.isSyncing || store.history.single.episode != 9);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(store.history.single.episode, 9);
    },
  );

  test(
    'disabling sync during a read preserves local data and cancels upload',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      beforeRead = (key) async {
        if (key == ICloudSyncService.keyHistory) {
          entered.complete();
          await release.future;
        }
      };
      final pending = service.syncWithCloud(store);
      await entered.future;
      await service.setSyncEnabled(false, store);
      release.complete();
      await pending;
      expect(store.history, isEmpty);
      expect(writes, isEmpty);
      expect(service.lastStatusMessage, '已停用');
    },
  );

  test(
    'bad record preserves the original cloud value and imports other records',
    () async {
      final history = jsonDecode(cloud[ICloudSyncService.keyHistory]!) as List;
      history.insert(0, {'drama': false, 'updatedAt': false});
      final raw = jsonEncode(history);
      cloud[ICloudSyncService.keyHistory] = raw;
      await service.syncWithCloud(store);
      expect(store.history, hasLength(1));
      expect(cloud[ICloudSyncService.keyHistory], raw);
      expect(service.lastStatusMessage, contains('格式不兼容'));
    },
  );

  test(
    'old playback cache uploads on startup without replaying or changing timestamps',
    () async {
      const backupPath = String.fromEnvironment('OLD_HISTORY_LOCAL_BACKUP');
      final rows = backupPath.isNotEmpty
          ? jsonDecode(File(backupPath).readAsStringSync()) as List
          : List.generate(180, (index) {
              final row = Map<String, dynamic>.from(
                (fixture['history'] as List).single as Map,
              );
              row['drama'] = {
                ...Map<String, dynamic>.from(row['drama'] as Map),
                'id': 'hongguo:old-ios-$index',
                'sourceId': 'old-ios-$index',
                'title': '旧记录合成剧 $index',
                'cover': '',
              };
              row['episode'] = index % 24 + 1;
              row['position'] = index + 0.25;
              row['duration'] = 300;
              row['updatedAt'] = DateTime(
                2026,
                9,
                1,
                10,
                index,
              ).toIso8601String();
              return row;
            });
      store.dispose();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'history': jsonEncode(rows),
        'favorites': jsonEncode((fixture['follows'] as Map)['dramas']),
      });
      final prefs = await SharedPreferences.getInstance();
      store = LocalStore(prefs);
      await prefs.setBool(ICloudSyncService.prefSyncEnabled, true);
      await prefs.setInt(
        ICloudSyncService.prefLastSyncDate,
        DateTime.now().millisecondsSinceEpoch,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(store.history, hasLength(rows.length));
      final expected = [
        for (final entry in store.history)
          {
            'id': entry.drama.id,
            'episode': entry.episode,
            'position': entry.position,
            'duration': entry.duration,
            'updatedAtMillis': entry.updatedAt.millisecondsSinceEpoch,
          },
      ];
      cloud.clear();
      service.initialize(store);
      for (
        var i = 0;
        i < 300 &&
            (!cloud.containsKey(ICloudSyncService.keyHistory) ||
                service.isSyncing);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final uploaded = jsonDecode(cloud[ICloudSyncService.keyHistory]!) as List;
      expect(uploaded, hasLength(rows.length));
      final byId = {
        for (final row in uploaded) (row['drama'] as Map)['id']: row,
      };
      for (final row in expected) {
        final actual = byId[row['id']]!;
        expect(actual['episode'], row['episode']);
        expect(actual['position'], row['position']);
        expect(actual['duration'], row['duration']);
        expect(
          DateTime.parse(actual['updatedAt'] as String).millisecondsSinceEpoch,
          row['updatedAtMillis'],
        );
        expect(actual['updatedAt'], endsWith('Z'));
      }
      expect(store.favorites, hasLength(1));
      final writeCount = writes.length;
      await service.syncWithCloud(store);
      expect(writes.length, writeCount);
      const exportPath = String.fromEnvironment('OLD_HISTORY_EXPORT');
      if (exportPath.isNotEmpty) {
        await File(exportPath).writeAsString(
          jsonEncode({
            'history': cloud[ICloudSyncService.keyHistory],
            'expected': expected,
            'count': rows.length,
          }),
        );
      }
    },
  );

  test('unavailable iCloud is reported as failure and never uploads', () async {
    available = false;
    await service.syncWithCloud(store);
    expect(store.history, isEmpty);
    expect(writes, isEmpty);
    expect(service.lastSyncDate, isNull);
    expect(service.lastStatusMessage, contains('失败'));
  });
}
