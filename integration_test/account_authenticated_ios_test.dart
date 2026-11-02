import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/pages/account/account_page.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/home/home_catalog_view.dart';
import 'package:THLRedLook/views/player/player_viewport_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    '真实账号重启恢复、搜索、选集和自然下一集',
    (tester) async {
      expect(Platform.isIOS, true);
      expect(DramaCover.imagesDisabled, true);
      Future<T> real<T>(Future<T> Function() run) async =>
          (await tester.runAsync(run)) as T;
      Future<void> wait(
        bool Function() done,
        String stage, {
        int seconds = 90,
      }) async {
        debugPrint('THL_ACCOUNT_WAIT $stage');
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          await real(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(done(), true, reason: stage);
      }

      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 300));
      }

      Finder key(String value) => find.byKey(ValueKey(value));
      HomeCatalogView catalog() =>
          tester.widget<HomeCatalogView>(find.byType(HomeCatalogView).last);
      PlayerViewportView viewport() => tester.widget<PlayerViewportView>(
        find.byType(PlayerViewportView).last,
      );
      Future<void> ready(int number, {int seconds = 90}) async {
        await wait(
          () {
            if (find.byType(PlayerViewportView).evaluate().isEmpty) {
              return false;
            }
            final v = viewport();
            return v.error != null ||
                (!v.loading &&
                    v.detail.episodes[v.index].number == number &&
                    v.player.state.position.inMilliseconds > 700 &&
                    !v.player.state.buffering &&
                    (v.player.state.width ?? 0) > 0);
          },
          'decoded episode $number',
          seconds: seconds,
        );
        final v = viewport();
        expect(v.error, isNull);
        expect(v.detail.episodes[v.index].number, number);
        expect(v.player.state.playing, true);
        expect(v.plan!.quality, 1080);
        final player = v.player as LunaExoPlayer;
        await real(
          () => player.waitForVideoFrame().timeout(const Duration(seconds: 20)),
        );
        expect(await real(player.audioTrackCount), greaterThan(0));
        expect(player.controller!.value.volume, greaterThan(0));
      }

      await app.main([]);
      await wait(
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
        'bootstrap',
      );
      final account = HongguoAccountSession.shared;
      expect(
        account.loggedIn,
        true,
        reason:
            'Requires phone authorization on this dedicated simulator before running',
      );
      final accountId = account.id;
      final root = tester.widget<app.DuanjuApp>(find.byType(app.DuanjuApp));
      final store = root.store!;
      final navigator = root.navigatorKey!.currentState!;
      final preferences = store.playbackPreferences;
      final favorites = store.favorites.map((d) => d.id).toSet();
      final history = store.history.map((d) => d.drama.id).toSet();
      await tap(key('bottom-nav-4'));
      await wait(
        () =>
            find.byType(AccountScreen).evaluate().isNotEmpty &&
            account.verified,
        'restored account profile verification',
      );
      expect(find.text('退出登录'), findsOneWidget);
      await tap(key('bottom-nav-0'));
      await wait(
        () => find.byType(HomeCatalogView).evaluate().isNotEmpty,
        'catalog',
      );
      await real(
        () => store.setPlaybackPreferences(
          preferences.copyWith(speed: 1, quality: 0, autoAdvance: true),
        ),
      );
      try {
        await tap(key('toggle-search'));
        await tester.enterText(find.byType(TextField).first, '满院亲戚全是上古大妖第五季');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await wait(
          () =>
              !catalog().loading &&
              catalog().gridKey.endsWith('-满院亲戚全是上古大妖第五季'),
          'authenticated UI search',
        );
        expect(catalog().error, isNull);
        final drama = catalog().items.firstWhere(
          (d) => d.cleanSourceId == '7695704804978330649',
        );
        await tap(
          find.byWidgetPredicate(
            (w) => w is DramaTile && w.drama.id == drama.id,
          ),
        );
        await wait(
          () =>
              find.byType(DetailScreen).evaluate().isNotEmpty &&
              key('detail-episodes-toggle').evaluate().isNotEmpty,
          'detail',
        );
        if (key('episode-3').evaluate().isEmpty) {
          await tap(key('detail-episodes-toggle'));
        }
        await wait(
          () => key('episode-3').evaluate().isNotEmpty,
          'episode selection',
        );
        await tap(key('episode-3'));
        await ready(3);
        await ready(4, seconds: 180);
        expect(account.loggedIn && account.id == accountId, true);
        expect(store.favorites.map((d) => d.id).toSet(), favorites);
        expect(
          store.history.map((d) => d.drama.id).toSet().containsAll(history),
          true,
        );
        binding.reportData = {
          'platform': 'iOS27',
          'restoredAccount': true,
          'appProfileVerified': true,
          'authenticatedSearch': true,
          'selectedEpisode': 3,
          'naturalNext': 4,
          'videoFrame': true,
          'audioTrack': true,
          'muted': false,
          'quality': viewport().plan!.quality,
          'seek': false,
          'speed': 1,
          'favoritesPreserved': true,
          'oldHistoryPreserved': true,
          'postersDisabled': true,
        };
        debugPrint('THL_ACCOUNT_RESULT ${jsonEncode(binding.reportData)}');
      } finally {
        navigator.popUntil((route) => route.isFirst);
        await tester.pump(const Duration(milliseconds: 500));
        await real(() => store.setPlaybackPreferences(preferences));
      }
    },
    skip: !const bool.fromEnvironment('THL_ACCOUNT_OWNER'),
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
