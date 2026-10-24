import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/media/media_pipeline.dart';
import 'package:THLRedLook/core/player/ios_encrypted_stream.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/models/catalog/models.dart';

class EncryptedPlayback {
  EncryptedPlayback({
    MediaExecutor? executor,
    Future<Directory> Function()? temporaryDirectory,
    bool? streamEncrypted,
    IosEncryptedStream Function()? iosStreamFactory,
  }) : _executor = executor ?? FFmpegExecutor(),
       _iosStreamFactory =
           iosStreamFactory ?? (Platform.isIOS ? IosEncryptedStream.new : null),
       _streamEncrypted =
           streamEncrypted ?? (Platform.isAndroid || Platform.isIOS),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final MediaExecutor _executor;
  final bool _streamEncrypted;
  final IosEncryptedStream Function()? _iosStreamFactory;
  final Future<Directory> Function() _temporaryDirectory;
  IosEncryptedStream? _stream;
  PlaybackPlan? _streamOriginal;
  String? _streamUrl;
  bool isStreamPlan(PlaybackPlan plan) => _streamUrl == plan.url;

  HttpClient? _client;
  Directory? _ready;
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _closed = false;

  Future<void> cancel() async {
    _generation++;
    final stream = _stream;
    _stream = null;
    _client?.close(force: true);
    final cancellation = _executor.cancel();
    await stream?.close();
    await cancellation;
  }

  Future<PlaybackPlan> prepare(
    PlaybackPlan plan, {
    void Function(double)? progress,
    bool forceCache = false,
  }) async {
    if (isStreamPlan(plan) && _streamOriginal != null) plan = _streamOriginal!;
    final generation = ++_generation;
    final previous = _tail;
    final finished = Completer<void>();
    _tail = finished.future;
    Directory? workspace;
    void check() {
      if (_closed || generation != _generation) {
        throw AppFailure('已取消播放准备', code: 'cancelled');
      }
    }

    try {
      final previousStream = _stream;
      _stream = null;
      await previousStream?.close();
      _client?.close(force: true);
      await _executor.cancel();
      await previous;
      check();
      final ready = _ready;
      _ready = null;
      if (ready != null && await ready.exists()) {
        await ready.delete(recursive: true);
      }
      if (plan.decryptionKey.isEmpty) return plan;
      if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(plan.decryptionKey)) {
        throw AppFailure('视频内容密钥无效', code: 'media_key');
      }
      if (_streamEncrypted && !plan.local && !forceCache) {
        final factory = _iosStreamFactory;
        if (factory == null) return plan;
        final stream = factory();
        _stream = stream;
        final clock = Stopwatch()..start();
        try {
          final prepared = await stream.open(plan);
          check();
          _streamOriginal = plan;
          _streamUrl = prepared.url;
          DiaryService.add(
            '[Play] iOS 按需解密已准备: ${clock.elapsedMilliseconds}ms, 首批=${prepared.prefetchedBytes}, 总量=${prepared.mediaBytes}',
          );
          return prepared;
        } catch (_) {
          await stream.close();
          if (identical(_stream, stream)) _stream = null;
          check();
          DiaryService.add('[Play] iOS 按需解密暂不可用，尝试缓存恢复');
        }
      }
      final root = await _temporaryDirectory();
      check();
      final cache = await Directory(
        p.join(root.path, 'encrypted_playback'),
      ).create(recursive: true);
      workspace = await cache.createTemp('episode_');
      final input = p.join(workspace.path, 'input.mp4');
      final output = p.join(workspace.path, 'playback.mp4');
      if (plan.local) {
        final uri = Uri.tryParse(plan.url);
        await File(
          uri?.scheme == 'file' ? uri!.toFilePath() : plan.url,
        ).copy(input);
      } else {
        await _download(
          plan,
          input,
          check,
          (value) => progress?.call(value * .85),
        );
      }
      check();
      progress?.call(.85);
      await _executor.run([
        '-decryption_key',
        plan.decryptionKey,
        '-i',
        input,
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        '-c',
        'copy',
        '-movflags',
        '+faststart',
        '-f',
        'mp4',
        output,
      ]);
      check();
      await _executor.run([
        '-xerror',
        '-err_detect',
        'explode',
        '-i',
        output,
        '-t',
        '1',
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        '-f',
        'null',
        '-',
      ]);
      check();
      final probe = await _executor.probe(output);
      check();
      verifyMediaDuration(probe, 0);
      if (await File(output).length() < 1024) {
        throw AppFailure('视频缓存不完整', code: 'media_incomplete');
      }
      await File(input).delete();
      check();
      _ready = workspace;
      workspace = null;
      progress?.call(1);
      return PlaybackPlan(
        url: Uri.file(output).toString(),
        local: true,
        onlineCache: !plan.offline,
        quality: plan.quality,
        qualities: plan.qualities,
        session: plan.session,
        danmakuId: plan.danmakuId,
        expiresAt: 0,
        prefetchedBytes: await File(output).length(),
      );
    } finally {
      try {
        if (workspace != null && await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      } finally {
        finished.complete();
      }
    }
  }

  Future<void> _download(
    PlaybackPlan plan,
    String destination,
    void Function() check,
    void Function(double) progress,
  ) async {
    final uri = Uri.tryParse(plan.url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      throw AppFailure('视频地址无效', code: 'media_url');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _client = client;
    IOSink? sink;
    final timeout = Timer(
      const Duration(seconds: 90),
      () => client.close(force: true),
    );
    try {
      final request = await client.getUrl(uri);
      plan.headers.forEach(request.headers.set);
      request.headers.set('Accept-Encoding', 'identity');
      final response = await request.close();
      check();
      if (response.statusCode != 200) {
        throw AppFailure(
          '媒体服务器暂时拒绝播放（${response.statusCode}）',
          code: 'media_http',
        );
      }
      const maxBytes = 512 * 1024 * 1024;
      if (response.contentLength > maxBytes) {
        throw AppFailure('视频超过本地播放缓存限制', code: 'media_size');
      }
      sink = File(destination).openWrite();
      var received = 0;
      final prefix = <int>[];
      await sink.addStream(
        response.timeout(const Duration(seconds: 20)).map((chunk) {
          check();
          received += chunk.length;
          if (received > maxBytes) {
            throw AppFailure('视频超过本地播放缓存限制', code: 'media_size');
          }
          if (prefix.length < 12) prefix.addAll(chunk.take(12 - prefix.length));
          if (response.contentLength > 0) {
            progress(received / response.contentLength);
          }
          return chunk;
        }),
      );
      await sink.flush();
      if (response.contentLength > 0 && received != response.contentLength ||
          prefix.length < 12 ||
          !{
            'ftyp',
            'styp',
          }.contains(String.fromCharCodes(prefix.sublist(4, 8)))) {
        throw AppFailure('视频缓存不完整', code: 'media_incomplete');
      }
    } finally {
      timeout.cancel();
      await sink?.close();
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }

  Future<void> close() async {
    _closed = true;
    await cancel();
    await _tail;
    _streamOriginal = null;
    _streamUrl = null;
    final ready = _ready;
    _ready = null;
    if (ready != null && await ready.exists()) {
      await ready.delete(recursive: true);
    }
  }
}
