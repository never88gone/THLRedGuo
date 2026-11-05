import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_mpv.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_preferences.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || arguments.length < 3) exit(2);
  final report = File(arguments[1]);
  final cycles = int.parse(arguments[2]);
  final activeClose = arguments.length > 3 && arguments[3] == 'active-close';
  await windowManager.ensureInitialized();
  await windowManager.show();
  await windowManager.setSize(const Size(960, 640));
  MediaKit.ensureInitialized();
  final current = ValueNotifier<VideoController?>(null);
  final paintKey = GlobalKey();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 640,
            height: 360,
            child: RepaintBoundary(
              key: paintKey,
              child: ValueListenableBuilder<VideoController?>(
                valueListenable: current,
                builder: (_, controller, _) => controller == null
                    ? const SizedBox()
                    : Video(controller: controller, fit: BoxFit.fill),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> waitFor(bool Function() ready) async {
    final timer = Stopwatch()..start();
    while (!ready() && timer.elapsed.inSeconds < 25) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!ready()) throw StateError('Renderer probe timed out');
  }

  Future<List<List<int>>> capture(String name) async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        paintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    await File(
      '${report.parent.path}/$name.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    final bytes = rgba!.buffer.asUint8List();
    final samples = [
      for (var bar = 0; bar < 7; bar++)
        [
          for (var channel = 0; channel < 3; channel++)
            bytes[((image.height * .2).floor() * image.width +
                        ((bar + .5) * image.width / 7).floor()) *
                    4 +
                channel],
        ],
    ];
    image.dispose();
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
        if ((samples[bar][channel] - expected[bar][channel]).abs() > 35) {
          throw StateError(
            'Rendered color mismatch $bar/$channel: ${samples[bar]}',
          );
        }
      }
    }
    return samples;
  }

  final evidence = <Map<String, Object?>>[];
  Player? activePlayer;
  VideoEnhancementController? activeEnhancement;
  var exitCode = 0;
  try {
    for (var cycle = 0; cycle < cycles; cycle++) {
      final player = Player(
        configuration: const PlayerConfiguration(
          muted: true,
          logLevel: MPVLogLevel.v,
        ),
      );
      activePlayer = player;
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          hwdec: 'auto-copy-safe',
        ),
      );
      final native = VideoEnhancementMpv(player.platform as NativePlayer);
      final enhancement = VideoEnhancementController(
        player: player,
        video: controller,
        preferences: const VideoEnhancementPreferences(
          mode: VideoEnhancementMode.quality,
        ),
        category: '合成彩条',
        tags: const [],
      );
      activeEnhancement = enhancement;
      current.value = controller;
      await enhancement.beforeMedia();
      await player.setPlaylistMode(PlaylistMode.loop);
      await player.open(Media(arguments[0]));
      await waitFor(
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
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      enhancement.setViewport(const Size(640, 360), television: false);
      enhancement.mediaReady();
      await waitFor(() => enhancement.status == '通用神经超分');
      final samples = await capture('release-bars-$cycle');
      final decoder = native.read('hwdec-current');
      if (decoder != 'd3d11va-copy') {
        throw StateError('Expected hardware-copy decoder, got $decoder');
      }
      evidence.add({
        'cycle': cycle,
        'hwdec': decoder,
        'enhancement': enhancement.status,
        'samples': samples,
        'passes': native.read('vo-passes'),
      });
      await report.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'ok': true,
          'activeClose': activeClose,
          'evidence': evidence,
        }),
      );
      if (activeClose && cycle == cycles - 1) break;
      await enhancement.close();
      activeEnhancement = null;
      current.value = null;
      await WidgetsBinding.instance.endOfFrame;
      await player.dispose();
      activePlayer = null;
    }
  } catch (error, stack) {
    exitCode = 1;
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'ok': false,
        'error': error.toString(),
        'stack': stack.toString(),
        'evidence': evidence,
      }),
    );
  }
  if (!activeClose || exitCode != 0) {
    await activeEnhancement?.close();
    current.value = null;
    await WidgetsBinding.instance.endOfFrame;
    await activePlayer?.dispose();
  }
  await const MethodChannel(
    'duanju/device',
  ).invokeMethod<void>('finishPackageSmoke', exitCode);
}
