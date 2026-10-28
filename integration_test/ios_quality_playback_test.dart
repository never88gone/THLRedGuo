import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/pages/player/player_page.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/player/player_quality_sheet_view.dart';
import 'package:THLRedLook/views/player/player_viewport_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    'iOS 27 real 1080 priority, quality UI, automatic next and saved progress',
    (t) async {
      expect(Platform.isIOS, isTrue);
      expect(DramaCover.imagesDisabled, isTrue);
      SharedPreferences.setMockInitialValues({});
      final rows = <Map<String, Object?>>[];
      final semantics = t.ensureSemantics();
      Future<T> real<T>(Future<T> Function() operation) async =>
          (await t.runAsync(operation)) as T;
      Future<void> wait(bool Function() predicate, String stage) async {
        debugPrint('IOS_QUALITY_WAIT $stage');
        final deadline = DateTime.now().add(const Duration(seconds: 100));
        while (!predicate() && DateTime.now().isBefore(deadline)) {
          await t.pump(const Duration(milliseconds: 100));
          await real(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(predicate(), isTrue, reason: stage);
      }

      PlayerViewportView view() =>
          t.widget<PlayerViewportView>(find.byType(PlayerViewportView).last);
      LunaExoPlayer player() => view().player as LunaExoPlayer;
      Future<void> controls() async {
        final toggle = find
            .byKey(const ValueKey('player-toggle'))
            .hitTestable();
        if (toggle.evaluate().isEmpty) {
          final rect = t.getRect(
            find.byKey(const ValueKey('player-gesture-surface')),
          );
          await t.tapAt(
            Offset(rect.left + rect.width * .08, rect.top + rect.height * .45),
          );
          await t.pump(const Duration(milliseconds: 300));
        }
        await wait(() => toggle.evaluate().isNotEmpty, 'visible controls');
      }

      Future<void> tapKey(String key) async {
        final target = find.byKey(ValueKey(key));
        await t.ensureVisible(target);
        await wait(() {
          final route = ModalRoute.of(t.element(target));
          return target.hitTestable().evaluate().isNotEmpty &&
              route?.animation?.status != AnimationStatus.forward &&
              route?.animation?.status != AnimationStatus.reverse;
        }, 'hittable $key');
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 300));
      }

      Future<void> ready(int episode, int quality) async {
        await wait(() {
          if (find.byType(PlayerViewportView).evaluate().isEmpty) return false;
          final v = view();
          return v.error != null ||
              (!v.loading &&
                  v.plan != null &&
                  (v.player as LunaExoPlayer).controller?.dataSource ==
                      v.plan!.url &&
                  !v.player.state.buffering &&
                  v.detail.episodes[v.index].number == episode &&
                  v.player.state.position.inMilliseconds > 300 &&
                  (v.player.state.width ?? 0) > 0);
        }, 'ready episode=$episode quality=$quality');
        expect(view().error, isNull);
        final p = player();
        await real(
          () => p.waitForVideoFrame().timeout(const Duration(seconds: 20)),
        );
        final size = p.controller!.value.size;
        expect(math.min(size.width, size.height).round(), quality);
        expect(view().plan!.quality, quality);
        expect(view().qualityLabel, '${quality}P');
        expect(await real(p.audioTrackCount), greaterThan(0));
        expect(
          (await real(
            p.controller!.getAudioTracks,
          )).any((track) => track.isSelected),
          isTrue,
        );
        expect(p.controller!.value.volume, greaterThan(0));
      }

      Future<void> capture(String stage) async {
        await controls();
        final v = view();
        final p = player();
        final audio = await real(
          () => const MethodChannel(
            'duanju/encrypted_stream',
          ).invokeMapMethod<String, dynamic>('audioStatus'),
        );
        expect(audio!['outputs'], isNotEmpty);
        expect(audio['outputVolume'] as num, greaterThan(0));
        final row = <String, Object?>{
          'stage': stage,
          'episode': v.detail.episodes[v.index].number,
          'reportedQuality': v.plan!.quality,
          'availableQualities': v.plan!.qualities,
          'width': p.controller!.value.size.width,
          'height': p.controller!.value.size.height,
          'positionMs': p.state.position.inMilliseconds,
          'playing': p.state.playing,
          'firstFrame': true,
          'selectedAudioTrack': true,
          'playerVolume': p.controller!.value.volume,
          'audioOutput': audio,
        };
        const endpoint = String.fromEnvironment('IOS_QUALITY_CHECKPOINT');
        if (endpoint.isNotEmpty) {
          final result = await real(() async {
            final client = HttpClient();
            try {
              final request = await client.postUrl(Uri.parse(endpoint));
              request.headers.contentType = ContentType.json;
              final payload = utf8.encode(
                jsonEncode({'stage': stage, 'media': v.plan!.url}),
              );
              request.contentLength = payload.length;
              request.add(payload);
              final response = await request.close();
              return jsonDecode(await response.transform(utf8.decoder).join())
                  as Map<String, dynamic>;
            } finally {
              client.close(force: true);
            }
          });
          expect(result['screenshot'], isTrue);
          expect(result['audioSignal'], isTrue);
          row['hostVerification'] = result;
        }
        rows.add(row);
        binding.reportData = {'samples': rows};
        debugPrint('IOS_QUALITY_SAMPLE ${jsonEncode(row)}');
      }

      Future<void> choose(int quality) async {
        await controls();
        await tapKey('player-quality');
        await wait(
          () => find.byType(PlayerQualitySheetView).evaluate().isNotEmpty,
          'quality sheet',
        );
        final sheet = t.widget<PlayerQualitySheetView>(
          find.byType(PlayerQualitySheetView),
        );
        expect(sheet.qualities, containsAll([1080, 720, 540, 480, 360]));
        await tapKey('quality-option-$quality');
        await wait(
          () => find.byType(PlayerQualitySheetView).evaluate().isEmpty,
          'quality sheet dismissed',
        );
      }

      try {
        await app.main([]);
        await wait(
          () => find.byType(HomeScreen).evaluate().isNotEmpty,
          'production bootstrap',
        );
        final root = t.widget<app.DuanjuApp>(find.byType(app.DuanjuApp));
        final repository = root.repository;
        final store = root.store!;
        final navigator = root.navigatorKey!.currentState!;
        final detail = await real(
          () => repository.detail(
            const Drama(
              id: 'hongguo:7694896136963755032',
              source: 'hongguo',
              sourceId: '7694896136963755032',
              title: '雾锁情迷',
            ),
          ),
        );
        expect(detail.episodes.length, greaterThan(3));
        void open({int index = 0, double position = 0}) {
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => PlayerScreen(
                detail: detail,
                initialIndex: index,
                initialPosition: position,
                repository: repository,
                store: store,
              ),
            ),
          );
        }

        open();
        await ready(1, 1080);
        expect(store.playbackPreferences.quality, 0);
        await capture('01-default-1080');
        await real(() => player().seek(const Duration(seconds: 12)));
        await wait(
          () => player().state.position.inMilliseconds >= 11500,
          'seek to 12s',
        );
        await controls();
        await tapKey('player-toggle');
        expect(player().state.playing, isFalse);
        final pausedPosition = player().state.position.inMilliseconds;
        await choose(720);
        await ready(1, 720);
        expect(player().state.playing, isFalse);
        expect(
          player().state.position.inMilliseconds,
          closeTo(pausedPosition, 800),
        );
        expect(store.playbackPreferences.quality, 720);
        await capture('02-paused-720');
        await choose(1080);
        await ready(1, 1080);
        expect(player().state.playing, isFalse);
        expect(
          player().state.position.inMilliseconds,
          closeTo(pausedPosition, 800),
        );
        await capture('03-paused-1080');
        await controls();
        await tapKey('player-toggle');
        await wait(
          () =>
              player().state.playing &&
              player().state.position.inMilliseconds > pausedPosition + 700,
          'resume after quality change',
        );
        await real(
          () => player().seek(
            player().state.duration - const Duration(seconds: 4),
          ),
        );
        await ready(2, 1080);
        expect(player().state.position.inSeconds, lessThan(15));
        expect(store.playbackPreferences.quality, 1080);
        await capture('04-automatic-episode-2');
        await controls();
        await tapKey('player-quality');
        await wait(
          () => find.byType(PlayerQualitySheetView).evaluate().isNotEmpty,
          'second episode actual choices',
        );
        final secondSheet = t.widget<PlayerQualitySheetView>(
          find.byType(PlayerQualitySheetView),
        );
        expect(secondSheet.qualities, contains(1080));
        expect(find.byKey(const ValueKey('quality-option-720')), findsNothing);
        await tapKey('quality-option-0');
        await ready(2, 1080);
        expect(store.playbackPreferences.quality, 0);
        await real(
          () => player().seek(
            player().state.duration - const Duration(seconds: 4),
          ),
        );
        await ready(3, 1080);
        expect(player().state.position.inSeconds, lessThan(15));
        await capture('05-automatic-episode-3');
        await real(() => player().seek(const Duration(seconds: 18)));
        await wait(
          () => player().state.position.inMilliseconds >= 17500,
          'third episode progress',
        );
        await controls();
        await tapKey('player-toggle');
        final savedPosition = player().state.position.inMilliseconds / 1000.0;
        navigator.pop();
        await wait(
          () => find.byType(PlayerViewportView).evaluate().isEmpty,
          'return from player',
        );
        await wait(
          () => store.watched(detail.drama.id)?.episode == 3,
          'saved episode',
        );
        final watched = store.watched(detail.drama.id)!;
        expect(watched.position, closeTo(savedPosition, 1));
        open(index: watched.episode - 1, position: watched.position);
        await ready(3, 1080);
        expect(
          player().state.position.inMilliseconds / 1000.0,
          closeTo(savedPosition, 2),
        );
        await capture('06-resumed-progress');
        navigator.pop();
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
        debugPrint('IOS_QUALITY_COMPLETE ${jsonEncode(rows)}');
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 300));
        semantics.dispose();
      }
    },
    skip: !Platform.isIOS || !const bool.fromEnvironment('HONGGUO_LIVE'),
    timeout: const Timeout(Duration(minutes: 9)),
  );
}
