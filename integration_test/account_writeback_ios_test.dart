import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/core/account/hongguo_account_library.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/home/home_catalog_view.dart';
import 'package:THLRedLook/views/player/player_viewport_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    '真实账号追剧回读、观看进度回写、续播与下一集，本地资料保留',
    (tester) async {
      Future<T> real<T>(Future<T> Function() run) async =>
          (await tester.runAsync(run)) as T;
      Future<void> wait(
        bool Function() done,
        String stage, {
        int seconds = 90,
      }) async {
        debugPrint('THL_WRITEBACK_STAGE $stage');
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          await real(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(done(), true, reason: stage);
      }

      Finder key(String value) => find.byKey(ValueKey(value));
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 200));
        await wait(
          () {
            final visible = target.hitTestable();
            if (visible.evaluate().length != 1) return false;
            final widget = tester.widget(visible);
            return widget is! ButtonStyleButton || widget.onPressed != null;
          },
          'tap enabled target',
          seconds: 20,
        );
        await tester.tap(target.hitTestable());
        await tester.pump(const Duration(milliseconds: 200));
      }

      PlayerViewportView viewport() => tester.widget<PlayerViewportView>(
        find.byType(PlayerViewportView).last,
      );
      Future<void> ready(int episode) async {
        await wait(
          () =>
              find.byType(PlayerViewportView).evaluate().isNotEmpty &&
              (viewport().error != null ||
                  (!viewport().loading &&
                      viewport().detail.episodes[viewport().index].number ==
                          episode &&
                      viewport().player.state.position.inMilliseconds > 1500 &&
                      (viewport().player.state.width ?? 0) > 0)),
          'video $episode',
        );
        expect(viewport().error, isNull);
        final player = viewport().player as LunaExoPlayer;
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
      expect(DramaCover.imagesDisabled, true);
      final account = HongguoAccountSession.shared;
      expect(
        account.loggedIn,
        true,
        reason: 'Dedicated owner simulator must already be authorized',
      );
      final root = tester.widget<app.DuanjuApp>(find.byType(app.DuanjuApp));
      final store = root.store!, navigator = root.navigatorKey!.currentState!;
      final service = HongguoAccountService();
      addTearDown(service.dispose);
      final library = HongguoAccountLibrary.shared;
      final oldHistory = jsonEncode(
        store.history
            .map(
              (e) => {
                'id': e.drama.id,
                'episode': e.episode,
                'position': e.position,
                'duration': e.duration,
                'updatedAt': e.updatedAt.toIso8601String(),
              },
            )
            .toList(),
      );
      final oldFavorites = jsonEncode(
        store.favorites.map((e) => e.id).toList(),
      );
      await real(() => library.load(false));
      await wait(
        () =>
            find.byType(HomeCatalogView).evaluate().isNotEmpty &&
            !tester
                .widget<HomeCatalogView>(find.byType(HomeCatalogView).last)
                .loading,
        'catalog',
      );
      final candidates = tester
          .widget<HomeCatalogView>(find.byType(HomeCatalogView).last)
          .items;
      final drama = candidates.firstWhere(
        (d) => d.episodes > 1 && !library.following(d.id),
      );
      var added = false;
      Future<void> open() async {
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => DetailScreen(
              drama: drama,
              repository: root.repository,
              store: store,
            ),
          ),
        );
        await wait(
          () =>
              key('follow-status').evaluate().isNotEmpty &&
              key('detail-episodes-toggle').evaluate().isNotEmpty,
          'account detail',
        );
      }

      try {
        await open();
        added = true;
        await tap(key('follow-status'));
        await wait(() => library.following(drama.id), 'follow readback');
        added = true;
        await tap(key('follow-status'));
        await wait(() => !library.following(drama.id), 'unfollow readback');
        added = false;
        if (key('episode-1').evaluate().isEmpty) {
          await tap(key('detail-episodes-toggle'));
        }
        await wait(
          () => key('episode-1').evaluate().isNotEmpty,
          'episode selector',
        );
        await tap(key('episode-1'));
        await ready(1);
        await wait(
          () => viewport().player.state.position.inSeconds >= 6,
          'watch progress',
        );
        final expectedSaved =
            viewport().player.state.position.inMilliseconds / 1000;
        navigator.pop();
        await wait(
          () => find.byType(PlayerViewportView).evaluate().isEmpty,
          'back to detail',
        );
        await real(library.flush);
        final saved = await real(() => service.progress(drama));
        expect(saved, isNotNull);
        expect(saved!.episode, 1);
        expect(saved.position, greaterThan(3));
        expect(saved.position, closeTo(expectedSaved, 1.5));
        navigator.pop();
        await tester.pump(const Duration(milliseconds: 250));
        await open();
        expect(store.watched(drama.id)!.position, closeTo(saved.position, 1.5));
        await tap(key('start-play'));
        await ready(1);
        expect(
          viewport().player.state.position.inMilliseconds / 1000,
          greaterThanOrEqualTo(saved.position - 2),
        );
        final duration = viewport().player.state.duration;
        await real(
          () => viewport().player.seek(duration - const Duration(seconds: 3)),
        );
        await ready(2);
        await wait(
          () => viewport().player.state.position.inSeconds >= 6,
          'next episode progress',
        );
        final expectedNext =
            viewport().player.state.position.inMilliseconds / 1000;
        navigator.pop();
        await wait(
          () => find.byType(PlayerViewportView).evaluate().isEmpty,
          'next episode saved',
        );
        await real(library.flush);
        final next = await real(() => service.progress(drama));
        expect(next!.episode, 2);
        expect(next.position, greaterThan(3));
        expect(next.position, closeTo(expectedNext, 1.5));
        expect(
          jsonEncode(
            store.history
                .map(
                  (e) => {
                    'id': e.drama.id,
                    'episode': e.episode,
                    'position': e.position,
                    'duration': e.duration,
                    'updatedAt': e.updatedAt.toIso8601String(),
                  },
                )
                .toList(),
          ),
          oldHistory,
        );
        expect(
          jsonEncode(store.favorites.map((e) => e.id).toList()),
          oldFavorites,
        );
        binding.reportData = {
          'officialFollowReadback': true,
          'officialUnfollowReadback': true,
          'progressGet': true,
          'serverProgressSeconds': saved.position,
          'resume': true,
          'automaticNextAfterSeek': 2,
          'nextProgressSeconds': next.position,
          'forcedSaveWithin1_5Seconds': true,
          'videoFrame': true,
          'audioTrack': true,
          'localHistoryUnchanged': true,
          'localFavoritesUnchanged': true,
          'postersDisabled': true,
          'seriesId': drama.cleanSourceId,
        };
        debugPrint('THL_WRITEBACK_RESULT ${jsonEncode(binding.reportData)}');
      } finally {
        navigator.popUntil((route) => route.isFirst);
        await tester.pump(const Duration(milliseconds: 300));
        if (added) await real(() => library.setFollowing(drama, false));
      }
    },
    skip: !const bool.fromEnvironment('THL_ACCOUNT_OWNER'),
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
