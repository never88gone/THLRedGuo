import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/core/store/saved_library.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/account/account_page.dart';

class _Repo extends AppRepository {
  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('游客我的保留本地追剧和历史，窄屏与宽屏分类及设置入口可用', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final session = HongguoAccountSession.shared;
    await session.bindProfile('synthetic-guest-library');
    final store = LocalStore(await SharedPreferences.getInstance());
    const drama = Drama(
      id: 'hongguo:123',
      source: 'hongguo',
      title: '合成追剧',
      episodes: 10,
    );
    const watched = Drama(
      id: 'hongguo:456',
      source: 'hongguo',
      title: '合成历史',
      episodes: 10,
    );
    await store.toggleFavorite(drama);
    await store.saveWatch(
      WatchEntry(
        drama: watched,
        episode: 3,
        position: 20,
        duration: 90,
        updatedAt: DateTime(2026),
      ),
    );
    final repo = _Repo();
    var settings = 0;
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountScreen(
            repository: repo,
            store: store,
            onOpen: (_) {},
            onOpenSettings: () => settings++,
            localLibraryBuilder: (history) => SavedLibrary(
              key: ValueKey(history),
              repository: repo,
              store: store,
              history: history,
              onOpen: (_) {},
              onContinue: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hongguo-account-login')), findsOneWidget);
    expect(find.text('合成历史'), findsWidgets);
    await tester.tap(find.byKey(const Key('my-follows')));
    await tester.pumpAndSettle();
    expect(find.text('合成追剧'), findsWidgets);
    expect(find.text('合成历史'), findsNothing);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-history')));
    await tester.pumpAndSettle();
    expect(find.text('合成历史'), findsWidgets);
    expect(find.byKey(const Key('my-settings')), findsNothing);
    expect(store.favorites.single.id, drama.id);
    expect(store.history.single.episode, 3);
    expect(store.history.single.position, 20);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
