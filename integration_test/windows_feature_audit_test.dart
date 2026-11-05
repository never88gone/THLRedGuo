import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_preferences.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_mpv.dart';
import 'package:THLRedLook/core/js/js_source_models.dart';
import 'package:THLRedLook/core/js/js_source_service.dart';
import 'package:THLRedLook/core/media/media_pipeline.dart';
import 'package:THLRedLook/core/player/encrypted_playback.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/pages/settings/settings_page.dart';
import 'package:THLRedLook/pages/settings/playback_settings_page.dart';

class _LocalOnlyHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (uri) {
          if (!{'127.0.0.1', 'localhost', '::1'}.contains(uri.host)) {
            throw const SocketException(
              'External requests are blocked in the Windows audit',
            );
          }
          return 'DIRECT';
        };
}

class _Repository extends AppRepository {
  _Repository(this.media);
  final String media;
  bool failCatalog = true;
  final queries = <String>[];
  final resolutions = <int>[];
  static const drama = Drama(
    id: 'hongguo:synthetic-1',
    source: 'hongguo',
    title: '合成剧甲',
    episodes: 3,
    description: 'Windows 本地合成验证，不含站源图片',
  );
  @override
  bool get supportsSourceManagement => true;
  @override
  Future<int> jsSourceScan() async => 1;
  @override
  Future<List<JsSourceMeta>> jsSourceList() async => [
    const JsSourceMeta(id: 'hongguo', name: '合成官方数据', version: '999.0.0'),
  ];
  @override
  Future<bool> jsSourceSetActive(String source) async => true;
  @override
  Future<bool> jsSourceSaveAndLoad(String script, String fileName) async =>
      true;
  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) async => const [CatalogCategory.all];
  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      CatalogPage([]);
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    queries.add(query);
    if (failCatalog) {
      failCatalog = false;
      throw AppFailure('合成网络失败，请重试');
    }
    return CatalogPage([drama], page: page, fresh: true);
  }

  @override
  Future<List<String>> suggestions(String query) async => ['合成搜索'];
  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';
  @override
  Future<DramaDetail> detail(Drama drama) async => DramaDetail(drama, [
    for (var i = 1; i <= 3; i++)
      Episode({'id': 'synthetic-$i', 'title': '第 $i 集'}, i),
  ]);
  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    resolutions.add(episode.number);
    return PlaybackPlan(
      url: media,
      local: true,
      quality: 720,
      qualities: const [720],
      session: 'synthetic-${episode.number}',
    );
  }

  @override
  Future<void> cancelPlayback() async {}
  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) async =>
      throw AppFailure('合成数据无备用地址');
  @override
  Future<void> release(String session) async {}
  @override
  Future<AppRuntimeState> initialize() async => const AppRuntimeState(
    version: '1.0.0',
    standalone: true,
    allSources: true,
  );
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready, {
  int seconds = 20,
}) async {
  final clock = Stopwatch()..start();
  while (!ready() && clock.elapsed.inSeconds < seconds) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), true, reason: 'Windows operation timed out');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final output = Directory(
    const String.fromEnvironment(
      'WINDOWS_AUDIT_OUTPUT',
      defaultValue: 'build/verification/windows-full-audit',
    ),
  );
  final results = <String, dynamic>{};
  final paintKey = GlobalKey();
  final executor = FFmpegExecutor();
  late File video;
  const key = '00112233445566778899aabbccddeeff';
  Future<({int width, int height, Uint8List pixels})> capture(
    String name, {
    GlobalKey? boundaryKey,
  }) async {
    final boundary =
        (boundaryKey ?? paintKey).currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    final frame = (
      width: image.width,
      height: image.height,
      pixels: rgba!.buffer.asUint8List(),
    );
    image.dispose();
    return frame;
  }

  Future<void> show(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: paintKey,
        child: MaterialApp(key: UniqueKey(), home: home),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  setUpAll(() async {
    if (!Platform.isWindows) {
      throw StateError('Windows audit requires a real Windows Flutter engine');
    }
    await output.create(recursive: true);
    HttpOverrides.global = _LocalOnlyHttp();
    await windowManager.ensureInitialized();
    await windowManager.show();
    await windowManager.setSize(const Size(1280, 800));
    MediaKit.ensureInitialized();
    video = File('${output.path}/synthetic-av.mp4');
    await executor.run([
      '-f',
      'lavfi',
      '-i',
      'testsrc=size=320x180:rate=24',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=44100:cl=stereo',
      '-t',
      '4',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      video.path,
    ]);
    final probe = await executor.probe(video.path);
    expect(probe.videoCodec, 'h264');
    expect(probe.hasAudio, true);
    results['ffmpeg'] = {
      'video': probe.videoCodec,
      'audio': probe.audio['codec_name'],
      'duration': probe.duration,
    };
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDownAll(() async {
    await windowManager.setFullScreen(false);
    await File(
      '${output.path}/native-ui-results.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  });

  testWidgets('Windows rendered color hardware decoder and shader comparison', (
    tester,
  ) async {
    final bars = File('${output.path}/synthetic-bars.mp4');
    await executor.run([
      '-f',
      'lavfi',
      '-i',
      'smptebars=size=320x180:rate=24',
      '-t',
      '4',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-color_primaries',
      'bt709',
      '-color_trc',
      'bt709',
      '-colorspace',
      'smpte170m',
      bars.path,
    ]);
    final colorKey = GlobalKey();
    final rows = <Map<String, Object?>>[];
    List<List<int>> samples(
      ({int width, int height, Uint8List pixels}) frame,
    ) => [
      for (var bar = 0; bar < 7; bar++)
        [
          for (var channel = 0; channel < 3; channel++)
            frame.pixels[((frame.height * .2).floor() * frame.width +
                        ((bar + .5) * frame.width / 7).floor()) *
                    4 +
                channel],
        ],
    ];
    void expectBars(List<List<int>> actual) {
      const expected = [
        [191, 191, 191],
        [191, 191, 0],
        [0, 191, 191],
        [0, 191, 0],
        [191, 0, 191],
        [191, 0, 0],
        [0, 0, 191],
      ];
      for (var bar = 0; bar < 7; bar++) {
        for (var channel = 0; channel < 3; channel++) {
          expect(
            actual[bar][channel],
            closeTo(expected[bar][channel], 35),
            reason: 'Rendered bar $bar channel $channel',
          );
        }
      }
    }

    double difference(Uint8List first, Uint8List second) {
      expect(first.length, second.length);
      var sum = 0;
      for (var i = 0; i < first.length; i++) {
        sum += (first[i] - second[i]).abs();
      }
      return sum / first.length;
    }

    for (final hardware in [true, false]) {
      final player = Player(
        configuration: const PlayerConfiguration(
          muted: true,
          logLevel: MPVLogLevel.v,
        ),
      );
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: hardware,
          hwdec: hardware ? 'auto-copy-safe' : 'no',
        ),
      );
      final native = VideoEnhancementMpv(player.platform as NativePlayer);
      final enhancement = VideoEnhancementController(
        player: player,
        video: controller,
        preferences: const VideoEnhancementPreferences(),
        category: '合成彩条',
        tags: const [],
      );
      try {
        await show(
          tester,
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 360,
                child: RepaintBoundary(
                  key: colorKey,
                  child: Video(controller: controller, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        );
        await enhancement.beforeMedia();
        await player.open(Media(bars.path), play: false);
        await _until(
          tester,
          () =>
              player.state.width == 320 &&
              (controller.rect.value?.width ?? 0) > 10,
        );
        await tester.pump(const Duration(milliseconds: 500));
        final original = await capture(
          hardware ? 'bars-original' : 'bars-software',
          boundaryKey: colorKey,
        );
        final originalSamples = samples(original);
        expectBars(originalSamples);
        final row = <String, Object?>{
          'hardwareRequested': hardware,
          'hwdec': native.read('hwdec-current'),
          'samples': originalSamples,
        };
        if (hardware) {
          expect(row['hwdec'], 'd3d11va-copy');
          await player.setPlaylistMode(PlaylistMode.loop);
          await player.play();
          enhancement.setViewport(const Size(640, 360), television: false);
          enhancement.mediaReady();
          enhancement.setPreferences(
            const VideoEnhancementPreferences(
              mode: VideoEnhancementMode.quality,
            ),
          );
          try {
            await _until(
              tester,
              () => enhancement.status == '通用神经超分',
              seconds: 25,
            );
          } finally {
            await File(
              '${output.path}/color-enhancement-state.json',
            ).writeAsString(
              const JsonEncoder.withIndent('  ').convert({
                'status': enhancement.status,
                'detail': enhancement.detail,
                'params': native.read('video-params'),
                'passes': native.read('vo-passes'),
              }),
            );
          }
          await player.pause();
          await tester.pump(const Duration(milliseconds: 300));
          final enhanced = await capture(
            'bars-enhanced',
            boundaryKey: colorKey,
          );
          expectBars(samples(enhanced));
          final passes = native.read('vo-passes');
          final descriptions =
              (passes is Map ? passes['fresh'] as List : const [])
                  .whereType<Map>()
                  .map((item) => item['desc'].toString())
                  .toList();
          expect(
            descriptions.any((item) => item.contains('feature map')),
            true,
          );
          expect(
            descriptions.any((item) => item.contains('aggregation')),
            true,
          );
          expect(
            difference(original.pixels, enhanced.pixels),
            greaterThan(.01),
          );
          await enhancement.toggleCompare();
          await tester.pump(const Duration(milliseconds: 500));
          expect(enhancement.status, '原画对比中');
          final compare = await capture('bars-compare', boundaryKey: colorKey);
          expectBars(samples(compare));
          expect(difference(enhanced.pixels, compare.pixels), greaterThan(.01));
          await enhancement.toggleCompare();
          await _until(tester, () => enhancement.status == '通用神经超分');
          await tester.pump(const Duration(milliseconds: 300));
          final restored = await capture(
            'bars-restored',
            boundaryKey: colorKey,
          );
          expect(difference(enhanced.pixels, restored.pixels), lessThan(2));
          row.addAll({
            'enhancement': enhancement.status,
            'passes': descriptions,
            'output': '${controller.rect.value}',
            'originalEnhancedMeanDifference': difference(
              original.pixels,
              enhanced.pixels,
            ),
            'compareMeanDifference': difference(
              enhanced.pixels,
              compare.pixels,
            ),
            'restoredMeanDifference': difference(
              enhanced.pixels,
              restored.pixels,
            ),
          });
          if (const bool.fromEnvironment('WINDOWS_AUDIT_VISUAL')) {
            await File('${output.path}/visual-ready.json').writeAsString(
              jsonEncode({
                'ready': true,
                'time': DateTime.now().toUtc().toIso8601String(),
                'display': 'hardware-copy-enhanced-bars',
              }),
            );
            final continueFile = File('${output.path}/visual-continue.json');
            for (
              var wait = 0;
              wait < 1200 && !await continueFile.exists();
              wait++
            ) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
        } else {
          expect(row['hwdec'], anyOf('no', isNull, ''));
        }
        rows.add(row);
        await File(
          '${output.path}/color-decoder-enhancement.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
      } finally {
        await enhancement.close();
        await tester.pumpWidget(const SizedBox());
        await player.dispose();
      }
    }
    results['colorsDecodersAndEnhancement'] = rows;
  });

  testWidgets('Windows native lifetime stress and renderer evidence', (
    tester,
  ) async {
    const cycles = int.fromEnvironment(
      'WINDOWS_AUDIT_CYCLES',
      defaultValue: 12,
    );
    final evidence = <Map<String, Object?>>[];
    for (var cycle = 0; cycle < cycles; cycle++) {
      final player = Player(
        configuration: const PlayerConfiguration(
          muted: true,
          logLevel: MPVLogLevel.debug,
        ),
      );
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          hwdec: String.fromEnvironment(
            'WINDOWS_AUDIT_HWDEC',
            defaultValue: 'auto-copy-safe',
          ),
        ),
      );
      final native = VideoEnhancementMpv(player.platform as NativePlayer);
      final logs = File('${output.path}/native-cycle-$cycle.log').openWrite();
      final subscription = player.stream.log.listen(
        (event) => logs.writeln('${event.prefix} ${event.level} ${event.text}'),
      );
      final enhancement = VideoEnhancementController(
        player: player,
        video: controller,
        preferences: const VideoEnhancementPreferences(
          mode: VideoEnhancementMode.quality,
        ),
        category: '合成测试',
        tags: const [],
      );
      try {
        await show(tester, Scaffold(body: Video(controller: controller)));
        await enhancement.beforeMedia();
        await player.setPlaylistMode(PlaylistMode.loop);
        await player.open(Media(video.path));
        await _until(
          tester,
          () =>
              player.state.width == 320 &&
              player.state.position.inMilliseconds > 300,
        );
        for (final size in [
          const Size(480, 270),
          const Size(800, 450),
          const Size(320, 180),
        ]) {
          await controller.setSize(
            width: size.width.toInt(),
            height: size.height.toInt(),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        enhancement.setViewport(const Size(960, 540), television: false);
        enhancement.mediaReady();
        await tester.pump(
          cycle % 10 == 0
              ? const Duration(seconds: 3)
              : const Duration(milliseconds: 250),
        );
        final row = <String, Object?>{
          'cycle': cycle,
          'enhancement': enhancement.status,
          'detail': enhancement.detail,
        };
        for (final property in [
          'mpv-version',
          'current-vo',
          'hwdec-current',
          'hwdec-interop',
          'video-params',
          'video-out-params',
          'vo-passes',
          'osd-dimensions',
        ]) {
          row[property] = native.read(property);
        }
        evidence.add(row);
        await File(
          '${output.path}/renderer-evidence.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
        if (cycle == 0) {
          await capture('stress-rendered-texture');
        }
        await player.pause();
      } finally {
        await enhancement.close();
        await tester.pumpWidget(const SizedBox());
        await player.dispose();
        await subscription.cancel();
        await logs.close();
      }
    }
    results['stress'] = {'cycles': cycles, 'completed': true};
  });

  testWidgets(
    'Windows real GPU video, pause seek speed fullscreen and CENC cache',
    (tester) async {
      final player = Player(
        configuration: const PlayerConfiguration(
          muted: true,
          logLevel: MPVLogLevel.error,
        ),
      );
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          hwdec: 'auto-copy-safe',
        ),
      );
      final enhancement = VideoEnhancementController(
        player: player,
        video: controller,
        preferences: const VideoEnhancementPreferences(),
        category: '合成测试',
        tags: const [],
      );
      final playback = EncryptedPlayback(
        temporaryDirectory: () async => output,
      );
      try {
        await show(tester, Scaffold(body: Video(controller: controller)));
        await enhancement.beforeMedia();
        await player.setPlaylistMode(PlaylistMode.loop);
        await player.open(Media(video.path));
        await _until(
          tester,
          () =>
              player.state.width == 320 &&
              player.state.position.inMilliseconds > 400,
        );
        expect(controller.rect.value?.width, greaterThan(0));
        final frame = await player.screenshot(format: 'image/png');
        expect(frame?.length, greaterThan(1000));
        await File(
          '${output.path}/native-video-frame.png',
        ).writeAsBytes(frame!);
        enhancement.setViewport(const Size(960, 540), television: false);
        enhancement.mediaReady();
        enhancement.setPreferences(
          const VideoEnhancementPreferences(mode: VideoEnhancementMode.economy),
        );
        await tester.pump(const Duration(seconds: 2));
        results['enhancement'] = {
          'supported': enhancement.supported,
          'status': enhancement.status,
          'detail': enhancement.detail,
        };
        await player.pause();
        expect(player.state.playing, false);
        await player.seek(const Duration(seconds: 2));
        await _until(
          tester,
          () => player.state.position.inMilliseconds >= 1800,
        );
        await player.setRate(1.5);
        expect(player.state.rate, 1.5);
        await windowManager.setFullScreen(true);
        await tester.pump(const Duration(milliseconds: 400));
        expect(await windowManager.isFullScreen(), true);
        await windowManager.setFullScreen(false);
        enhancement.setPreferences(const VideoEnhancementPreferences());
        await capture('native-player-window');
        if (const bool.fromEnvironment('WINDOWS_AUDIT_VISUAL')) {
          await File('${output.path}/visual-ready.json').writeAsString(
            jsonEncode({
              'ready': true,
              'time': DateTime.now().toUtc().toIso8601String(),
            }),
          );
          final continueFile = File('${output.path}/visual-continue.json');
          for (
            var attempt = 0;
            attempt < 1800 && !await continueFile.exists();
            attempt++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        final encrypted = File('${output.path}/synthetic-cenc.mp4');
        await executor.run([
          '-i',
          video.path,
          '-c',
          'copy',
          '-encryption_scheme',
          'cenc-aes-ctr',
          '-encryption_key',
          key,
          '-encryption_kid',
          'ffeeddccbbaa99887766554433221100',
          encrypted.path,
        ]);
        final prepared = await playback.prepare(
          PlaybackPlan(
            url: encrypted.uri.toString(),
            local: true,
            decryptionKey: key,
          ),
        );
        expect(prepared.decryptionKey, isEmpty);
        expect(prepared.local, true);
        verifyMediaDuration(
          await executor.probe(Uri.parse(prepared.url).toFilePath()),
          4,
        );
        await player.open(Media(prepared.url));
        await _until(
          tester,
          () =>
              player.state.width == 320 &&
              player.state.position.inMilliseconds > 300,
        );
        results['nativePlayback'] = {
          'decodedFrames': true,
          'textureSize': '${controller.rect.value}',
          'pauseSeekRate': true,
          'fullscreen': true,
          'cencCachePlayback': true,
        };
        expect(tester.takeException(), isNull);
      } finally {
        await windowManager.setFullScreen(false);
        await enhancement.close();
        await tester.pumpWidget(const SizedBox());
        await player.dispose();
        await playback.close();
      }
    },
  );

  testWidgets(
    'Windows browse retry search detail playback and local settings',
    (tester) async {
      final repository = _Repository(video.uri.toString());
      final sourceService = JsSourceService(repository);
      final store = LocalStore(await SharedPreferences.getInstance());
      try {
        await sourceService.initialize();
        await show(tester, HomeScreen(repository: repository, store: store));
        await _until(
          tester,
          () => find.textContaining('合成网络失败').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('重试').first);
        await _until(tester, () => find.text('合成剧甲').evaluate().isNotEmpty);
        await tester.tap(find.byKey(const ValueKey('toggle-search')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.enterText(find.byType(TextField).first, '合成搜索');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await _until(tester, () => repository.queries.contains('合成搜索'));
        await tester.tap(find.text('合成剧甲').first);
        await _until(
          tester,
          () =>
              find.byType(DetailScreen).evaluate().isNotEmpty &&
              find.byKey(const ValueKey('start-play')).evaluate().isNotEmpty,
        );
        await capture('desktop-detail');
        await tester.tap(find.byKey(const ValueKey('start-play')));
        await _until(tester, () => find.byType(Video).evaluate().isNotEmpty);
        final playing = tester
            .widget<Video>(find.byType(Video).first)
            .controller
            .player;
        await _until(tester, () => playing.state.position.inMilliseconds > 300);
        expect(repository.resolutions, isNotEmpty);
        await capture('desktop-playback');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 400));
        await show(
          tester,
          SettingsScreen(repository: repository, store: store),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('settings-playback-entry')),
        );
        await tester.tap(find.byKey(const ValueKey('settings-playback-entry')));
        await _until(
          tester,
          () => find.byType(PlaybackSettingsPage).evaluate().isNotEmpty,
        );
        expect(find.byKey(const ValueKey('settings-pip-switch')), findsNothing);
        await capture('desktop-settings');
        final backup = await store.exportBackup();
        final restored = LocalStore(await SharedPreferences.getInstance());
        await restored.importBackup(backup);
        expect(
          restored.playbackPreferences.toJson(),
          store.playbackPreferences.toJson(),
        );
        restored.dispose();
        results['ui'] = {
          'browseRetry': true,
          'search': true,
          'detail': true,
          'playback': true,
          'settings': true,
          'backupRoundTrip': true,
          'sourceImageRequests': 0,
        };
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        sourceService.dispose();
        store.dispose();
      }
    },
  );
}
