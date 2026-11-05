import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/media/media_pipeline.dart';

Future<void> runPackageSmoke(List<String> arguments) async {
  if (arguments.length != 3) {
    await _finishPackageSmoke(2);
    return;
  }
  final report = File(arguments[1]), input = arguments[2];
  Player? player;
  try {
    final repository = NativeRepository();
    await repository.initialize();
    final executor = FFmpegExecutor();
    final probe = await executor.probe(input);
    verifyMediaDuration(probe, 3);
    final remuxed = File(
      '${report.parent.path}${Platform.pathSeparator}remuxed.mkv',
    );
    await executor.run([
      '-i',
      input,
      '-map',
      '0:v:0',
      '-c',
      'copy',
      remuxed.path,
    ]);
    verifyMediaDuration(await executor.probe(remuxed.path), 3);
    player = Player(
      configuration: const PlayerConfiguration(muted: true, vo: 'null'),
    );
    await player.setAudioTrack(AudioTrack.no());
    await player.setVideoTrack(VideoTrack.auto());
    final playback = Future.any<String>([
      player.stream.position
          .firstWhere((time) => time.inMilliseconds >= 400)
          .then((_) => 'position'),
      player.stream.completed
          .firstWhere((value) => value)
          .then((_) => 'completed'),
      player.stream.error.first.then((error) => throw StateError(error)),
    ]);
    await player.open(Media(remuxed.path));
    final playbackEvidence = await playback.timeout(
      const Duration(seconds: 20),
    );
    await report.writeAsString(
      jsonEncode({
        'ok': true,
        'nativeCore': true,
        'ffprobe': true,
        'remux': true,
        'mediaKitPlayback': true,
        'playbackEvidence': playbackEvidence,
      }),
      flush: true,
    );
    await player.dispose();
    player = null;
    await _finishPackageSmoke(0);
  } catch (error) {
    await player?.dispose();
    await report.writeAsString(
      jsonEncode({'ok': false, 'error': error.toString()}),
      flush: true,
    );
    await _finishPackageSmoke(1);
  }
}

Future<void> _finishPackageSmoke(int code) => const MethodChannel(
  'duanju/device',
).invokeMethod<void>('finishPackageSmoke', code);
