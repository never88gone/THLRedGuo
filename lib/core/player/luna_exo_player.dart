import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as kit;
import 'package:video_player/video_player.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';

/// 模拟与 media_kit.PlayerStream 接口对齐的流集合
class LunaPlayerStreams implements PlayerStream {
  final StreamController<Duration> positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> durationController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> bufferController =
      StreamController<Duration>.broadcast();
  final StreamController<bool> playingController =
      StreamController<bool>.broadcast();
  final StreamController<bool> bufferingController =
      StreamController<bool>.broadcast();
  final StreamController<bool> completedController =
      StreamController<bool>.broadcast();
  final StreamController<String> errorController =
      StreamController<String>.broadcast();
  final StreamController<double> volumeController =
      StreamController<double>.broadcast();
  final StreamController<double> rateController =
      StreamController<double>.broadcast();
  final StreamController<VideoParams> videoParamsController =
      StreamController<VideoParams>.broadcast();
  final StreamController<PlayerLog> logController =
      StreamController<PlayerLog>.broadcast();
  final StreamController<double> pitchController =
      StreamController<double>.broadcast();

  @override
  Stream<Duration> get position => positionController.stream;

  @override
  Stream<Duration> get duration => durationController.stream;

  @override
  Stream<Duration> get buffer => bufferController.stream;

  @override
  Stream<bool> get playing => playingController.stream;

  @override
  Stream<bool> get buffering => bufferingController.stream;

  @override
  Stream<bool> get completed => completedController.stream;

  @override
  Stream<String> get error => errorController.stream;

  @override
  Stream<double> get volume => volumeController.stream;

  @override
  Stream<double> get rate => rateController.stream;

  @override
  Stream<VideoParams> get videoParams => videoParamsController.stream;

  @override
  Stream<PlayerLog> get log => logController.stream;

  @override
  Stream<double> get pitch => pitchController.stream;

  void dispose() {
    positionController.close();
    durationController.close();
    bufferController.close();
    playingController.close();
    bufferingController.close();
    completedController.close();
    errorController.close();
    volumeController.close();
    rateController.close();
    videoParamsController.close();
    logController.close();
    pitchController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      return const Stream<dynamic>.empty();
    }
    return null;
  }
}

class _LunaVideoPlayerController extends VideoPlayerController {
  _LunaVideoPlayerController.file(super.file, {super.videoPlayerOptions})
    : super.file();

  _LunaVideoPlayerController.networkUrl(
    super.uri, {
    super.formatHint,
    super.httpHeaders,
    super.videoPlayerOptions,
  }) : super.networkUrl();

  final _pendingSeeks = <Future<void>>{};
  bool _retiring = false;
  Future<void>? _releaseFuture;

  @override
  Future<void> seekTo(Duration position) async {
    if (_retiring) return;
    final completion = Completer<void>();
    _pendingSeeks.add(completion.future);
    try {
      await super.seekTo(position);
    } finally {
      _pendingSeeks.remove(completion.future);
      completion.complete();
    }
  }

  @override
  Future<void> dispose() {
    _retiring = true;
    return _releaseFuture ??= () async {
      await Future.wait(_pendingSeeks.toList());
      await super.dispose();
    }();
  }
}

/// 采用和 LunaTV-Mobile 完全相同架构的 ExoPlayer (AndroidX Media3) 播放器封装，
/// 同时对上层播控 UI (PlayerControls & TelevisionControls) 暴露完全兼容的 Player 契约。
class LunaExoPlayer implements Player {
  LunaExoPlayer({this.initializationTimeout = const Duration(seconds: 30)}) {
    state = const PlayerState().copyWith(volume: 100.0);
  }

  VideoPlayerController? _controller;
  final Duration initializationTimeout;
  VoidCallback? _valueListener;
  Timer? _positionPollTimer;
  Timer? _watchdogTimer;
  int _consecutiveZeroSizeTicks = 0;
  PlaybackDecoderMode _decoderMode = PlaybackDecoderMode.hardware;

  PlaybackDecoderMode get decoderMode => _decoderMode;
  bool get isHardwareDecoding => true;

  void setDecoderMode(PlaybackDecoderMode mode) {
    if (_decoderMode == mode) return;
    _decoderMode = mode;
    DiaryService.add('[ExoPlayer] 设置解码模式: ${mode.label}');
  }

  int _openGeneration = 0;
  int _seekSequence = 0;
  int _pendingSeekSequence = 0;
  Future<void> _seekOperations = Future<void>.value();
  bool _disposed = false;
  Future<void>? _disposeFuture;
  String? _controllerError;
  Player? _streamPlayer;
  kit.VideoController? _streamVideo;
  final List<StreamSubscription<dynamic>> _streamSubscriptions = [];

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  @override
  PlayerState state = const PlayerState();

  @override
  final LunaPlayerStreams stream = LunaPlayerStreams();

  @override
  PlatformPlayer? get platform => _streamPlayer?.platform;

  @override
  Future<int> get handle => Future<int>.value(0);

  VideoPlayerController? get controller => _controller;
  bool get streamingDecryption => _streamPlayer != null;
  String get mediaUri {
    final playlist = _streamPlayer?.state.playlist.medias;
    if (playlist != null && playlist.isNotEmpty) return playlist.first.uri;
    return _controller?.dataSource ?? '';
  }

  Future<void> waitForVideoFrame() async {
    await _streamVideo?.waitUntilFirstFrameRendered;
  }

  Future<int> audioTrackCount() async {
    final native = _streamPlayer;
    if (native != null) {
      return native.state.tracks.audio
          .where((track) => track.id != 'auto' && track.id != 'no')
          .length;
    }
    return (await _controller?.getAudioTracks())?.length ?? 0;
  }

  Future<void> _openEncrypted(Media media, String key, bool play) async {
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(key)) {
      throw const FormatException('视频内容密钥无效');
    }
    await stop();
    if (_disposed) return;
    MediaKit.ensureInitialized();
    final generation = ++_openGeneration;
    final volume = state.volume;
    final rate = state.rate;
    final native = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    _streamPlayer = native;
    _streamVideo = kit.VideoController(native);
    WidgetsBinding.instance.scheduleFrame();
    void mirror<T>(
      Stream<T> input,
      StreamController<T> output, {
      bool repaint = false,
    }) {
      _streamSubscriptions.add(
        input.listen((value) {
          if (_disposed ||
              generation != _openGeneration ||
              !identical(native, _streamPlayer)) {
            return;
          }
          state = native.state;
          _safeAdd(output, value);
          if (repaint) revision.value++;
        }),
      );
    }

    mirror(native.stream.position, stream.positionController);
    mirror(native.stream.duration, stream.durationController);
    mirror(native.stream.buffer, stream.bufferController);
    mirror(native.stream.playing, stream.playingController, repaint: true);
    mirror(native.stream.buffering, stream.bufferingController, repaint: true);
    mirror(native.stream.completed, stream.completedController, repaint: true);
    mirror(
      native.stream.videoParams,
      stream.videoParamsController,
      repaint: true,
    );
    mirror(native.stream.error, stream.errorController);
    mirror(native.stream.volume, stream.volumeController);
    mirror(native.stream.rate, stream.rateController);
    try {
      final backend = native.platform as NativePlayer;
      await backend.setProperty('demuxer-lavf-o', 'decryption_key=$key');
      await backend.setProperty('network-timeout', '20');
      await native.setVolume(volume);
      await native.setRate(rate);
      if (_disposed || generation != _openGeneration) return;
      await native.open(media, play: play);
      if (!_disposed && generation == _openGeneration) revision.value++;
    } catch (_) {
      if (identical(native, _streamPlayer)) await stop();
      rethrow;
    }
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (_disposed) return;
    if (playable is! Media) return;

    final media = playable;
    final url = media.uri;
    if (url.isEmpty) return;
    final key = media.extras?['decryptionKey']?.toString() ?? '';
    if (key.isNotEmpty) {
      return _openEncrypted(media, key, play);
    }
    if (_streamPlayer != null) await stop();

    final myGen = ++_openGeneration;
    _pendingSeekSequence = 0;
    _seekOperations = Future<void>.value();
    _positionPollTimer?.cancel();
    _watchdogTimer?.cancel();

    // 关键核心：在 Android TV 上，MediaCodec 硬件视频解码器通常仅支持单实例并发。
    // 切换集数或换源时，必须严格执行串行释放：立即卸载旧控制器并彻底 dispose，
    // 防止新旧两个 ExoPlayer 实例在底层同时竞争同一个硬件解码器导致底层崩溃或静默黑屏。
    final old = _controller;
    _controller = null;
    if (old != null) {
      if (_valueListener != null) {
        try {
          old.removeListener(_valueListener!);
        } catch (_) {}
        _valueListener = null;
      }
      try {
        await old.pause();
      } catch (_) {}
      try {
        await old.dispose();
      } catch (_) {}
      // 在 Android 电视端/低运存设备，底层 MediaCodec release 具有短暂的驱动回收延迟
      // 让出微小等待周期，彻底释放硬件解码器句柄与 Surface
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }

    if (_disposed || myGen != _openGeneration) return;
    revision.value++;

    state = state.copyWith(completed: false);
    _safeAdd(stream.completedController, false);

    final Map<String, String> headers = <String, String>{};
    try {
      if (media.httpHeaders != null) {
        headers.addAll(Map<String, String>.from(media.httpHeaders!));
      }
    } catch (_) {}

    // 针对防盗链 CDN 注入标准移动端 UA
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] =
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    }

    bool isHls =
        url.toLowerCase().contains('.m3u8') ||
        url.toLowerCase().contains('hls') ||
        (headers['accept']?.contains('mpegurl') ?? false);
    var confirmedMp4 = false;

    final uri = Uri.tryParse(url);
    if (uri == null && !url.startsWith('/')) {
      DiaryService.add('[ExoPlayer] 错误: 无效的播放地址 $url');
      throw Exception('无效的播放地址: $url');
    }

    // 先导探测：如果尚未显式判定为 HLS，向网络地址快速嗅探前置响应头与内容，智能识别
    if (!isHls &&
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https')) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      try {
        final req = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 3));
        headers.forEach((k, v) => req.headers.set(k, v));
        req.headers.set('Range', 'bytes=0-512');
        final resp = await req.close().timeout(const Duration(seconds: 3));
        final cType = resp.headers.contentType?.toString().toLowerCase() ?? '';
        final chunks = await resp
            .take(1)
            .timeout(const Duration(seconds: 3))
            .toList();
        final firstChunk = chunks.isNotEmpty
            ? String.fromCharCodes(chunks.first)
            : '';
        confirmedMp4 =
            cType.contains('video/mp4') ||
            firstChunk.length >= 8 && firstChunk.substring(4, 8) == 'ftyp';
        DiaryService.add(
          '[Sniff] 探测结果: status=${resp.statusCode}, contentType=$cType, prefix=${firstChunk.length > 20 ? firstChunk.substring(0, 20) : firstChunk}',
        );
        if (cType.contains('mpegurl') || firstChunk.contains('#EXTM3U')) {
          isHls = true;
          DiaryService.add(
            '[Sniff] 自动识别为 HLS 流，注入 formatHint: VideoFormat.hls',
          );
        }
      } catch (e) {
        DiaryService.add('[Sniff] 探测警告 (非致命): $e');
      } finally {
        client.close(force: true);
      }
    }

    VideoFormat? formatHint = isHls ? VideoFormat.hls : null;

    DiaryService.add(
      '[ExoPlayer] open(gen=$myGen): local=${url.startsWith('/') || uri?.scheme == 'file'}, host=${uri?.host}, isHls=$isHls, formatHint=$formatHint',
    );

    VideoPlayerController c;
    if (url.startsWith('/') || (uri != null && uri.scheme == 'file')) {
      final filePath = uri != null && uri.scheme == 'file'
          ? uri.toFilePath()
          : url;
      DiaryService.add('[ExoPlayer] 本地缓存播放');
      c = _LunaVideoPlayerController.file(
        File(filePath),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    } else {
      c = _LunaVideoPlayerController.networkUrl(
        uri!,
        formatHint: formatHint,
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    }

    try {
      DiaryService.add(
        '[ExoPlayer] c.initialize() 开始 (formatHint=$formatHint)...',
      );
      await c.initialize().timeout(initializationTimeout);
      DiaryService.add(
        '[ExoPlayer] c.initialize() 成功! duration=${c.value.duration}, size=${c.value.size}, isInitialized=${c.value.isInitialized}',
      );
    } catch (e, stack) {
      DiaryService.add('[ExoPlayer] 首次 initialize 失败: $e');
      if (!confirmedMp4 &&
          uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        final alternateFormat = formatHint == VideoFormat.hls
            ? null
            : VideoFormat.hls;
        DiaryService.add(
          '[ExoPlayer] 启动自愈重试，切换格式为 formatHint=$alternateFormat...',
        );
        try {
          await c.dispose();
        } catch (_) {}

        final retryHeaders = Map<String, String>.from(headers);
        if (alternateFormat == VideoFormat.hls) {
          retryHeaders['Accept'] =
              'application/vnd.apple.mpegurl,application/x-mpegURL,*/*';
        }
        c = _LunaVideoPlayerController.networkUrl(
          uri,
          formatHint: alternateFormat,
          httpHeaders: retryHeaders,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        try {
          await c.initialize().timeout(initializationTimeout);
          formatHint = alternateFormat;
          DiaryService.add('[ExoPlayer] 自愈重试成功! duration=${c.value.duration}');
        } catch (retryErr, retryStack) {
          DiaryService.add(
            '[ExoPlayer] 自愈重试依然失败! 异常: $retryErr\n堆栈: $retryStack',
          );
          if (myGen == _openGeneration) {
            _safeAdd(stream.errorController, retryErr.toString());
          }
          try {
            await c.dispose();
          } catch (_) {}
          rethrow;
        }
      } else {
        DiaryService.add('[ExoPlayer] c.initialize() 失败! 异常: $e\n堆栈: $stack');
        if (myGen == _openGeneration) {
          _safeAdd(stream.errorController, e.toString());
        }
        try {
          await c.dispose();
        } catch (_) {}
        rethrow;
      }
    }

    if (_disposed || myGen != _openGeneration) {
      try {
        await c.dispose();
      } catch (_) {}
      return;
    }

    _controller = c;
    _controllerError = null;
    final dur = c.value.duration;
    final w = c.value.size.width.round();
    final h = c.value.size.height.round();
    final videoParams = VideoParams(w: w, h: h, dw: w, dh: h);

    state = state.copyWith(
      duration: dur,
      position: Duration.zero,
      playing: play,
      buffering: c.value.isBuffering,
      width: w > 0 ? w : 1920,
      height: h > 0 ? h : 1080,
      videoParams: videoParams,
    );

    _safeAdd(stream.durationController, dur);
    _safeAdd(stream.positionController, Duration.zero);
    _safeAdd(stream.playingController, play);
    _safeAdd(stream.bufferingController, c.value.isBuffering);
    _safeAdd(stream.videoParamsController, videoParams);

    _valueListener = () => _onControllerValue(c);
    c.addListener(_valueListener!);

    // 定时轮询真实播放位置 (与 LunaTV-Mobile 对齐)
    _startPositionPolling();

    // 启动大屏黑屏与首帧无画面自愈看门狗
    _startWatchdog(c, myGen);

    if (media.start != null && media.start! > Duration.zero) {
      try {
        await c.seekTo(media.start!);
        state = state.copyWith(position: media.start!);
        _safeAdd(stream.positionController, media.start!);
      } catch (_) {}
    }

    if (play) {
      try {
        await c.play();
      } catch (_) {}
    }
    revision.value++;
  }

  void _startPositionPolling() {
    _positionPollTimer?.cancel();
    _positionPollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final c = _controller;
      if (c == null || !c.value.isInitialized) return;
      final pos = c.value.position;
      if (_pendingSeekSequence == 0 && pos != state.position) {
        state = state.copyWith(position: pos);
        _safeAdd(stream.positionController, pos);
      }
    });
  }

  void _startWatchdog(VideoPlayerController c, int gen) {
    _watchdogTimer?.cancel();
    _consecutiveZeroSizeTicks = 0;
    _watchdogTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      if (_disposed || gen != _openGeneration || _controller != c) {
        timer.cancel();
        return;
      }
      if (!c.value.isInitialized) return;
      if (c.value.isPlaying && c.value.position > const Duration(seconds: 1)) {
        final size = c.value.size;
        if (size.width == 0 || size.height == 0) {
          _consecutiveZeroSizeTicks++;
          DiaryService.add(
            '[ExoPlayer Watchdog] 警告: 正在播放中但视频画面尺寸为 0x0 (tick=$_consecutiveZeroSizeTicks)',
          );
          if (_consecutiveZeroSizeTicks >= 2) {
            DiaryService.add('[ExoPlayer Watchdog] 尝试触发硬解管线冲洗 (Keyframe Flush)...');
            try {
              final pos = c.value.position;
              await c.seekTo(pos);
            } catch (_) {}
          }
        } else {
          _consecutiveZeroSizeTicks = 0;
          timer.cancel();
        }
      }
    });
  }

  void _onControllerValue(VideoPlayerController c) {
    if (_disposed || _controller != c) return;
    final v = c.value;

    bool stateChanged = false;
    if (v.isPlaying != state.playing) {
      DiaryService.add('[ExoPlayer] isPlaying 变为: ${v.isPlaying}');
      state = state.copyWith(playing: v.isPlaying);
      _safeAdd(stream.playingController, v.isPlaying);
      stateChanged = true;
    }
    if (v.isBuffering != state.buffering) {
      DiaryService.add('[ExoPlayer] isBuffering 变为: ${v.isBuffering}');
      state = state.copyWith(buffering: v.isBuffering);
      _safeAdd(stream.bufferingController, v.isBuffering);
      stateChanged = true;
    }
    if (v.hasError) {
      final error = v.errorDescription ?? '视频读取失败';
      if (_controllerError != error) {
        _controllerError = error;
        DiaryService.add('[ExoPlayer] controller error: $error');
        _safeAdd(stream.errorController, error);
      }
    }
    final dur = v.duration;
    if (dur > Duration.zero && dur != state.duration) {
      state = state.copyWith(duration: dur);
      _safeAdd(stream.durationController, dur);
      stateChanged = true;
    }
    final pos = v.position;
    if (_pendingSeekSequence == 0 && pos != state.position) {
      state = state.copyWith(position: pos);
      _safeAdd(stream.positionController, pos);
    }
    if (v.buffered.isNotEmpty) {
      final lastRange = v.buffered.last;
      if (lastRange.end != state.buffer) {
        state = state.copyWith(buffer: lastRange.end);
        _safeAdd(stream.bufferController, state.buffer);
      }
    }
    if (v.isCompleted != state.completed) {
      state = state.copyWith(completed: v.isCompleted);
      _safeAdd(stream.completedController, v.isCompleted);
      stateChanged = true;
    }

    if (stateChanged) {
      revision.value++;
    }
  }

  @override
  Future<void> play() async {
    if (_streamPlayer != null) return _streamPlayer!.play();
    final c = _controller;
    if (c == null) return;
    try {
      await c.play();
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    if (_streamPlayer != null) return _streamPlayer!.pause();
    final c = _controller;
    if (c == null) return;
    try {
      await c.pause();
    } catch (_) {}
  }

  @override
  Future<void> playOrPause() async {
    if (_streamPlayer != null) return _streamPlayer!.playOrPause();
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration target) async {
    if (_streamPlayer != null) return _streamPlayer!.seek(target);
    final c = _controller;
    if (c == null) return;
    final generation = _openGeneration;
    final sequence = ++_seekSequence;
    final bounded = target < Duration.zero
        ? Duration.zero
        : c.value.duration > Duration.zero && target > c.value.duration
        ? c.value.duration
        : target;
    _pendingSeekSequence = sequence;
    final operation = _seekOperations.catchError((Object _) {}).then((_) async {
      bool current() =>
          !_disposed &&
          _controller == c &&
          generation == _openGeneration &&
          sequence == _seekSequence;
      if (!current()) return;
      try {
        await c.seekTo(bounded);
        if (!current()) return;
        state = state.copyWith(position: bounded);
        _safeAdd(stream.positionController, bounded);
        if (state.completed) {
          state = state.copyWith(completed: false);
          _safeAdd(stream.completedController, false);
        }
      } finally {
        if (current()) _pendingSeekSequence = 0;
      }
    });
    _seekOperations = operation;
    await operation;
  }

  @override
  Future<void> setRate(double rate) async {
    if (_streamPlayer != null) return _streamPlayer!.setRate(rate);
    final r = rate.clamp(0.25, 4.0);
    state = state.copyWith(rate: r);
    _safeAdd(stream.rateController, r);
    final c = _controller;
    if (c == null) return;
    try {
      await c.setPlaybackSpeed(r);
    } catch (_) {}
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_streamPlayer != null) return _streamPlayer!.setVolume(volume);
    final v = volume.clamp(0.0, 100.0);
    state = state.copyWith(volume: v);
    _safeAdd(stream.volumeController, v);
    final c = _controller;
    if (c == null) return;
    try {
      await c.setVolume(v / 100.0);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _openGeneration++;
    _pendingSeekSequence = 0;
    _seekOperations = Future<void>.value();
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    final c = _controller;
    _controller = null;
    _controllerError = null;
    final native = _streamPlayer;
    _streamPlayer = null;
    _streamVideo = null;
    for (final subscription in _streamSubscriptions) {
      await subscription.cancel();
    }
    _streamSubscriptions.clear();
    final listener = _valueListener;
    _valueListener = null;
    if (c != null && listener != null) {
      try {
        c.removeListener(listener);
      } catch (_) {}
    }
    state = state.copyWith(
      playlist: const Playlist([]),
      playing: false,
      buffering: false,
      completed: false,
      position: Duration.zero,
      duration: Duration.zero,
      buffer: Duration.zero,
    );
    _safeAdd(stream.playingController, false);
    _safeAdd(stream.bufferingController, false);
    _safeAdd(stream.positionController, Duration.zero);
    if (!_disposed) revision.value++;
    if (c != null) {
      try {
        await c.dispose();
      } catch (_) {}
    }
    await native?.dispose();
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _disposePlayer();

  Future<void> _disposePlayer() async {
    _disposed = true;
    await stop();
    stream.dispose();
  }

  void _safeAdd<T>(StreamController<T> ctl, T value) {
    if (!ctl.isClosed) ctl.add(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isMethod) return Future<void>.value();
    return null;
  }
}

/// 采用和 LunaTV-Mobile 完全相同架构的 ExoPlayer 视图组件
class LunaExoVideoView extends StatelessWidget {
  const LunaExoVideoView({
    super.key,
    required this.player,
    this.fit = BoxFit.contain,
    this.controls,
  });

  final LunaExoPlayer player;
  final BoxFit fit;
  final Widget Function(BuildContext)? controls;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player.revision,
      builder: (context, _) {
        final nativeVideo = player._streamVideo;
        final c = player.controller;
        final hasVideo = c != null && c.value.isInitialized;
        final rawRatio = hasVideo ? c.value.aspectRatio : 16 / 9;
        final ratio = (rawRatio > 0 && !rawRatio.isNaN && !rawRatio.isInfinite)
            ? rawRatio
            : 16 / 9;

        return Stack(
          fit: StackFit.expand,
          children: [
            if (nativeVideo != null)
              kit.Video(
                key: ObjectKey(nativeVideo),
                controller: nativeVideo,
                fit: fit,
                controls: kit.NoVideoControls,
              )
            else if (hasVideo)
              Center(
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: VideoPlayer(key: ObjectKey(c), c),
                ),
              )
            else
              const ColoredBox(color: AppColors.black),
            if (controls != null) controls!(context),
          ],
        );
      },
    );
  }
}
