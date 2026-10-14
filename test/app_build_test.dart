import 'dart:convert';

import 'package:THLRedLook/app_build.dart';
import 'package:THLRedLook/core_bridge.dart';
import 'package:THLRedLook/local_profiles.dart';
import 'package:THLRedLook/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const red = FixtureRepository.free;
  const other = FixtureRepository.vip;

  test('edition sources include DSD only in the all-source build', () async {
    SharedPreferences.setMockInitialValues({'source': 'huangdou'});
    final store = testStore(await SharedPreferences.getInstance());
    expect(appSlug, allSourcesEnabled ? 'zhenguojian' : 'hongguojian');
    // 默认只显示红果、韩小圈、鬼片网与青空次元，其余站源需要密码解锁。
    expect(store.sources.length, 4);
    expect(
      SourceSite.values.any((source) => source.id == 'dsd'),
      allSourcesEnabled,
    );
    expect(SourceSite.isAvailable('dsd'), isTrue);
    expect(SourceSite.isKnown('dsd'), isTrue);
    expect(SourceSite.byId('dsd').name, '帝果');
    expect(store.allowsSource('dsd'), isFalse);
    expect(store.source, 'hongguo');
    await store.enableSourceGate('666666');
    expect(store.sourcesUnlocked, isTrue);
    expect(store.sources.length, 11);
    expect(store.allowsSource('dsd'), isTrue);
    store.dispose();
  });

  test(
    'edition filtering preserves favorites and history through backup restore',
    () async {
      final history = [
        for (final drama in [red, other])
          WatchEntry(
            drama: drama,
            episode: 1,
            position: 12,
            duration: 60,
            updatedAt: DateTime(2026, 9, 19),
          ).toJson(),
      ];
      SharedPreferences.setMockInitialValues({
        'source': 'huangdou',
        'favorites': jsonEncode([red.toJson(), other.toJson()]),
        'history': jsonEncode(history),
      });
      final store = testStore(await SharedPreferences.getInstance());
      // 管理员默认可见全部站源；这里仍显式启用密码锁，验证启用后行为一致。
      await store.enableSourceGate('666666');
      expect(store.favorites.length, 2);
      expect(store.history.length, 2);
      expect(store.isFavorite(other.id), isTrue);
      expect(store.watched(other.id) != null, isTrue);
      await store.toggleFavorite(red);
      final backup = await store.exportBackup();
      final library =
          (jsonDecode(backup)['libraries'] as Map)['default'] as Map;
      expect((library['favorites'] as List).map((row) => (row as Map)['id']), [
        other.id,
      ]);
      expect(library['history'], hasLength(2));
      await store.importBackup(backup);
      if (allSourcesEnabled) await store.unlockSources('666666');
      expect(store.history, hasLength(allSourcesEnabled ? 2 : 1));
      expect(store.favorites.map((drama) => drama.id), allSourcesEnabled ? [other.id] : isEmpty);
      store.dispose();
    },
  );

  test(
    'a restored foreign-source profile keeps its identity and permissions',
    () async {
      SharedPreferences.setMockInitialValues({
        ...await gatePreferences(),
        'profiles': jsonEncode([
          LocalProfile(
            id: 'default',
            name: '管理员',
            admin: true,
            salt: '0' * 32,
            pinHash: '1' * 64,
          ).toJson(),
          const LocalProfile(
            id: 'viewer',
            name: '已有用户',
            sources: ['huangdou'],
            download: false,
          ).toJson(),
        ]),
        'activeProfile': 'viewer',
        'profile.viewer.source': 'huangdou',
      });
      final store = testStore(await SharedPreferences.getInstance());
      await unlockGate(store);
      expect(store.profile.id, 'viewer');
      expect(store.profile.admin, isFalse);
      expect(store.profile.sources, ['huangdou']);
      expect(store.canDownload, isFalse);
      expect(store.source, 'huangdou');
      expect(store.allowsSource('hongguo'), isFalse);
      expect(store.allowsSource('huangdou'), isTrue);
      store.dispose();
    },
  );

  test('restored DSD profile data follows edition availability', () async {
    SharedPreferences.setMockInitialValues({
      ...await gatePreferences(),
      'profiles': jsonEncode([
        LocalProfile(
          id: 'default',
          name: '管理员',
          admin: true,
          salt: '0' * 32,
          pinHash: '1' * 64,
        ).toJson(),
        const LocalProfile(
          id: 'viewer',
          name: '帝果旧用户',
          sources: ['dsd'],
          download: false,
        ).toJson(),
      ]),
      'activeProfile': 'viewer',
      'profile.viewer.source': 'dsd',
    });
    final store = testStore(await SharedPreferences.getInstance());
    await unlockGate(store);
    expect(store.configurationError, isNull);
    expect(store.profile.sources, ['dsd']);
    expect(
      store.sources.map((source) => source.id),
      ['dsd'],
    );
    expect(store.source, 'dsd');
    expect(store.allowsSource('dsd'), isTrue);
    store.dispose();
  });

  test(
    'background requests reject unavailable sources before native I/O',
    () async {
      final repository = NativeRepository(background: true);
      final denied = [
        ...SourceSite.allValues
            .where((source) => !SourceSite.isAvailable(source.id))
            .map((source) => source.id),
        'unknown',
      ];
      for (final source in denied) {
        final drama = Drama(id: '$source:123', source: source, title: '合成数据');
        final episode = Episode({'id': '1'}, 1);
        for (final request in [
          () => repository.catalog(source),
          () => repository.cached(source),
          () => repository.sourceStatus(source),
          () => repository.startSourceJob(source, 'update'),
          () => repository.cancelSourceJob(source),
          () => repository.detail(drama),
          () => repository.cover(drama),
          () => repository.resolve(drama, episode),
          () => repository.resolveOnline(drama, episode),
          () => repository.enqueueDownloads(DramaDetail(drama, [episode]), [
            episode,
          ]),
          () => repository.localPlayback(drama, episode),
        ]) {
          await expectLater(
            request(),
            throwsA(
              isA<AppFailure>().having(
                (error) => error.message,
                'message',
                '当前版本不包含此站源',
              ),
            ),
          );
        }
      }
    },
  );
}
