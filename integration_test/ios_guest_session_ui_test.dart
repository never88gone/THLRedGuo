import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/core/js/hongguo_guest_session.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/pages/feed/video_feed_page.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/pages/settings/source_diagnostics_page.dart';
import 'package:THLRedLook/pages/settings/settings_page.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostic_runner.dart';
import 'package:THLRedLook/views/catalog/catalog_filters.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/player/player_episodes_sheet_view.dart';
import 'package:THLRedLook/views/player/player_quality_sheet_view.dart';
import 'package:THLRedLook/views/player/player_viewport_view.dart';
import 'helpers/ios_ui.dart' as h;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    'iOS 27 persistent anonymous session and production UI automation',
    (t) async {
      expect(Platform.isIOS, true);
      expect(DramaCover.imagesDisabled, true);
      await HongguoGuestSession.shared.preload();
      final savedGuest = HongguoGuestSession.shared.value;
      final savedCreated = HongguoGuestSession.shared.createdAt;
      final initialPreferences = <String, Object>{};
      if (savedGuest != null) {
        initialPreferences[HongguoGuestSession.sessionKey] = savedGuest;
      }
      if (savedCreated != null) {
        initialPreferences[HongguoGuestSession.createdKey] =
            savedCreated.millisecondsSinceEpoch;
      }
      SharedPreferences.setMockInitialValues(initialPreferences);
      HongguoGuestSession.shared.resetForTesting(savedGuest, savedCreated);
      final semantics = t.ensureSemantics();
      final steps = <Map<String, Object?>>[];
      final videos = <Map<String, Object?>>[];
      final timeline = <Map<String, Object?>>[];
      final diagnosticRounds = <Map<String, Object?>>[];
      final failures = <String>[];
      const selected = String.fromEnvironment('UI_STEPS');
      void report() {
        binding.reportData = {
          'steps': steps,
          'videos': videos,
          'timeline': timeline,
          'diagnosticRounds': diagnosticRounds,
          'remoteImagesDisabled': true,
          'platform': 'iOS 27',
          'selectedSteps': selected,
          if (binding.reportData?['screenshots'] != null)
            'screenshots': binding.reportData!['screenshots'],
        };
      }

      Future<T> real<T>(Future<T> Function() run) async =>
          (await t.runAsync(run)) as T;
      Future<void> step(String name, Future<void> Function() run) async {
        if (selected.isNotEmpty &&
            !selected.split(',').contains(name.substring(0, 2))) {
          return;
        }
        final clock = Stopwatch()..start();
        final began = DateTime.now();
        debugPrint('IOS_GUEST_BEGIN $name');
        try {
          await run();
          final error = t.takeException();
          if (error != null) throw error;
          steps.add({
            'name': name,
            'ok': true,
            'ms': clock.elapsedMilliseconds,
          });
        } catch (error) {
          failures.add(name);
          steps.add({
            'name': name,
            'ok': false,
            'error': SourceDiagnostics.redact(error.toString()),
            'ms': clock.elapsedMilliseconds,
          });
          t.takeException();
        }
        final traces = SourceDiagnostics.shared.entries
            .where((e) => !e.at.isBefore(began))
            .map(
              (e) => {
                'at': e.at.toIso8601String(),
                'context': e.context,
                'stage': e.stage,
                'host': e.host,
                'path': Uri.tryParse(e.url)?.path ?? '',
                'status': e.status,
                'code': e.errorCode,
                'elapsedMs': e.elapsedMs,
                'session': e.sessionStatus,
              },
            )
            .toList();
        steps.last['traces'] = traces;
        report();
        debugPrint('IOS_GUEST_STEP ${jsonEncode(steps.last)}');
      }

      try {
        await real(
          () => SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]),
        );
        await app.main([]);
        await h.wait(
          t,
          () => find.byType(HomeScreen).evaluate().isNotEmpty,
          'production bootstrap',
        );
        final root = t.widget<app.DuanjuApp>(find.byType(app.DuanjuApp));
        final store = root.store!;
        final navigator = root.navigatorKey!.currentState!;
        Future<void> home() async {
          navigator.popUntil((route) => route.isFirst);
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pump(const Duration(milliseconds: 450));
          await h.tap(t, h.key('bottom-nav-0'));
        }

        Future<void> search(String query) async {
          await home();
          if (find.byType(TextField).evaluate().isEmpty) {
            await h.tap(t, h.key('toggle-search'));
          }
          await h.tap(t, find.byType(TextField).first);
          await t.enterText(find.byType(TextField).first, query);
          await t.testTextInput.receiveAction(TextInputAction.search);
          await t.pump(const Duration(milliseconds: 300));
          await h.wait(
            t,
            () =>
                !h.catalog(t).loading &&
                h.catalog(t).gridKey.endsWith('-$query'),
            'search $query',
          );
          expect(h.catalog(t).error, isNull);
          expect(h.catalog(t).items, isNotEmpty);
        }

        Future<void> detail(String query) async {
          await search(query);
          final drama = h.catalog(t).items.first;
          final tile = find.byWidgetPredicate(
            (w) => w is DramaTile && w.drama.id == drama.id,
          );
          await h.tap(t, tile.first);
          await h.wait(
            t,
            () =>
                find.byType(DetailScreen).evaluate().isNotEmpty &&
                h.key('start-play').evaluate().isNotEmpty &&
                t.widget<FilledButton>(h.key('start-play')).onPressed != null,
            'detail $query',
          );
        }

        Future<void> ready({String? id, int? episode}) async {
          await h.wait(
            t,
            () {
              if (find.byType(PlayerViewportView).evaluate().isEmpty) {
                return false;
              }
              final v = h.viewport(t);
              return v.error != null ||
                  !v.loading &&
                      !v.player.state.buffering &&
                      v.player.state.position.inMilliseconds > 800 &&
                      (v.player.state.width ?? 0) > 0 &&
                      (id == null || v.detail.drama.cleanSourceId == id) &&
                      (episode == null ||
                          v.detail.episodes[v.index].number == episode);
            },
            'decoded playback $id/$episode',
            seconds: 110,
          );
          expect(h.viewport(t).error, isNull);
          final end = DateTime.now().add(const Duration(seconds: 20));
          var tracks = 0;
          while (tracks == 0 && DateTime.now().isBefore(end)) {
            tracks = await real(
              (h.viewport(t).player as LunaExoPlayer).audioTrackCount,
            );
            if (tracks == 0) {
              await t.pump(const Duration(milliseconds: 100));
              await real(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
            }
          }
          expect(tracks, greaterThan(0));
          await real(
            () => (h.viewport(t).player as LunaExoPlayer)
                .waitForVideoFrame()
                .timeout(const Duration(seconds: 20)),
          );
        }

        Future<void> play() async {
          await h.tap(t, h.key('start-play'));
          await ready();
        }

        Future<void> recordVideo(String label) async {
          await ready();
          final v = h.viewport(t), p = v.player as LunaExoPlayer;
          final tracks = await real(p.audioTrackCount);
          expect(tracks, greaterThan(0));
          expect(p.controller!.value.volume, greaterThan(0));
          final row = <String, Object?>{
            'label': label,
            'series': v.detail.drama.cleanSourceId,
            'episode': v.detail.episodes[v.index].number,
            'width': p.state.width,
            'height': p.state.height,
            'quality': v.plan?.quality,
            'qualities': v.plan?.qualities,
            'preferredQuality': store.playbackPreferences.quality,
            'positionMs': p.state.position.inMilliseconds,
            'audioTracks': tracks,
            'firstFrame': true,
            'error': v.error,
          };
          videos.add(row);
          report();
          debugPrint('IOS_GUEST_VIDEO ${jsonEncode(row)}');
        }

        Future<void> snapshot(String name) async {
          await t.pump(const Duration(milliseconds: 400));
          await real(
            () => Future<void>.delayed(const Duration(milliseconds: 500)),
          );
          await t.pump();
          await binding.takeScreenshot(name);
        }

        await step('01 discover categories and automatic pagination', () async {
          await h.wait(
            t,
            () =>
                find.byType(CatalogFilters).evaluate().isNotEmpty &&
                !h.catalog(t).loading,
            'discover categories',
          );
          for (final category in [
            'app:discover:playlet',
            'app:discover:motion_comic',
            'app:discover:ai_playlet',
            'app:discover:all',
          ]) {
            await h.tap(t, h.key('category-$category'));
            await h.wait(
              t,
              () =>
                  !h.catalog(t).loading &&
                  h.catalog(t).gridKey.contains(category),
              'category $category',
            );
            expect(h.catalog(t).items, isNotEmpty);
          }
          final count = h.catalog(t).items.length;
          for (var i = 0; i < 12 && h.catalog(t).items.length == count; i++) {
            await t.drag(
              find.byType(CustomScrollView).last,
              const Offset(0, -600),
            );
            await t.pump(const Duration(milliseconds: 250));
            await real(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
          }
          await h.wait(
            t,
            () => h.catalog(t).items.length > count || !h.catalog(t).hasMore,
            'automatic next page',
          );
          await snapshot('01-discover');
        });
        String? favorite;
        await step('02 search, detail and local favorite', () async {
          await detail('雾锁情迷');
          await h.tap(t, h.key('follow-status'));
          await h.tap(t, find.text('想看').last);
          await play();
          favorite = h.viewport(t).detail.drama.id;
          expect(store.isFavorite(favorite!), true);
          await recordVideo('control episode 1');
        });
        await step(
          '03 episode picker, quality, pause progress and danmaku',
          () async {
            await h.controls(t);
            await h.tap(t, find.byTooltip('旋转与全屏'));
            await h.wait(
              t,
              () =>
                  h.key('player-episodes').hitTestable().evaluate().isNotEmpty,
              'fullscreen episode picker',
            );
            await h.controls(t);
            await h.tap(t, h.key('player-episodes'));
            expect(find.byType(PlayerEpisodesSheetView), findsOneWidget);
            await h.tap(t, h.key('episode-option-2'));
            await ready(episode: 3);
            await h.controls(t);
            await h.tap(t, find.byTooltip('退出全屏').first);
            await h.wait(
              t,
              () => t.view.physicalSize.height > t.view.physicalSize.width,
              'portrait playback',
            );
            await h.seekWithSlider(t, 12);
            await h.wait(
              t,
              () => h.viewport(t).player.state.position.inSeconds >= 11,
              'seek',
            );
            await h.controls(t);
            await h.tap(t, h.key('player-toggle'));
            final paused = h.viewport(t).player.state.position.inMilliseconds;
            final priorPlan = h.viewport(t).plan;
            await h.tap(t, h.key('player-quality'));
            expect(find.byType(PlayerQualitySheetView), findsOneWidget);
            await h.tap(t, h.key('quality-option-720'));
            await h.wait(
              t,
              () =>
                  !identical(h.viewport(t).plan, priorPlan) &&
                  h.viewport(t).plan?.quality == 720 &&
                  (h.viewport(t).player.state.width == 720 ||
                      h.viewport(t).player.state.height == 720) &&
                  !h.viewport(t).loading,
              '720p plan installed',
            );
            await ready(episode: 3);
            expect(h.viewport(t).player.state.playing, false);
            expect(
              h.viewport(t).player.state.position.inMilliseconds,
              closeTo(paused, 1000),
            );
            await h.controls(t);
            final danmaku = h.viewport(t).danmakuEnabled;
            await h.tap(t, h.key('player-danmaku-toggle'));
            expect(h.viewport(t).danmakuEnabled, !danmaku);
            await h.tap(t, h.key('player-danmaku-toggle'));
            expect(h.viewport(t).danmakuEnabled, danmaku);
            await h.tap(t, h.key('player-toggle'));
            await recordVideo('episode and quality switch');
          },
        );
        await step('04 automatic next episode and back navigation', () async {
          final v = h.viewport(t), next = v.detail.episodes[v.index].number + 1;
          final previousPlan = v.plan;
          await h.seekWithSlider(
            t,
            v.player.state.duration.inMilliseconds / 1000 - 2,
          );
          await h.wait(
            t,
            () =>
                !identical(h.viewport(t).plan, previousPlan) &&
                h.viewport(t).detail.episodes[h.viewport(t).index].number ==
                    next,
            'new episode plan installed',
          );
          await h.wait(
            t,
            () => h.viewport(t).player.state.position.inSeconds < 6,
            'next media position reset',
          );
          await ready(episode: next);
          await recordVideo('automatic next');
          await home();
          expect(store.watched(favorite!), isNotNull);
          await h.tap(t, h.key('bottom-nav-2'));
          await h.wait(
            t,
            () => h.key('saved-$favorite').evaluate().isNotEmpty,
            'local favorite view',
          );
          await snapshot('04-favorites');
          await h.tap(t, h.key('bottom-nav-3'));
          await h.wait(
            t,
            () => h.key('saved-tab-2').evaluate().isNotEmpty,
            'history tab displayed',
          );
          expect(store.history, isNotEmpty);
          await snapshot('04-history');
        });
        for (final query in ['满院亲戚全是上古大妖第五季', '觉醒伪神', '重生', '修仙', '萌宝', '千金']) {
          await step('05 search and real playback $query', () async {
            await detail(query);
            await play();
            await recordVideo(query);
            await real(() => Future<void>.delayed(const Duration(seconds: 5)));
            await t.pump();
          });
        }
        await step('06 recommendation feed autoplay and switching', () async {
          await home();
          await h.tap(t, h.key('bottom-nav-1'));
          await h.wait(
            t,
            () =>
                find.byType(VideoFeedScreen).evaluate().isNotEmpty &&
                find.byType(PlayerViewportView).evaluate().isNotEmpty,
            'recommendation feed',
          );
          await recordVideo('recommendation first');
          final feed = t
              .widget<VideoFeedScreen>(find.byType(VideoFeedScreen))
              .controller;
          final previousIndex = feed.index;
          await t.drag(h.key('feed-pager'), const Offset(0, -650));
          await t.pump(const Duration(milliseconds: 400));
          await h.wait(
            t,
            () => feed.index > previousIndex && !feed.loading,
            'recommendation changed',
          );
          await ready(id: feed.current!.drama.cleanSourceId);
          await recordVideo('recommendation next');
          await home();
        });
        await step(
          '07 real session lifetime and natural continuous playback',
          () async {
            await detail('雾锁情迷');
            await play();
            final created =
                HongguoGuestSession.shared.createdAt ?? DateTime.now();
            final retainedGuest = HongguoGuestSession.shared.value;
            final startedEpisode = h.viewport(t).index;
            final end = created.add(const Duration(minutes: 12));
            var lastBucket = -1;
            while (DateTime.now().isBefore(end)) {
              await t.pump();
              final v = h.viewport(t);
              expect(v.error, isNull);
              final bucket = DateTime.now().difference(created).inSeconds ~/ 15;
              if (bucket != lastBucket) {
                lastBucket = bucket;
                final row = <String, Object?>{
                  'ageSeconds': DateTime.now().difference(created).inSeconds,
                  'episode': v.detail.episodes[v.index].number,
                  'positionMs': v.player.state.position.inMilliseconds,
                  'buffering': v.player.state.buffering,
                  'recoveries': SourceDiagnostics.shared.entries
                      .where((e) => e.stage == '游客会话恢复')
                      .length,
                };
                timeline.add(row);
                report();
                debugPrint('IOS_GUEST_NATURAL ${jsonEncode(row)}');
              }
              await real(
                () => Future<void>.delayed(const Duration(milliseconds: 250)),
              );
            }
            expect(h.viewport(t).index, greaterThan(startedEpisode));
            expect(HongguoGuestSession.shared.value, retainedGuest);
            await recordVideo('natural session lifetime');
            await home();
            await detail('雾锁情迷');
            await play();
            await recordVideo('reenter after twelve minutes');
            debugPrint(
              'IOS_GUEST_RECOVERIES ${SourceDiagnostics.shared.entries.where((e) => e.stage == '游客会话恢复').length}',
            );
          },
        );
        await step(
          '08 search and diagnosis preserve favorites and history',
          () async {
            await home();
            expect(store.isFavorite(favorite!), true);
            expect(store.watched(favorite!), isNotNull);
            await search('重生');
            expect(h.catalog(t).items, isNotEmpty);
            await home();
            await h.tap(t, h.key('home-appbar-settings-button'));
            await h.wait(
              t,
              () => find.byType(SettingsScreen).evaluate().isNotEmpty,
              'settings route',
            );
            await t.pump(const Duration(seconds: 1));
            final settingsScroll = find
                .descendant(
                  of: find.byType(SettingsScreen),
                  matching: find.byType(Scrollable),
                )
                .last;
            await t.scrollUntilVisible(
              h.key('settings-source-diagnostics'),
              200,
              scrollable: settingsScroll,
            );
            await t.pump(const Duration(milliseconds: 400));
            await h.tap(t, h.key('settings-source-diagnostics'));
            await h.wait(
              t,
              () => find.byType(SourceDiagnosticsPage).evaluate().isNotEmpty,
              'diagnostics route',
            );
            for (var i = 0; i < 3; i++) {
              final button = h.key('source-diagnostics-run');
              await h.tap(t, button);
              await h.wait(
                t,
                () =>
                    !SourceDiagnosticRunner.shared.running &&
                    SourceDiagnosticRunner.shared.result.startsWith('检测'),
                'diagnosis round $i',
              );
              diagnosticRounds.add({
                'round': i + 1,
                'success': SourceDiagnosticRunner.shared.successCount,
                'failures': SourceDiagnosticRunner.shared.failureCount,
                'result': SourceDiagnosticRunner.shared.result,
                'traces': SourceDiagnostics.shared.entries
                    .where(
                      (e) =>
                          e.context.startsWith('主动检测') &&
                          e.errorCode.isNotEmpty,
                    )
                    .map(
                      (e) => {
                        'stage': e.stage,
                        'code': e.errorCode,
                        'status': e.status,
                        'host': e.host,
                      },
                    )
                    .toList(),
              });
              debugPrint('IOS_DIAGNOSIS ${jsonEncode(diagnosticRounds.last)}');
              expect(
                SourceDiagnosticRunner.shared.failureCount,
                0,
                reason: SourceDiagnosticRunner.shared.result,
              );
            }
            await snapshot('08-diagnostics');
          },
        );
        expect(failures, isEmpty, reason: failures.join(', '));
      } finally {
        report();
        semantics.dispose();
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 1));
      }
    },
    timeout: const Timeout(Duration(minutes: 35)),
  );
}
