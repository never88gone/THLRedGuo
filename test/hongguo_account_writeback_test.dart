import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/account/hongguo_account_library.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';

class _Service extends HongguoAccountService {
  _Service(HongguoAccountSession session) : super(session: session);
  final favorites = <WatchEntry>[];
  final reports = <WatchEntry>[];
  WatchEntry? watch;
  bool fail = false;
  Completer<void>? gate;
  Completer<List<WatchEntry>>? historyResult;
  @override
  Future<List<WatchEntry>> library({required bool history}) async {
    if (history && historyResult != null) return historyResult!.future;
    return history ? [?watch] : favorites;
  }

  @override
  Future<WatchEntry?> progress(Drama drama) async => watch;
  @override
  Future<void> setFollowing(Drama drama, bool follow) async {
    if (fail) throw const HongguoAccountFailure('synthetic server rejection');
    favorites.removeWhere((row) => row.drama.id == drama.id);
    if (follow) favorites.add(entry(drama, 0));
  }

  @override
  Future<void> updateProgress(
    WatchEntry entry, {
    required String itemId,
  }) async {
    if (gate != null) await gate!.future;
    if (fail) throw const HongguoAccountFailure('synthetic server rejection');
    reports.add(entry);
    watch = entry;
  }
}

WatchEntry entry(Drama drama, double position) => WatchEntry(
  drama: drama,
  episode: 2,
  position: position,
  duration: 90,
  updatedAt: DateTime.now(),
);
const _id = '7345678901234567999';
final drama = Drama(
  id: 'hongguo:$_id',
  source: 'hongguo',
  sourceId: _id,
  title: '合成测试',
  cover: '',
  description: '',
  episodes: 8,
);
Future<void> login(HongguoAccountSession session, String id) async {
  final jar = HongguoAccountCookies()
    ..merge(Uri.parse('https://hongguoduanju.com/'), [
      'sessionid=synthetic-$id; Path=/; Secure',
    ]);
  await session.accept(jar, {
    'id': id,
    'nickname': 'synthetic',
  }, expectedRevision: session.revision);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HongguoAccountSession session;
  late _Service service;
  late HongguoAccountLibrary library;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    session = HongguoAccountSession();
    await session.bindProfile('writeback-test');
    service = _Service(session);
    library = HongguoAccountLibrary(service: service);
  });
  tearDown(() => library.dispose());
  test('官方写入成功后更新追剧，拒绝时保留已确认状态', () async {
    await login(session, '123');
    await library.toggle(drama);
    expect(library.following(drama.id), true);
    service.fail = true;
    await expectLater(
      library.toggle(drama),
      throwsA(isA<HongguoAccountFailure>()),
    );
    expect(library.following(drama.id), true);
    service.fail = false;
    await library.toggle(drama);
    expect(library.following(drama.id), false);
  });
  test('进度节流，切集或退出强制写入，允许向后拖动', () async {
    await login(session, '123');
    await library.report(entry(drama, 40), itemId: _id);
    await library.report(entry(drama, 45), itemId: _id);
    expect(service.reports.length, 1);
    await library.report(entry(drama, 10), itemId: _id, force: true);
    expect(service.reports.map((e) => e.position), [40, 10]);
    expect(library.watched(drama.id)!.position, 10);
  });
  test('排队期间切换账号，不把旧账号进度发给新账号', () async {
    await login(session, '123');
    final pending = library.report(entry(drama, 10), itemId: _id, force: true);
    final rejected = expectLater(
      pending,
      throwsA(isA<HongguoAccountFailure>()),
    );
    await session.logout();
    await login(session, '456');
    await rejected;
    expect(service.reports, isEmpty);
    expect(library.watched(drama.id), isNull);
  });
  test('较早上报仍在进行时，强制保存较低进度按最后操作覆盖', () async {
    await login(session, '123');
    await library.report(entry(drama, 10), itemId: _id, force: true);
    service.gate = Completer<void>();
    final older = library.report(entry(drama, 20), itemId: _id, force: true);
    await Future<void>.delayed(Duration.zero);
    final latest = library.report(entry(drama, 10), itemId: _id, force: true);
    service.gate!.complete();
    await Future.wait([older, latest]);
    expect(service.reports.map((row) => row.position), [10, 20, 10]);
    expect(library.watched(drama.id)!.position, 10);
  });
  test('上报失败后节流期间保持失败，强制保存可重新尝试', () async {
    await login(session, '123');
    service.fail = true;
    await expectLater(
      library.report(entry(drama, 10), itemId: _id),
      throwsA(isA<HongguoAccountFailure>()),
    );
    service.fail = false;
    await expectLater(
      library.report(entry(drama, 15), itemId: _id),
      throwsA(isA<HongguoAccountFailure>()),
    );
    expect(library.watched(drama.id), isNull);
    await library.report(entry(drama, 20), itemId: _id, force: true);
    expect(library.watched(drama.id)!.position, 20);
  });
  test('快速连续切换追剧按顺序执行，最终状态与两次操作一致', () async {
    await login(session, '123');
    await Future.wait([library.toggle(drama), library.toggle(drama)]);
    expect(library.following(drama.id), false);
  });
  test('账号追剧缓存尚未加载时，加入操作保持服务端已追剧状态', () async {
    await login(session, '123');
    service.favorites.add(entry(drama, 0));
    final store = LocalStore(
      await SharedPreferences.getInstance(),
      accountLibrary: library,
    );
    addTearDown(store.dispose);
    expect(store.isFavorite(drama.id), false);
    await store.toggleFavorite(drama);
    expect(store.isFavorite(drama.id), true);
    expect(service.favorites.single.drama.id, drama.id);
  });
  test('历史读取的旧响应不会覆盖请求期间已确认的新观看记录', () async {
    await login(session, '123');
    service.historyResult = Completer<List<WatchEntry>>();
    final oldRead = library.load(true);
    await library.report(entry(drama, 10), itemId: _id, force: true);
    service.historyResult!.complete([]);
    await oldRead;
    expect(library.entries(true).single.position, 10);
    service.historyResult = null;
    service.watch = null;
    await library.load(true, refresh: true);
    expect(library.entries(true), isEmpty);
  });
  test('单独查询续播进度不伪造最近观看历史', () async {
    await login(session, '123');
    service.watch = entry(drama, 20);
    await library.refreshProgress(drama);
    expect(library.watched(drama.id)!.position, 20);
    expect(library.entries(true), isEmpty);
  });
  test('登录只读写账号资料，旧本地记录和iCloud同步资料保持不变，退出恢复旧进度', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore(prefs, accountLibrary: library);
    addTearDown(store.dispose);
    await store.toggleFavorite(drama);
    await store.saveWatch(entry(drama, 65));
    final before = jsonEncode({
      for (final key in prefs.getKeys().toList()..sort()) key: prefs.get(key),
    });
    await login(session, '123');
    service.watch = entry(drama, 12);
    await store.prepareAccountDrama(drama);
    expect(store.watched(drama.id)!.position, 12);
    expect(store.isFavorite(drama.id), false);
    await store.toggleFavorite(drama);
    await store.saveWatch(entry(drama, 20), itemId: _id, force: true);
    expect(store.isFavorite(drama.id), true);
    final after = jsonEncode({
      for (final key in prefs.getKeys().toList()..sort()) key: prefs.get(key),
    });
    expect(after, before);
    await session.logout();
    expect(store.watched(drama.id)!.position, 65);
    expect(store.isFavorite(drama.id), true);
  });
}
