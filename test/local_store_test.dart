import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalStore 本地存储与持久化核心自动化测试', () {
    late SharedPreferences prefs;
    late LocalStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      store = LocalStore(prefs);
    });

    test('1. 追剧收藏 (Favorites) 添加、查询与取消', () async {
      final drama = Drama(
        id: 'hongguo:7345678901234567890',
        source: 'hongguo',
        sourceId: '7345678901234567890',
        title: '万界至尊战神',
        episodes: 80,
      );

      expect(store.isFavorite(drama.id), isFalse);

      await store.toggleFavorite(drama);
      expect(store.isFavorite(drama.id), isTrue);
      expect(store.favorites.length, equals(1));
      expect(store.favorites.first.title, equals('万界至尊战神'));

      // 再次切换则取消追剧
      await store.toggleFavorite(drama);
      expect(store.isFavorite(drama.id), isFalse);
      expect(store.favorites, isEmpty);
    });

    test('2. 观看历史 (History) 与秒级断点记录测试', () async {
      final drama = Drama(
        id: 'hongguo:7345678901234567890',
        source: 'hongguo',
        sourceId: '7345678901234567890',
        title: '万界至尊战神',
        episodes: 80,
      );

      final entry1 = WatchEntry(
        drama: drama,
        episode: 3,
        position: 125.5,
        duration: 180.0,
        updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await store.saveWatch(entry1);

      final saved = store.watched(drama.id);
      expect(saved, isNotNull);
      expect(saved!.episode, equals(3));
      expect(saved.position, equals(125.5));
      expect(saved.duration, equals(180.0));
      expect(saved.finished, isFalse);

      // 模拟播完第 3 集（position >= duration - 1）
      final entryFinished = WatchEntry(
        drama: drama,
        episode: 3,
        position: 180.0,
        duration: 180.0,
        updatedAt: DateTime.now(),
      );
      await store.saveWatch(entryFinished);
      final savedFinished = store.watched(drama.id);
      expect(savedFinished!.finished, isTrue);

      // 单项移除历史
      await store.removeHistory(drama.id);
      expect(store.watched(drama.id), isNull);
    });

    test('3. 历史记录清空 (clearHistory) 测试', () async {
      final d1 = Drama(id: 'hongguo:1', source: 'hongguo', sourceId: '1', title: '剧集1');
      final d2 = Drama(id: 'hongguo:2', source: 'hongguo', sourceId: '2', title: '剧集2');

      await store.saveWatch(WatchEntry(
        drama: d1,
        episode: 1,
        position: 10,
        duration: 60,
        updatedAt: DateTime.now(),
      ));
      await store.saveWatch(WatchEntry(
        drama: d2,
        episode: 2,
        position: 20,
        duration: 60,
        updatedAt: DateTime.now(),
      ));

      expect(store.history.length, equals(2));

      await store.clearHistory();
      expect(store.history, isEmpty);
    });

    test('4. 隐私数据源模式与特定源观看历史脱敏测试', () async {
      final hongguoDrama = Drama(
        id: 'hongguo:888',
        source: 'hongguo',
        sourceId: '888',
        title: '隐秘短剧',
      );

      await store.saveWatch(WatchEntry(
        drama: hongguoDrama,
        episode: 1,
        position: 30,
        duration: 100,
        updatedAt: DateTime.now(),
      ));

      expect(store.history.any((e) => e.drama.id == 'hongguo:888'), isTrue);
      expect(store.watched('hongguo:888'), isNotNull);

      // 将特定源设置为隐私数据源
      await store.setSourcePrivate('hongguo', true);
      expect(store.isPrivateSource('hongguo'), isTrue);

      // 在常规公开历史列表中，隐私源的记录必须被自动脱敏过滤
      expect(store.history.any((e) => e.drama.source == 'hongguo'), isFalse);
      expect(store.watched('hongguo:888'), isNull);

      // 解除隐私模式后可重新查阅
      await store.setSourcePrivate('hongguo', false);
      expect(store.isPrivateSource('hongguo'), isFalse);
      expect(store.watched('hongguo:888'), isNotNull);
    });

    test('5. 站源密码锁 (Source Gate) 启用与解锁验证', () async {
      expect(store.sourceGateEnabled, isFalse);

      await store.enableSourceGate('123456');
      expect(store.sourceGateEnabled, isTrue);
      expect(store.sourcesUnlocked, isTrue);

      // 锁定
      store.lockSources();
      expect(store.sourcesUnlocked, isFalse);

      // 密码错误时应拒绝解锁
      expect(
        () async => await store.unlockSources('000000'),
        throwsA(isA<StateError>()),
      );
      expect(store.sourcesUnlocked, isFalse);

      // 正确密码解锁
      await store.unlockSources('123456');
      expect(store.sourcesUnlocked, isTrue);

      // 关闭密码锁，恢复不使用密码状态
      await store.disableSourceGate();
      expect(store.sourceGateEnabled, isFalse);
      expect(store.sourceGateOff, isTrue);
    });
  });
}
