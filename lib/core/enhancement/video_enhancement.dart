import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:THLRedLook/core/enhancement/video_enhancement_detector.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_monitor.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_mpv.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_pipeline.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_policy.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_preferences.dart';
import 'package:THLRedLook/utils/media/video_output_size.dart';

class VideoEnhancementController extends ChangeNotifier {
  VideoEnhancementController({
    required this.player,
    required VideoController? video,
    required this._preferences,
    required String category,
    required List<String> tags,
  }) : _animationHint = videoHasAnimationTags(category, tags) {
    final native = player.platform;
    supported =
        video != null &&
        native is NativePlayer &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (!supported) {
      _status = '当前平台暂不支持画质增强';
      return;
    }
    _mpv = VideoEnhancementMpv(native as NativePlayer);
    _pipeline = VideoEnhancementPipeline(_mpv!, _filterLabel);
    _output = VideoOutputSizeAdapter(video!, onFailure: _outputFailed);
    _subscriptions.addAll([
      player.stream.log.listen(_onLog),
      player.stream.videoParams.listen((_) => _schedule()),
      player.stream.rate.listen((_) {
        _ignorePerformanceUntil = DateTime.now().add(const Duration(seconds: 5));
        _schedule();
      }),
      player.stream.buffering.listen((buffering) {
        if (buffering) ignorePerformance();
      }),
    ]);
    _initialization = _initialize();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _startMonitor());
  }

  static const _filterLabel = 'duanju_vsr';
  final Player player;
  late final bool supported;
  final bool _animationHint;
  VideoEnhancementPreferences _preferences;
  VideoEnhancementMpv? _mpv;
  VideoEnhancementPipeline? _pipeline;
  final VideoEnhancementDetector _detector = VideoEnhancementDetector(
    filterLabel: _filterLabel,
  );
  final VideoEnhancementMonitor _monitor = VideoEnhancementMonitor(_filterLabel);
  VideoOutputSizeAdapter? _output;
  Future<void>? _initialization, _monitoring, _closing;
  Future<void> _tail = Future<void>.value();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _rejected = <VideoEnhancementBackend>{};
  Timer? _timer, _debounce;
  int _revision = 0, _costLimit = 4, _confirmationMisses = 0, _failureCount = 0;
  DateTime _ignorePerformanceUntil = DateTime.fromMillisecondsSinceEpoch(0);
  VideoEnhancementDecision? _applied;
  VideoEnhancementBackend? _applyingBackend;
  bool _ready = false,
      _initialized = false,
      _foreground = true,
      _television = false,
      _closed = false,
      _comparing = false,
      _confirmed = false,
      _circuitOpen = false;
  String _status = '画质增强已关闭', _downgradeReason = '', _lastFailure = '';
  Size _viewport = Size.zero;

  VideoEnhancementPreferences get preferences => _preferences;
  bool get comparing => _comparing;
  bool get canCompare =>
      supported &&
      _ready &&
      _foreground &&
      !_circuitOpen &&
      _preferences.mode != VideoEnhancementMode.off &&
      (_comparing || (_applied?.backend.cost ?? 0) > 0);
  bool get animation => switch (_preferences.content) {
    VideoEnhancementContent.automatic => _animationHint,
    VideoEnhancementContent.animation => true,
    VideoEnhancementContent.general => false,
  };
  String get status => _status;
  String get contentLabel => animation ? '当前按动漫增强' : '当前按通用画面增强';
  String get detail => formatEnhancementDetail(
    source: videoDisplaySize(player.state.videoParams),
    output: _applied?.output,
    downgradeReason: _downgradeReason,
  );

  VideoEnhancementDecision _choose({required bool ready}) => _detector.choose(
    preferences: _preferences,
    parameters: player.state.videoParams,
    viewport: _viewport,
    ready: ready,
    television: _television,
    animation: animation,
    rate: player.state.rate,
    costLimit: _costLimit,
    rejected: _rejected,
  );

  void _downgradeCost(int maxCost, String reason) {
    _costLimit = math.min(_costLimit, maxCost);
    _downgradeReason = reason;
    ignorePerformance();
    _schedule(immediate: true);
  }

  Future<void> _initialize() async {
    try {
      await _mpv!.initialize();
      if (_closed) return;
      await _output!.initialize();
      if (_closed) return;
      _initialized = true;
      await _detector.readPower();
      _detector.readCapabilities(mpv: _mpv!, videoParams: player.state.videoParams);
      _schedule();
    } catch (_) {
      if (!_closed) _setStatus('增强初始化失败，继续原画播放');
    }
  }

  void _resetFaultState() {
    _costLimit = 4;
    _downgradeReason = '';
    _lastFailure = '';
    _failureCount = 0;
    _circuitOpen = false;
  }

  void setPreferences(VideoEnhancementPreferences value) {
    if (_closed || value == _preferences) return;
    _preferences = value;
    _comparing = false;
    _rejected.clear();
    _resetFaultState();
    _schedule(immediate: true);
    notifyListeners();
  }

  void setViewport(Size pixels, {required bool television}) {
    if (_closed || !supported || (_viewport == pixels && _television == television)) return;
    _viewport = pixels;
    _television = television;
    ignorePerformance();
    _schedule();
  }

  void setForeground(bool value) {
    if (_closed || _foreground == value) return;
    _foreground = value;
    ignorePerformance();
    _schedule(immediate: true);
  }

  void suspend() {
    if (_closed) return;
    _ready = false;
    _comparing = false;
    _revision++;
    _schedule(immediate: true);
  }

  Future<void> beforeMedia() async {
    if (_closed || !supported) return;
    _ready = false;
    _comparing = false;
    _revision++;
    _debounce?.cancel();
    _resetFaultState();
    _detector.recentEnhancementErrors.clear();
    _monitor.reset();
    ignorePerformance();
    await _enqueue(() async {
      await _initialization;
      if (_closed || !_initialized) return;
      _resetPipelineOutput();
      _applied = null;
      _confirmed = false;
    });
  }

  void _resetPipelineOutput() {
    _pipeline?.clearEffects();
    _output?.setTarget(null);
  }

  void mediaReady() {
    if (_closed) return;
    _ready = true;
    ignorePerformance();
    _schedule();
  }

  void ignorePerformance() {
    _ignorePerformanceUntil = DateTime.now().add(const Duration(seconds: 6));
    _monitor.reset();
  }

  Future<void> toggleCompare() async {
    if (!canCompare || _closed) return;
    _comparing = !_comparing;
    ignorePerformance();
    _schedule(immediate: true);
    notifyListeners();
    await _tail;
  }

  void _schedule({bool immediate = false}) {
    if (_closed || !supported || _circuitOpen) return;
    final revision = ++_revision;
    _debounce?.cancel();
    void run() => unawaited(_enqueue(() => _apply(revision)));
    if (immediate) {
      run();
    } else {
      _debounce = Timer(const Duration(milliseconds: 220), run);
    }
  }

  Future<void> _enqueue(Future<void> Function() work) {
    final next = _tail.then((_) async {
      if (_closed) return;
      try {
        await work();
      } catch (error) {
        if (!_closed) _failBackend(error);
      }
    });
    _tail = next.catchError((Object _) {});
    return _tail;
  }

  Future<void> _apply(int revision) async {
    await _initialization;
    if (_closed || !_initialized || revision != _revision) return;
    _detector.readCapabilities(mpv: _mpv!, videoParams: player.state.videoParams);
    final decision = _choose(ready: _ready && _foreground);
    final selected = _comparing && canCompare
        ? VideoEnhancementDecision(VideoEnhancementBackend.original, decision.output, '原画对比中')
        : decision;
    if (selected == _applied) {
      _publishStatus();
      return;
    }
    _applyingBackend = selected.backend;
    try {
      _applied = null;
      _pipeline?.clearEffects();
      await _output!.setTarget(selected.output);
      if (_closed || revision != _revision) return;

      final parameters = player.state.videoParams;
      await _pipeline?.prepareAndApply(
        selected: selected,
        luma: _detector.luma,
        vendor: _detector.vendor,
        videoW: parameters.w?.toDouble(),
        videoH: parameters.h?.toDouble(),
      );

      _applied = selected;
      _confirmationMisses = 0;
      _confirmed = selected.backend == VideoEnhancementBackend.original;
      ignorePerformance();
      _publishStatus();
      if (!_closed) notifyListeners();
    } catch (error) {
      _failBackend(error, backend: selected.backend);
    } finally {
      _applyingBackend = null;
    }
  }

  void _onLog(PlayerLog log) {
    if (_closed) return;
    _detector.processLog(
      log,
      circuitOpen: _circuitOpen,
      activeBackend: _applyingBackend ?? _applied?.backend,
      onRendererChanged: _schedule,
      onRenderFailed: _failBackend,
    );
  }

  bool handlePlaybackError(String text) {
    if (_closed || !supported) return false;
    final active = (_applyingBackend ?? _applied?.backend)?.cost ?? 0;
    if (!_detector.handlePlaybackError(text, activeCost: active)) return false;
    _failBackend(const VideoEnhancementFailure('render'));
    return true;
  }

  void _outputFailed() {
    if (_closed || _costLimit == 0) return;
    _costLimit = 0;
    _failBackend(const VideoEnhancementFailure('output-size'));
  }

  void _failBackend(Object error, {VideoEnhancementBackend? backend}) {
    if (_closed || _circuitOpen) return;
    final stage = error is VideoEnhancementFailure ? error.stage : 'resource';
    debugPrint('Video enhancement failed: $stage');
    final failed = backend ?? _applyingBackend ?? _applied?.backend;
    _failureCount++;
    _applyingBackend = null;
    if (failed != null) _rejected.add(failed);
    if (failed == VideoEnhancementBackend.scaling ||
        failed == VideoEnhancementBackend.original ||
        stage == 'output-size') {
      _costLimit = 0;
    }
    _lastFailure = stage;
    _downgradeReason = '增强不可用，已自动回退';
    _applied = null;
    _confirmed = false;
    _setStatus('正在恢复原画播放');
    if (_failureCount >= 4 || failed == VideoEnhancementBackend.original) {
      _tripCircuitBreaker();
      return;
    }
    _schedule(immediate: true);
  }

  void _tripCircuitBreaker() {
    _circuitOpen = true;
    _costLimit = 0;
    _revision++;
    _debounce?.cancel();
    unawaited(_enqueue(() async {
      try {
        _resetPipelineOutput();
        if (_closed) return;
        _applied = const VideoEnhancementDecision(
          VideoEnhancementBackend.original,
          null,
          '增强不可用，已恢复原画',
        );
        _setStatus('增强不可用，已恢复原画');
      } catch (_) {
        _setStatus('增强已停用，请重新打开本集');
      }
    }));
  }

  void _startMonitor() {
    if (_closed ||
        !_initialized ||
        _monitoring != null ||
        _circuitOpen ||
        !_foreground ||
        !_ready ||
        _preferences.mode == VideoEnhancementMode.off) {
      return;
    }
    final future = _monitorCheck();
    _monitoring = future;
    unawaited(future.whenComplete(() {
      if (identical(_monitoring, future)) _monitoring = null;
    }));
  }

  Future<void> _monitorCheck() async {
    try {
      await _detector.readPower();
      if (_closed ||
          !_initialized ||
          _circuitOpen ||
          _applyingBackend != null) {
        return;
      }
      if (_detector.readCapabilities(mpv: _mpv!, videoParams: player.state.videoParams)) {
        _schedule();
      }
      if (!_ready || !_foreground) return;
      final selected = _applied;
      if (selected == null) {
        _schedule();
        return;
      }
      final reassessed = _choose(ready: true);
      if (!_comparing && reassessed != selected) {
        if (reassessed.backend.cost < selected.backend.cost &&
            (_detector.power.thermalStatus >= 2 ||
                (_detector.power.headroom ?? 0) >= .85)) {
          _downgradeCost(reassessed.backend.cost, '本集已因温控降低增强');
        } else {
          _schedule();
        }
        return;
      }
      if (selected.backend == VideoEnhancementBackend.original) return;
      final passes = _mpv!.read('vo-passes');
      final fresh = passes is Map && passes['fresh'] is List
          ? passes['fresh'] as List
          : const [];
      final sizeMatches = _monitor.checkSizeMatches(
        mpv: _mpv!,
        actual: _output!.actualSize,
        target: selected.output,
      );
      final effectFound = _monitor.checkEffectFound(
        mpv: _mpv!,
        selected: selected,
        fresh: fresh,
        luma: _detector.luma,
        gpu: _detector.gpu,
      );
      final verification = _monitor.verifyConfirmation(
        sizeMatches: sizeMatches,
        effectFound: effectFound,
        isPlaying: player.state.playing,
        isBuffering: player.state.buffering,
        currentMisses: _confirmationMisses,
      );
      _confirmationMisses = verification.misses;
      if (verification.failure != null) {
        _failBackend(verification.failure!);
        return;
      }
      final wasConfirmed = _confirmed;
      _confirmed = verification.confirmed;
      _publishStatus();
      if (wasConfirmed != _confirmed && !_closed) notifyListeners();

      final overloaded = _monitor.checkOverloaded(
        player: player,
        mpv: _mpv!,
        selected: selected,
        fresh: fresh,
        confirmed: _confirmed,
        comparing: _comparing,
        ignorePerformanceUntil: _ignorePerformanceUntil,
      );
      if (overloaded) {
        _downgradeCost(
          selected.backend == VideoEnhancementBackend.hardware
              ? 2
              : selected.backend.cost - 1,
          '本集已为保持流畅降低增强',
        );
      }
    } catch (_) {
      if (!_closed) _monitor.reset();
    }
  }

  void _publishStatus() {
    final status = formatEnhancementStatus(
      decision: _applied,
      comparing: _comparing,
      confirmed: _confirmed,
      lastFailure: _lastFailure,
      mode: _preferences.mode,
    );
    if (status.isNotEmpty) _setStatus(status);
  }

  void _setStatus(String value) {
    if (_closed || value == _status) return;
    _status = value;
    notifyListeners();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _revision++;
    _timer?.cancel();
    _debounce?.cancel();
    await Future.wait(_subscriptions.map((s) => s.cancel()));
    await _initialization;
    await _tail;
    await _monitoring;
    await _output?.close();
    if (_mpv != null) _mpv!.closed = true;
    super.dispose();
  }
}
