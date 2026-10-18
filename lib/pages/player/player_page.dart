import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/utils/screen/app_orientation.dart';
import 'package:THLRedLook/utils/theme/app_theme.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/core/player/encrypted_playback.dart';
import 'package:THLRedLook/core/danmaku/danmaku_controller.dart';
import 'package:THLRedLook/views/download/download_picker.dart';
import 'package:THLRedLook/pages/downloads/downloads_page.dart';
import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/core/player/playback_loader.dart';
import 'package:THLRedLook/core/player/playback_preloader.dart';
import 'package:THLRedLook/core/player/playback_recovery.dart';
import 'package:THLRedLook/core/player/playback_diagnostics.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/core/player/player_interactions.dart';
import 'package:THLRedLook/views/player/player_menu.dart';
import 'package:THLRedLook/views/television/television_controls.dart';
import 'package:THLRedLook/core/lan/lan_controller.dart';
import 'package:THLRedLook/pages/lan/lan_page.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/utils/media/video_output_size.dart';
import 'package:THLRedLook/views/player/player_mobile_panel_view.dart';
import 'package:THLRedLook/views/player/player_desktop_panel_view.dart';
import 'package:THLRedLook/views/player/player_viewport_view.dart';
import 'package:THLRedLook/views/player/player_quality_sheet_view.dart';
import 'package:THLRedLook/utils/player/player_dialog_helper.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.detail,
    required this.initialIndex,
    required this.repository,
    required this.store,
    this.initialPosition = 0,
    this.localOnly = false,
    this.allowOnlineFallback = true,
    this.mediaId,
    this.playerFactory,
    this.videoBuilder,
    this.handoff,
    this.initialSeriesEntries,
    this.onSeasonChanged,
  });
  final DramaDetail detail;
  final int initialIndex;
  final double initialPosition;
  final bool localOnly;
  final bool allowOnlineFallback;
  final String? mediaId;
  final AppRepository repository;
  final LocalStore store;
  final LanIncomingPlayback? handoff;
  final List<HongguoSeriesEntry>? initialSeriesEntries;
  final ValueChanged<DramaDetail>? onSeasonChanged;
  @visibleForTesting
  final Player Function()? playerFactory;
  @visibleForTesting
  final Widget Function(Widget controls)? videoBuilder;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController? _video;
  late final VideoEnhancementController _enhancement;
  late final PlaybackLoader _loader;
  late final PlaybackPreloader _preloader;
  bool _preloadEnabled = true;
  late final DanmakuController _danmaku;
  int _seekSequence = 0;
  bool _danmakuEnabled = true;
  late final PlayerInteractions _interactions;
  final _playerFocus = FocusNode(debugLabel: 'player-surface');
  final _videoPaneKey = GlobalKey();
  final _menuRevision = ValueNotifier<int>(0);
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _recovery = PlaybackRecovery();
  final _encryptedPlayback = EncryptedPlayback();
  Object _lanIdentity = Object();
  bool _handoffOwned = true;
  double? _lanFirstPosition;
  String? _savedProgressKey;
  final _health = PlaybackHealth();
  Timer? _saveTimer;
  Timer? _healthTimer;
  Timer? _errorTimer;
  Timer? _pictureInPictureExitTimer;
  Future<void> _operations = Future<void>.value();
  late int _index;
  late final int _profileEpoch;
  int _openedIndex = -1;
  int _generation = 0;
  int _seasonSwitchTicket = 0;
  int _requestedQuality = 0;
  bool _loading = true;
  bool _forceOnline = false;
  bool _localFailure = false;
  bool _fullscreen = false;
  bool _automaticFullscreenSuppressed = false;
  bool _panelOpen = false;
  bool _autoAdvance = true;
  bool? _systemFullscreen;
  Orientation? _lastOrientation;
  bool _closed = false;
  bool _acceptErrors = false;
  bool _foreground = true;
  bool _playIntent = true;
  bool _lifecyclePaused = false;
  bool _resumeAfterInterruption = false;
  bool _showControlsOnPlaybackReady = true;
  bool _pendingError = false;
  bool _requireRecovery = false;
  bool _pictureInPictureSupported = false;
  bool _pictureInPictureActive = false;
  bool _pictureInPictureRequested = false;
  bool _pictureInPictureHandlerInstalled = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  String _loadingMessage = '正在准备播放';
  String? _error;
  String? _saveWarning;
  PlaybackPlan? _plan;
  double _speed = 1;
  double _aspectRatio = 9 / 16;
  double _resumePosition = 0;
  bool _rotating = false;
  bool _television = false;
  AppOrientationController? _orientationController;
  bool get _pictureInPictureVisible =>
      _pictureInPictureActive || _pictureInPictureRequested;
  bool get _canUsePictureInPicture =>
      !_television &&
      defaultTargetPlatform == TargetPlatform.android &&
      _pictureInPictureSupported;
  bool get _mobile =>
      !_television &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  VideoEnhancementController? get _enhancementForUi =>
      _enhancement.supported ? _enhancement : null;
  PlaybackPreferences get _preferences => PlaybackPreferences(
    speed: _speed,
    quality: _requestedQuality,
    autoAdvance: _autoAdvance,
    danmaku: _danmakuEnabled,
    preload: _preloadEnabled,
    enhancement: _enhancement.preferences,
  );
  String get _qualityLabel {
    if (_plan?.offline == true) return '本地原画';
    final q = _requestedQuality > 0
        ? _requestedQuality
        : (_plan?.quality ?? 720);
    if (q >= 1080) return '1080P';
    if (q >= 720) return '720P';
    return '${q}P';
  }

  String get _session => _plan?.session ?? '';
  double get _currentPosition =>
      _openedIndex == _index && _player.state.position.inMilliseconds > 0
      ? _player.state.position.inMilliseconds / 1000
      : _resumePosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialIndex;
    _profileEpoch = widget.handoff?.profileEpoch ?? widget.store.profileEpoch;
    final preferences = widget.store.playbackPreferences;
    _speed = preferences.speed;
    _requestedQuality = preferences.quality;
    _autoAdvance = true;
    _danmakuEnabled = preferences.danmaku;
    _preloadEnabled = true;
    _loader = PlaybackLoader(widget.repository);
    _preloader = PlaybackPreloader(widget.repository);
    _danmaku = DanmakuController(widget.repository)
      ..setEnabled(_danmakuEnabled);
    widget.store.addListener(_accessChanged);
    _player =
        widget.playerFactory?.call() ??
        ((Platform.isAndroid || Platform.isIOS)
            ? LunaExoPlayer()
            : Player(
                configuration: const PlayerConfiguration(
                  bufferSize: 32 * 1024 * 1024,
                  logLevel: MPVLogLevel.error,
                ),
              ));
    _video = widget.videoBuilder == null && _player is! LunaExoPlayer
        ? VideoController(
            _player,
            configuration: VideoControllerConfiguration(
              enableHardwareAcceleration: !Platform.isIOS,
            ),
          )
        : null;
    _enhancement = VideoEnhancementController(
      player: _player,
      video: _video,
      preferences: preferences.enhancement,
      category: widget.detail.drama.category,
      tags: widget.detail.drama.tags,
    );
    _interactions = PlayerInteractions(
      player: _player,
      available: () =>
          !_closed &&
          widget.store.profileEpoch == _profileEpoch &&
          !_loading &&
          _error == null &&
          _foreground &&
          !_panelOpen,
      baseSpeed: () => _speed,
      onTogglePlayback: _togglePlayback,
      onSeek: _seekTo,
      onFullscreen: _rotate,
      onEpisode: (direction) {
        final next = _index + direction;
        if (next < 0) return '已经是第一集';
        if (next >= widget.detail.episodes.length) return '已经是最后一集';
        unawaited(_play(next));
        return '第 ${widget.detail.episodes[next].number} 集';
      },
    );
    _playerFocus.addListener(() {
      if (!_playerFocus.hasPrimaryFocus && !_closed) _interactions.cancel();
    });
    _configurePictureInPicture();
    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (_enhancement.handlePlaybackError(error)) return;
        if (!_closed && _acceptErrors && mounted && error.trim().isNotEmpty) {
          if (!_pendingError) {
            DiaryService.add(
              '[Play] 原生播放错误: 剧=${widget.detail.drama.cleanSourceId}, 集=${widget.detail.episodes[_index].number}, ${playbackFailureSummary(AppFailure(error, code: 'native_stream'))}',
            );
          }
          _queueRecovery(force: PlaybackRecovery.audioOutputFailed(error));
        }
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed &&
            !_loading &&
            !_closed &&
            _acceptErrors &&
            _error == null) {
          final duration = _player.state.duration;
          if (duration <= Duration.zero ||
              _player.state.position < duration - const Duration(seconds: 2)) {
            _queueRecovery();
          } else if (_autoAdvance &&
              _foreground &&
              !_panelOpen &&
              _index + 1 < widget.detail.episodes.length) {
            _play(_index + 1, showControlsOnReady: false);
          } else {
            setState(() => _playIntent = false);
            _interactions.cancel();
            unawaited(_player.pause());
            unawaited(_saveProgress(flush: true));
          }
        }
      }),
    );
    _subscriptions.add(
      _player.stream.position.listen((position) {
        if (!_closed && _openedIndex == _index && position > Duration.zero) {
          _resumePosition = position.inMilliseconds / 1000;
        }
        _syncDanmaku();
        _syncPreload();
        _acknowledgeHandoff();
      }),
    );
    for (final stream in [
      _player.stream.duration,
      _player.stream.buffer,
      _player.stream.playing,
      _player.stream.buffering,
      _player.stream.rate,
      _player.stream.completed,
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          _syncDanmaku();
          _syncPreload();
          _acknowledgeHandoff();
        }),
      );
    }
    _subscriptions.add(
      _player.stream.videoParams.listen((parameters) {
        final size = videoDisplaySize(parameters);
        if (size != null && mounted && !_closed) {
          setState(() {
            _aspectRatio = size.width / size.height;
          });
          _scheduleSystemUi();
        }
      }),
    );
    _saveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveProgress(),
    );
    _healthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_closed &&
          _acceptErrors &&
          !_loading &&
          _error == null &&
          _health.stalled(
            position: _player.state.position,
            playing: _player.state.playing && _playIntent,
            buffering: _player.state.buffering && _playIntent,
            foreground: _foreground,
            now: DateTime.now(),
          )) {
        unawaited(_recover());
      }
    });
    final handoff = widget.handoff;
    if (handoff != null) {
      handoff.consumed = true;
      handoff.stop = () async {
        if (_handoffOwned && !_closed) await _stopForLan();
      };
    }
    if (_profileEpoch != widget.store.profileEpoch ||
        handoff?.cancelled == true) {
      handoff?.fail('接收用户已变更，推送已取消');
      if (handoff != null) {
        unawaited(widget.repository.release(handoff.plan.session));
      }
      _loading = false;
      _error = '播放接收已取消';
    } else {
      _play(
        _index,
        position: widget.initialPosition,
        handoffPlan: handoff?.plan,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closed) {
        widget.repository.catalogUpdates.publish(
          widget.repository.catalogUpdates.current(widget.detail.drama),
          retryCover: true,
        );
      }
    });
    _seriesEntries = widget.initialSeriesEntries;
    _discoverSeasons();
  }

  List<HongguoSeriesEntry>? _seriesEntries;

  List<HongguoSeriesEntry> get _currentSeriesEntries {
    if (_seriesEntries != null && _seriesEntries!.isNotEmpty) {
      return _seriesEntries!;
    }
    return hongguoSeriesEntries(
      widget.detail.drama,
      widget.store.seriesDramasFor(widget.detail.drama),
    );
  }

  Future<void> _discoverSeasons() async {
    try {
      final entries = await discoverSeriesSeasons(
        anchor: widget.detail.drama,
        repository: widget.repository,
        store: widget.store,
        existingEntries: _seriesEntries,
      );
      if (mounted && !_closed && entries.isNotEmpty) {
        setState(() {
          _seriesEntries = entries;
        });
      }
    } catch (_) {}
  }

  Future<void> _switchSeason(Drama seasonDrama) async {
    if (_closed || !mounted) return;
    if (seasonDrama.id == widget.detail.drama.id) return;

    final ticket = ++_seasonSwitchTicket;

    final anchor = widget.detail.drama;
    if (widget.store
            .following(anchor.id)
            ?.seriesSeasons[seasonDrama.id]
            ?.read ==
        false) {
      await saveUserChange(
        context,
        () => widget.store.markSeriesSeasonRead(anchor.id, seasonDrama.id),
      );
      if (!mounted) return;
    }

    _notice(
      '正在切换至 ${seasonDrama.title}...',
      duration: const Duration(milliseconds: 700),
    );

    try {
      seasonDrama = await resolveHongguoSeriesIdentity(
        drama: seasonDrama,
        repository: widget.repository,
        store: widget.store,
      );
      if (!mounted || _closed || ticket != _seasonSwitchTicket) return;
      final safeDrama =
          seasonDrama.sourceId.isEmpty || seasonDrama.sourceId.contains(':')
          ? Drama(
              id: seasonDrama.id,
              source: seasonDrama.source,
              sourceId: seasonDrama.cleanSourceId,
              title: seasonDrama.title,
              description: seasonDrama.description,
              cover: seasonDrama.cover,
              episodes: seasonDrama.episodes,
              category: seasonDrama.category,
              heat: seasonDrama.heat,
              views: seasonDrama.views,
              onlineDate: seasonDrama.onlineDate,
              tags: seasonDrama.tags,
              releaseStatus: seasonDrama.releaseStatus,
            )
          : seasonDrama;
      var nextDetail = await widget.repository.detail(safeDrama);
      if (!mounted || _closed || ticket != _seasonSwitchTicket) return;
      if (nextDetail.episodes.isEmpty && safeDrama.episodes > 0) {
        nextDetail = DramaDetail(
          safeDrama,
          List.generate(
            safeDrama.episodes,
            (index) => Episode({
              'id': '${safeDrama.cleanSourceId}_${index + 1}',
              'title': '第 ${index + 1} 集',
              'currentEpisode': index + 1,
            }, index + 1),
          ),
        );
      }
      if (nextDetail.episodes.isEmpty) {
        if (ticket == _seasonSwitchTicket) {
          _notice('该季暂无可用集数');
        }
        return;
      }

      final watched = widget.store.watched(seasonDrama.id);
      final initialIndex = resumeEpisodeIndex(nextDetail.episodes, watched);
      final initialPosition = (watched != null && watched.position > 0)
          ? watched.position.toDouble()
          : 0.0;

      if (ticket != _seasonSwitchTicket || !mounted || _closed) return;

      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();

      widget.onSeasonChanged?.call(nextDetail);
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            detail: nextDetail,
            initialIndex: initialIndex,
            initialPosition: initialPosition,
            repository: widget.repository,
            store: widget.store,
            localOnly: widget.localOnly,
            allowOnlineFallback: widget.allowOnlineFallback,
            playerFactory: widget.playerFactory,
            videoBuilder: widget.videoBuilder,
            initialSeriesEntries: hongguoSeriesEntries(nextDetail.drama, [
              ..._currentSeriesEntries.map((entry) => entry.drama),
              ...widget.store.seriesDramasFor(nextDetail.drama),
            ], lockedEntries: _currentSeriesEntries),
            onSeasonChanged: widget.onSeasonChanged,
          ),
        ),
      );
    } catch (e) {
      if (mounted && ticket == _seasonSwitchTicket) {
        _notice('切换失败: $e');
      }
    }
  }

  void _accessChanged() {
    if (!_closed &&
        (widget.store.profileEpoch != _profileEpoch || widget.store.locked)) {
      _preloader.clear();
      _enhancement.suspend();
      _handoffOwned = false;
      _playIntent = false;
      widget.handoff?.fail('接收端用户已变更');
      unawaited(_player.pause());
    }
    if (!_closed &&
        (widget.store.profileEpoch != _profileEpoch ||
            widget.store.locked ||
            !widget.store.allowsSource('hongguo'))) {
      _danmaku.setPlan(null);
    }
  }

  void _configurePictureInPicture() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _pictureInPictureHandlerInstalled = true;
    AppDevice.channel.setMethodCallHandler((call) async {
      if (call.method == 'pictureInPictureChanged') {
        final arguments = call.arguments;
        final active = arguments is Map && arguments['active'] == true;
        _setPictureInPictureStatus(active: active, delayHiddenPause: !active);
      }
    });
    unawaited(_refreshPictureInPictureStatus());
  }

  Future<void> _refreshPictureInPictureStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'pictureInPictureStatus',
      );
      if (!mounted || _closed) return;
      _setPictureInPictureStatus(
        supported: status?['supported'] == true,
        active: status?['active'] == true,
      );
    } on PlatformException {
      if (mounted && !_closed) {
        _setPictureInPictureStatus(supported: false, active: false);
      }
    } on MissingPluginException {
      if (mounted && !_closed) {
        _setPictureInPictureStatus(supported: false, active: false);
      }
    }
  }

  void _setPictureInPictureStatus({
    bool? supported,
    bool? active,
    bool? requested,
    bool delayHiddenPause = false,
  }) {
    final nextSupported = supported ?? _pictureInPictureSupported;
    final nextActive = active ?? _pictureInPictureActive;
    final nextRequested =
        requested ?? (nextActive ? false : _pictureInPictureRequested);
    void assign() {
      _pictureInPictureSupported = nextSupported;
      _pictureInPictureActive = nextActive;
      _pictureInPictureRequested = nextRequested;
    }

    if (mounted && !_closed) {
      setState(assign);
    } else {
      assign();
    }
    if (_pictureInPictureVisible ||
        _lifecycleState == AppLifecycleState.resumed) {
      _pictureInPictureExitTimer?.cancel();
      _applyLifecycleVisibility(pauseWhenHidden: false);
      return;
    }
    _pictureInPictureExitTimer?.cancel();
    _applyLifecycleVisibility(pauseWhenHidden: !delayHiddenPause);
    if (delayHiddenPause) {
      _pictureInPictureExitTimer = Timer(const Duration(milliseconds: 700), () {
        if (!_closed &&
            !_pictureInPictureVisible &&
            _lifecycleState != AppLifecycleState.resumed) {
          _applyLifecycleVisibility();
        }
      });
    }
  }

  void _applyLifecycleVisibility({bool pauseWhenHidden = true}) {
    if (_closed) return;
    final visible =
        _lifecycleState == AppLifecycleState.resumed ||
        _pictureInPictureVisible;
    _foreground = visible;
    _enhancement.setForeground(_foreground);
    _syncDanmaku();
    _syncPreload();
    _health.reset();
    if (!visible) _interactions.cancel();
    if (pauseWhenHidden &&
        !visible &&
        (_lifecycleState == AppLifecycleState.paused ||
            _lifecycleState == AppLifecycleState.inactive ||
            _lifecycleState == AppLifecycleState.hidden)) {
      if (!_lifecyclePaused) {
        _resumeAfterInterruption = _playIntent;
        _lifecyclePaused = true;
      }
      setState(() => _playIntent = false);
      unawaited(_player.pause());
      unawaited(_saveProgress(flush: true));
    }
    if (visible && _lifecyclePaused) {
      _lifecyclePaused = false;
      final resume = _resumeAfterInterruption;
      _resumeAfterInterruption = false;
      setState(() => _playIntent = resume);
      if (resume && !_loading && _error == null && _openedIndex == _index) {
        unawaited(_player.play());
      }
    }
    if (visible && _pendingError) {
      _queueRecovery();
    }
  }

  Future<void> _enterPictureInPicture() async {
    if (!_canUsePictureInPicture ||
        _closed ||
        _loading ||
        _error != null ||
        _panelOpen) {
      return;
    }
    _interactions.cancel();
    final rawRatio = _aspectRatio.isFinite && _aspectRatio > 0
        ? _aspectRatio
        : 16 / 9;
    final ratio = rawRatio.clamp(1 / 2.39, 2.39).toDouble();
    final width = ratio >= 1 ? (1000 * ratio).round() : 1000;
    final height = ratio >= 1 ? 1000 : (1000 / ratio).round();
    _setPictureInPictureStatus(requested: true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _closed) return;
    final sourceRect = _pictureInPictureSourceRect();
    final arguments = <String, int>{'width': width, 'height': height};
    if (sourceRect != null) arguments.addAll(sourceRect);
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'enterPictureInPicture',
        arguments,
      );
      if (!mounted || _closed) return;
      final supported = status?['supported'] == true;
      final active = status?['active'] == true;
      final requested = status?['requested'] == true;
      _setPictureInPictureStatus(
        supported: supported,
        active: active,
        requested: requested && !active,
      );
      if (!supported || (!active && !requested)) {
        _notice('当前设备不支持画中画');
      } else if (requested && !active) {
        _pictureInPictureExitTimer?.cancel();
        _pictureInPictureExitTimer = Timer(const Duration(seconds: 2), () {
          if (!_closed &&
              _pictureInPictureRequested &&
              !_pictureInPictureActive) {
            _setPictureInPictureStatus(requested: false);
          }
        });
      }
    } on PlatformException {
      _setPictureInPictureStatus(requested: false);
      _notice('无法进入画中画，请检查系统权限');
    } on MissingPluginException {
      _setPictureInPictureStatus(supported: false, requested: false);
      _notice('当前平台不支持画中画');
    }
  }

  Map<String, int>? _pictureInPictureSourceRect() {
    final paneContext = _videoPaneKey.currentContext;
    final renderObject = paneContext?.findRenderObject();
    if (paneContext == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final ratio =
        MediaQuery.maybeOf(paneContext)?.devicePixelRatio ??
        View.of(paneContext).devicePixelRatio;
    final left = (topLeft.dx * ratio).round().clamp(0, 100000);
    final top = (topLeft.dy * ratio).round().clamp(0, 100000);
    final right = ((topLeft.dx + size.width) * ratio).round().clamp(0, 100000);
    final bottom = ((topLeft.dy + size.height) * ratio).round().clamp(
      0,
      100000,
    );
    if (right <= left || bottom <= top) return null;
    return {'left': left, 'top': top, 'right': right, 'bottom': bottom};
  }

  void _attachLanPlayback() {
    LanController.current?.attachPlayback(
      LanPlaybackHost(
        identity: _lanIdentity,
        title:
            '${widget.detail.drama.title} · 第 ${widget.detail.episodes[_index].number} 集',
        stop: _stopForLan,
      ),
    );
  }

  void _acknowledgeHandoff() {
    final handoff = widget.handoff;
    if (!_handoffOwned ||
        handoff == null ||
        handoff.cancelled ||
        handoff.started.isCompleted ||
        _closed ||
        _loading ||
        _error != null ||
        _openedIndex != _index ||
        _index != widget.initialIndex ||
        widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    final state = _player.state;
    final position = state.position.inMilliseconds / 1000;
    final duration = state.duration.inMilliseconds / 1000;
    if (duration > 0 && handoff.position > duration + 2) {
      handoff.fail('续播位置超过接收端分集时长');
      return;
    }
    if (!state.playing ||
        state.buffering ||
        (state.width ?? 0) <= 0 ||
        position < handoff.position - .5 ||
        position > handoff.position + 20) {
      return;
    }
    _lanFirstPosition ??= position;
    if (position >= _lanFirstPosition! + .15) handoff.acknowledge(position);
  }

  Future<void> _stopForLan() async {
    final generation = _generation;
    await _serialize(() async {
      if (_closed ||
          generation != _generation ||
          widget.store.profileEpoch != _profileEpoch) {
        return;
      }
      _playIntent = false;
      _interactions.cancel();
      _enhancement.suspend();
      _health.reset();
      await _player.pause();
      await _saveProgress(flush: true);
    });
  }

  Future<void> _pushToDevice() async {
    final link = LanController.current;
    if (link == null ||
        _panelOpen ||
        _closed ||
        _loading ||
        _error != null ||
        widget.mediaId != null) {
      return;
    }
    final generation = _generation;
    final index = _index;
    bool current() =>
        mounted &&
        !_closed &&
        generation == _generation &&
        index == _index &&
        widget.store.profileEpoch == _profileEpoch;
    _interactions.cancel();
    setState(() => _panelOpen = true);
    try {
      await showLanPush(
        context,
        link,
        snapshot: () => LanPlaybackIntent(
          drama: widget.detail.drama,
          episodeID: widget.detail.episodes[index].id,
          episode: widget.detail.episodes[index].number,
          position: _currentPosition,
        ),
        stillCurrent: current,
        onAccepted: () async {
          if (!current()) throw StateError('本机播放内容已变更');
          await _stopForLan();
          if (!current()) throw StateError('本机播放内容已变更');
        },
      );
    } catch (error) {
      if (mounted && !_closed) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted && !_closed) setState(() => _panelOpen = false);
    }
  }

  void _syncPreload() {
    if (_closed) return;
    if (!_preloadEnabled ||
        !_foreground ||
        widget.localOnly ||
        _plan?.offline == true ||
        _loading ||
        _error != null ||
        _openedIndex != _index ||
        widget.store.profileEpoch != _profileEpoch ||
        widget.store.locked ||
        _index + 1 >= widget.detail.episodes.length) {
      _preloader.clear();
      return;
    }
    final state = _player.state;
    if (!state.playing || state.buffering || !_playIntent) {
      _preloader.pause();
      return;
    }
    final duration = state.duration.inMilliseconds;
    final position = state.position.inMilliseconds;
    if (duration <= 0 || position < 1500) {
      return;
    }
    final remaining = duration - position;
    final progress = position / duration;
    if (remaining > 25000 && progress < 0.35) {
      return;
    }
    _preloader.prepare(
      widget.detail.drama,
      widget.detail.episodes[_index + 1],
      quality: _requestedQuality,
    );
  }

  void _syncDanmaku({bool discontinuity = false}) {
    if (_closed) return;
    final state = _player.state;
    _danmaku.update(
      position: state.position,
      duration: state.duration,
      speed: state.rate,
      playing: state.playing && _playIntent && !state.completed,
      buffering: state.buffering,
      foreground: _foreground,
      available:
          !_loading &&
          _error == null &&
          _openedIndex == _index &&
          widget.store.profileEpoch == _profileEpoch &&
          !widget.store.locked &&
          widget.store.allowsSource('hongguo'),
      discontinuity: discontinuity,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final television = AppLayout.isTelevision(context);
    if (_television != television) {
      _fullscreen = false;
      _automaticFullscreenSuppressed = false;
      _interactions.cancel();
    }
    _television = television;
    _orientationController = AppOrientationScope.maybeOf(context);
    final orientation = MediaQuery.orientationOf(context);
    if (_lastOrientation != null && _lastOrientation != orientation) {
      _automaticFullscreenSuppressed = false;
      _interactions.cancel();
    }
    _lastOrientation = orientation;
    _scheduleSystemUi();
  }

  void _scheduleSystemUi() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed || (!_mobile && !_television)) return;
      final fullscreen = _showFullscreen;
      if (_systemFullscreen == fullscreen) return;
      _systemFullscreen = fullscreen;
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _applyLifecycleVisibility();
  }

  void _queueRecovery({bool force = false}) {
    if (_closed || !_acceptErrors || _error != null) {
      return;
    }
    _pendingError = true;
    _requireRecovery = _requireRecovery || force;
    if (!_foreground || (_errorTimer?.isActive ?? false)) {
      return;
    }
    final ticket = _generation;
    final position = _player.state.position;
    _errorTimer = Timer(const Duration(milliseconds: 900), () {
      if (_closed || ticket != _generation || !_foreground || !_acceptErrors) {
        return;
      }
      _pendingError = false;
      final required = _requireRecovery;
      _requireRecovery = false;
      final state = _player.state;
      if (!required &&
          state.playing &&
          !state.buffering &&
          (state.width ?? 0) > 0 &&
          state.position > position + const Duration(milliseconds: 300)) {
        return;
      }
      unawaited(_recover());
    });
  }

  Future<void> _recover() async {
    final current = _plan;
    if (_closed ||
        !_acceptErrors ||
        !_foreground ||
        current == null ||
        _error != null) {
      return;
    }
    _acceptErrors = false;
    _danmaku.setPlan(null);
    _errorTimer?.cancel();
    _pendingError = false;
    _requireRecovery = false;
    final position = _currentPosition;
    final action = current.offline
        ? PlaybackRecoveryAction.stop
        : _recovery.next(
            current,
            allowCache:
                _player is LunaExoPlayer &&
                (Platform.isAndroid || Platform.isIOS),
          );
    if (action == PlaybackRecoveryAction.stop) {
      _resumePosition = position;
      final ticket = _generation;
      try {
        await _serialize(() async {
          if (_closed || ticket != _generation) {
            return;
          }
          try {
            await _saveProgress();
            _openedIndex = -1;
            await _player.stop();
          } finally {
            await widget.repository.release(current.session);
          }
        });
      } catch (_) {}
      if (mounted && !_closed && ticket == _generation) {
        setState(() {
          _loading = false;
          _localFailure = current.offline;
          _error = current.offline
              ? widget.allowOnlineFallback
                    ? '本地视频读取失败，请重试或重新下载；也可以手动改为在线播放。'
                    : '本地成品读取失败，请重试或重新生成。'
              : '自动恢复未成功，请检查网络后重试，也可换一集或选择其他清晰度。';
        });
      }
      return;
    }
    await _play(
      _index,
      position: position,
      recoveryAction: action,
      recoveryPlan: current,
    );
  }

  void _togglePlayback() {
    if (_closed || _loading || _error != null) return;
    _handoffOwned = false;
    widget.handoff?.fail('接收端已操作播放');
    _interactions.cancel();
    setState(() => _playIntent = !_playIntent);
    if (_playIntent) _enhancement.mediaReady();
    _health.reset();
    if (_playIntent && _player.state.completed) {
      unawaited(_play(_index));
      return;
    }
    unawaited(_playIntent ? _player.play() : _player.pause());
    if (!_playIntent) unawaited(_saveProgress(flush: true));
    _syncDanmaku();
  }

  Future<void> _saveProgress({bool flush = false}) async {
    if (_openedIndex < 0 || widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    final position = _player.state.position.inMilliseconds / 1000;
    final duration = _player.state.duration.inMilliseconds / 1000;
    if (!position.isFinite ||
        !duration.isFinite ||
        position < .1 ||
        duration <= 0) {
      return;
    }
    final store = widget.store;
    final progressKey =
        '${widget.mediaId ?? widget.detail.drama.id}:$_openedIndex:$position:$duration';
    if (_savedProgressKey == progressKey && _saveWarning == null) {
      if (flush && widget.mediaId == null) LanController.current?.flush();
      return;
    }
    final entry = WatchEntry(
      drama: widget.repository.catalogUpdates.current(widget.detail.drama),
      episode: widget.detail.episodes[_openedIndex].number,
      position: position,
      duration: duration,
      updatedAt: DateTime.now(),
    );
    try {
      await Future<void>.value();
      if (store.profileEpoch != _profileEpoch) return;
      if (widget.mediaId == null) {
        await store.saveWatch(entry);
        if (flush) LanController.current?.flush();
      } else {
        await store.saveMediaWatch(widget.mediaId!, entry);
      }
      _savedProgressKey = progressKey;
      if (mounted && !_closed && _saveWarning != null) {
        setState(() => _saveWarning = null);
      }
    } catch (_) {
      if (mounted && !_closed && _saveWarning == null) {
        setState(() => _saveWarning = '观看进度尚未保存，请检查存储空间后重试。');
      }
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operations.catchError((Object _) {}).then((_) => operation());
    _operations = next;
    return next;
  }

  Future<void> _play(
    int index, {
    double position = 0,
    PlaybackRecoveryAction? recoveryAction,
    PlaybackPlan? recoveryPlan,
    bool playWhenReady = true,
    PlaybackPlan? handoffPlan,
    bool showControlsOnReady = true,
  }) async {
    if (_closed ||
        widget.store.profileEpoch != _profileEpoch ||
        index < 0 ||
        index >= widget.detail.episodes.length) {
      return;
    }
    if (recoveryAction != null &&
        recoveryAction != PlaybackRecoveryAction.cache) {
      final previousGeneration = _generation;
      await Future<void>.delayed(_recovery.retryDelay);
      if (_closed || previousGeneration != _generation) return;
    }
    _interactions.cancel();
    if (widget.handoff != null &&
        handoffPlan == null &&
        recoveryAction == null) {
      _handoffOwned = false;
      widget.handoff?.fail('接收端已更换播放内容');
    }
    if (index != _index) _forceOnline = false;
    final forceEncryptedCache =
        recoveryAction != null &&
        (_recovery.cacheAttempted ||
            (_plan?.decryptionKey.isNotEmpty ?? false));
    final warmed =
        handoffPlan ??
        (recoveryAction == null && _preloadEnabled && !widget.localOnly
            ? _preloader.take(
                widget.detail.drama,
                widget.detail.episodes[index],
                quality: _requestedQuality,
                online: _forceOnline,
              )
            : null);
    _preloader.clear();
    final ticket = ++_generation;
    unawaited(_encryptedPlayback.cancel());
    _enhancement.suspend();
    _seekSequence++;
    _danmaku.setPlan(null);
    _acceptErrors = false;
    _pendingError = false;
    _requireRecovery = false;
    _errorTimer?.cancel();
    _health.reset();
    if (recoveryAction == null) {
      _recovery.reset();
      _playIntent = playWhenReady;
      if (_lifecyclePaused) {
        _resumeAfterInterruption = playWhenReady;
        _playIntent = false;
      }
    }
    _resumePosition = position;
    _showControlsOnPlaybackReady = showControlsOnReady;
    setState(() {
      _index = index;
      _loading = warmed == null;
      _error = null;
      _localFailure = false;
      _loadingMessage = switch (recoveryAction) {
        PlaybackRecoveryAction.cache => '正在尝试本集缓存解密',
        PlaybackRecoveryAction.alternative => '正在切换备用线路',
        PlaybackRecoveryAction.refresh =>
          '正在重新获取播放地址（${_recovery.attempts}/${PlaybackRecovery.maxAttempts}）',
        _ => '正在准备播放',
      };
    });
    LanController.current?.detachPlayback(_lanIdentity);
    _lanIdentity = Object();
    _attachLanPlayback();
    PlaybackPlan? prepared;
    PlaybackPlan? retained;
    PlaybackPlan? failedPlan;
    bool installed = false;
    var failureStage = 'resolve';
    try {
      await _serialize(() async {
        if (_closed || ticket != _generation) {
          return;
        }
        await _saveProgress(flush: true);
        await _enhancement.beforeMedia();
        if (_closed || ticket != _generation) return;
        _openedIndex = -1;
        await _player.stop();
        final previous = _plan ?? recoveryPlan;
        _plan = null;
        if (recoveryAction == PlaybackRecoveryAction.alternative ||
            recoveryAction == PlaybackRecoveryAction.cache) {
          retained = previous;
        } else if (previous != null) {
          if (recoveryAction == PlaybackRecoveryAction.refresh) {
            failedPlan = previous;
          }
          await widget.repository.release(previous.session);
        }
      });
      if (_closed || ticket != _generation) {
        return;
      }
      prepared = retained != null
          ? recoveryAction == PlaybackRecoveryAction.cache
                ? await _loader.use(retained!)
                : await _loader.fallback(retained!)
          : failedPlan != null
          ? await _loader.refresh(
              widget.detail.drama,
              widget.detail.episodes[index],
              failedPlan!,
              quality: _requestedQuality,
            )
          : warmed != null
          ? await _loader.use(warmed)
          : await _loader.load(
              widget.detail.drama,
              widget.detail.episodes[index],
              quality: _requestedQuality,
              localOnly: widget.localOnly,
              online: _forceOnline,
            );
      if (prepared == null) {
        return;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        failureStage = 'prepare';
        prepared = await _encryptedPlayback.prepare(
          prepared,
          forceCache: forceEncryptedCache,
          progress: (value) {
            if (mounted && !_closed && ticket == _generation) {
              setState(() {
                _loading = true;
                _loadingMessage = '正在准备视频 ${(value * 100).round()}%';
              });
            }
          },
        );
      }
      final plan = prepared;
      failureStage = 'open';
      await _serialize(() async {
        if (_closed || ticket != _generation) {
          await widget.repository.release(plan.session);
          return;
        }
        if (plan.url.isEmpty) {
          throw AppFailure('站源未返回播放地址，请重试');
        }
        final platform = _player.platform;
        if (platform is NativePlayer) {
          if (Platform.isAndroid) {
            if (_television) {
              await platform.setProperty('hwdec', 'mediacodec');
              await platform.setProperty('hwdec-codecs', 'all');
              await platform.setProperty('opengl-pbo', 'yes');
              await platform.setProperty('video-latency-hacks', 'no');
              await platform.setProperty('scale', 'spline36');
              await platform.setProperty('cscale', 'spline36');
              await platform.setProperty('dscale', 'mitchell');
              await platform.setProperty('correct-downscaling', 'yes');
              await platform.setProperty('sigmoid-upscaling', 'yes');
              await platform.setProperty('vd-lavc-skiploopfilter', 'none');
              await platform.setProperty('vd-lavc-skipidct', 'none');
              await platform.setProperty('vd-lavc-threads', '4');
              await platform.setProperty(
                'demuxer-max-bytes',
                '${32 * 1024 * 1024}',
              );
              await platform.setProperty(
                'demuxer-max-back-bytes',
                '${8 * 1024 * 1024}',
              );
              await platform.setProperty('demuxer-readahead-secs', '15');
            } else {
              await platform.setProperty('hwdec', 'auto-safe');
              await platform.setProperty('hwdec-codecs', 'all');
              await platform.setProperty('scale', 'spline36');
              await platform.setProperty('cscale', 'spline36');
              await platform.setProperty('dscale', 'mitchell');
              await platform.setProperty('correct-downscaling', 'yes');
              await platform.setProperty('sigmoid-upscaling', 'yes');
              await platform.setProperty('vd-lavc-skiploopfilter', 'none');
              await platform.setProperty('vd-lavc-threads', '4');
              await platform.setProperty(
                'demuxer-max-bytes',
                '${32 * 1024 * 1024}',
              );
            }
            await platform.setProperty('vd-lavc-fast', 'no');
            await platform.setProperty('video-sync', 'audio');
            await platform.setProperty('framedrop', 'vo');
          }
          await platform.setProperty(
            'demuxer-lavf-o',
            [
              'seg_max_retry=3',
              'strict=experimental',
              'allowed_extensions=ALL',
              plan.local
                  ? 'protocol_whitelist=[file,crypto,data]'
                  : 'protocol_whitelist=[http,https,tcp,tls,crypto,data,file]',
              if (plan.decryptionKey.isNotEmpty)
                'decryption_key=${plan.decryptionKey}',
            ].join(','),
          );
          await platform.setProperty('network-timeout', '20');
        }
        _plan = plan;
        installed = true;
        _acceptErrors = true;
        DiaryService.add(
          '[Play] 打开媒体: 剧=${widget.detail.drama.cleanSourceId}, 集=${widget.detail.episodes[index].number}, local=${plan.local}, encrypted=${plan.decryptionKey.isNotEmpty}, host=${Uri.tryParse(plan.url)?.host}',
        );
        await _player.open(
          Media(
            plan.url,
            httpHeaders: plan.headers,
            extras: {'decryptionKey': plan.decryptionKey},
            start: position > 0
                ? Duration(milliseconds: (position * 1000).round())
                : null,
          ),
          play: _foreground && _playIntent,
        );
        if (_closed || ticket != _generation) {
          return;
        }
        _openedIndex = index;
        _enhancement.mediaReady();
        _attachLanPlayback();
        _health.reset();
        await _interactions.applySpeed();
        if (mounted && !_closed && ticket == _generation) {
          setState(() {
            _loading = false;
          });
          _danmaku.setPlan(plan);
          _syncDanmaku();
          _acknowledgeHandoff();
          _menuRevision.value++;
        }
      });
    } catch (error) {
      DiaryService.add(
        '[Play] 播放失败: 剧=${widget.detail.drama.cleanSourceId}, 集=${widget.detail.episodes[index].number}, 阶段=$failureStage, 恢复=${_recovery.attempts}/${PlaybackRecovery.maxAttempts}, ${playbackFailureSummary(error)}',
      );
      if (!_closed && mounted && ticket == _generation) {
        if (prepared != null && identical(_plan, prepared)) {
          _acceptErrors = true;
          _queueRecovery();
        } else {
          if (prepared != null) {
            await widget.repository.release(prepared.session);
          }
          if (!widget.localOnly &&
              error is! FormatException &&
              error is! FileSystemException) {
            final failed = prepared ?? failedPlan ?? retained ?? recoveryPlan;
            final action = _recovery.next(failed);
            if (action != PlaybackRecoveryAction.stop) {
              unawaited(
                _play(
                  index,
                  position: position,
                  recoveryAction: action,
                  recoveryPlan: failed,
                  playWhenReady: _playIntent,
                ),
              );
              return;
            }
          }
          if (mounted && !_closed && ticket == _generation) {
            setState(() {
              _loading = false;
              _localFailure =
                  (error is AppFailure && error.code == 'local_media') ||
                  (widget.localOnly && !_forceOnline);
              _error = error is AppFailure
                  ? error.message
                  : error is FileSystemException
                  ? '无法写入视频缓存，请检查剩余空间后重试。'
                  : '无法播放这一集，请重试或换一集。';
              widget.handoff?.fail(_error!);
            });
          }
        }
      } else if (prepared != null && !installed) {
        await widget.repository.release(prepared.session);
      }
    } finally {
      if (warmed != null && !installed) {
        await widget.repository.release(warmed.session);
      }
      if (retained != null &&
          (!installed || _plan?.session != retained!.session)) {
        await widget.repository.release(retained!.session);
      }
    }
  }

  Future<void> _switchOnline() async {
    _forceOnline = true;
    await _retry();
  }

  Future<void> _retry({int? quality}) async {
    final position = _currentPosition;
    if (quality != null) {
      _requestedQuality = quality;
    }
    await _play(
      _index,
      position: position,
      playWhenReady: quality == null || _error != null || _playIntent,
    );
  }

  bool get _showFullscreen =>
      _television ||
      _fullscreen ||
      (_mobile &&
          !_automaticFullscreenSuppressed &&
          _aspectRatio >= 1 &&
          MediaQuery.orientationOf(context) == Orientation.landscape);

  Future<void> _rotate() async {
    if (_rotating || _television) {
      return;
    }
    final fullscreen = !_showFullscreen;
    final previous = _fullscreen;
    final previousSuppressed = _automaticFullscreenSuppressed;
    _interactions.cancel();
    _rotating = true;
    setState(() {
      _fullscreen = fullscreen;
      _automaticFullscreenSuppressed = !fullscreen;
    });
    try {
      if (Platform.isWindows) {
        await windowManager.setFullScreen(fullscreen);
      } else if (_mobile) {
        await (_orientationController?.setPlayback(
              this,
              fullscreen: fullscreen,
              aspectRatio: _aspectRatio,
            ) ??
            SystemChrome.setPreferredOrientations(
              AppOrientationController.orientations(
                television: _television,
                fullscreen: fullscreen,
                aspectRatio: _aspectRatio,
              ),
            ));
      }
    } catch (_) {
      if (mounted && !_closed) {
        setState(() {
          _fullscreen = previous;
          _automaticFullscreenSuppressed = previousSuppressed;
        });
        _notice('无法切换全屏，请重试');
      }
    } finally {
      _rotating = false;
      if (mounted && !_closed) _scheduleSystemUi();
    }
  }

  void _notice(
    String message, {
    Duration duration = const Duration(milliseconds: 800),
  }) {
    if (!mounted || _closed) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _setPreferences(PlaybackPreferences preferences) async {
    if (_closed || widget.store.profileEpoch != _profileEpoch) {
      throw StateError('当前用户已变更');
    }
    _interactions.cancel();
    final nextPreferences = preferences.copyWith(
      autoAdvance: true,
      preload: true,
    );
    await widget.store.setPlaybackPreferences(nextPreferences);
    if (!mounted || _closed || widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    final qualityChanged = nextPreferences.quality != _requestedQuality;
    _enhancement.setPreferences(nextPreferences.enhancement);
    setState(() {
      _speed = nextPreferences.speed;
      _requestedQuality = nextPreferences.quality;
      _autoAdvance = true;
      _danmakuEnabled = nextPreferences.danmaku;
      _preloadEnabled = true;
    });
    _danmaku.setEnabled(_danmakuEnabled);
    _syncDanmaku();
    if (qualityChanged) _preloader.clear();
    _syncPreload();
    _menuRevision.value++;
    await _interactions.applySpeed();
    if (qualityChanged && _plan?.offline != true) {
      await _retry(quality: nextPreferences.quality);
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      await widget.store.toggleFavorite(widget.detail.drama);
      if (mounted && !_closed) setState(() {});
    } catch (_) {
      _notice('追剧记录未能保存，请检查存储空间后重试');
    }
  }

  Future<void> _toggleDanmaku() async {
    if (widget.detail.drama.source != 'hongguo') return;
    try {
      await _setPreferences(_preferences.copyWith(danmaku: !_danmakuEnabled));
    } catch (_) {
      _notice('弹幕偏好未能保存，请重试');
    }
  }

  Future<void> _retryDanmakuFromControls() async {
    try {
      _danmaku.retry();
      _menuRevision.value++;
    } catch (_) {
      _notice('弹幕重试失败，请稍后再试');
    }
  }

  Future<void> _submitDownloadSelection(DownloadSelection selection) async {
    if (!widget.repository.supportsDownloads ||
        !widget.store.canDownload ||
        widget.store.profileEpoch != _profileEpoch ||
        widget.mediaId != null) {
      return;
    }
    final added = await widget.repository.enqueueDownloads(
      widget.detail,
      selection.episodes,
      quality: selection.quality,
    );
    if (!mounted || _closed) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added == 0 ? '所选集数已在下载列表中' : '已加入 $added 集，已有任务自动跳过'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DownloadsScreen(
                  repository: widget.repository,
                  store: widget.store,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPanel(PlayerMenuSection section) async {
    if (_panelOpen || _closed) return;
    _interactions.cancel();
    setState(() => _panelOpen = true);
    try {
      if (_mobile && section == PlayerMenuSection.quality) {
        final chosenQuality = await PlayerDialogHelper.openQualitySheet(
          context: context,
          qualities: (_plan?.qualities != null && _plan!.qualities.isNotEmpty)
              ? _plan!.qualities
              : const [1080, 720, 360],
          selectedQuality: _requestedQuality,
          actualQuality:
              _plan?.quality ??
              (_requestedQuality > 0 ? _requestedQuality : 720),
          isLocal: _plan?.offline == true,
        );
        if (chosenQuality != null && chosenQuality != _requestedQuality) {
          await _setPreferences(_preferences.copyWith(quality: chosenQuality));
          if (mounted) {
            _notice(
              '已切换清晰度为 ${PlayerQualitySheetView.qualityTitle(chosenQuality)}',
            );
          }
        }
      } else if (_mobile && section == PlayerMenuSection.episodes) {
        final chosenIndex = await PlayerDialogHelper.openEpisodesSheet(
          context: context,
          episodes: widget.detail.episodes,
          currentIndex: _index,
          dramaTitle: widget.detail.drama.title,
          seriesEntries: _currentSeriesEntries,
          currentDramaId: widget.detail.drama.id,
          onSeasonSelected: _switchSeason,
        );
        if (mounted &&
            !_closed &&
            chosenIndex != null &&
            chosenIndex != _index) {
          await _play(chosenIndex);
        }
      } else {
        final index = await PlayerDialogHelper.openMenuPanel(
          context: context,
          section: section,
          detail: widget.detail,
          currentIndex: _index,
          preferences: _preferences,
          plan: _plan,
          store: widget.store,
          danmaku: _danmaku,
          preloader: _preloader,
          enhancement: _enhancement,
          enhancementForUi: _enhancementForUi,
          fullscreen: _showFullscreen,
          mobile: _mobile,
          menuRevision: _menuRevision,
          onPreferences: _setPreferences,
        );
        if (mounted && !_closed && index != null && index != _index) {
          await _play(index);
        }
      }
    } finally {
      if (mounted && !_closed) {
        setState(() => _panelOpen = false);
        _playerFocus.requestFocus();
      }
    }
  }

  Future<void> _seekTo(Duration target) async {
    if (_closed || _loading || _error != null) return;
    _handoffOwned = false;
    widget.handoff?.fail('接收端已调整播放位置');
    final ticket = ++_seekSequence;
    final generation = _generation;
    _danmaku.beginSeek();
    _enhancement.ignorePerformance();
    var succeeded = false;
    try {
      await _player.seek(target);
      succeeded = true;
    } catch (_) {
      _notice('跳转失败，请重试');
    } finally {
      if (!_closed && ticket == _seekSequence && generation == _generation) {
        _danmaku.endSeek(succeeded ? target : _player.state.position);
      }
    }
  }

  void _seek(int seconds) {
    final desired = _player.state.position + Duration(seconds: seconds);
    final maxDuration = _player.state.duration;
    final target = desired < Duration.zero
        ? Duration.zero
        : maxDuration > Duration.zero && desired > maxDuration
        ? maxDuration
        : desired;
    unawaited(_seekTo(target));
  }

  Future<void> _televisionEpisodes(BuildContext context) async {
    if (_panelOpen || _closed) return;
    setState(() => _panelOpen = true);
    int? index;
    try {
      index = await PlayerDialogHelper.openTelevisionEpisodes(
        context: context,
        episodes: widget.detail.episodes,
        currentIndex: _index,
      );
    } finally {
      if (mounted && !_closed) setState(() => _panelOpen = false);
    }
    if (index != null && mounted && !_closed && index != _index) {
      await _play(index);
    }
  }

  Future<void> _televisionSettings(BuildContext context) async {
    if (_panelOpen || _closed) return;
    setState(() => _panelOpen = true);
    TelevisionPlaybackSetting? selection;
    try {
      selection = await PlayerDialogHelper.openTelevisionSettings(
        context: context,
        speed: _speed,
        quality: _requestedQuality,
        qualities: _plan?.qualities ?? [],
        favorite: widget.store.isFavorite(widget.detail.drama.id),
        onFavorite: _toggleFavorite,
        autoAdvance: _autoAdvance,
        danmaku: _danmakuEnabled,
        showDanmaku: widget.detail.drama.source == 'hongguo',
        danmakuStatus: _danmaku.status,
        onRetryDanmaku: _danmaku.canRetry ? _danmaku.retry : null,
        preload: _preloadEnabled,
        preloadStatus: _preloader.status,
        enhancement: _enhancement,
        enhancementForUi: _enhancementForUi,
        danmakuController: _danmaku,
        preloader: _preloader,
      );
    } finally {
      if (mounted && !_closed) setState(() => _panelOpen = false);
    }
    if (selection == null || !mounted || _closed) return;
    try {
      await _setPreferences(
        _preferences.copyWith(
          speed: selection.speed,
          quality: selection.quality,
          autoAdvance: true,
          danmaku: selection.danmaku,
          preload: true,
          enhancement: selection.enhancement,
        ),
      );
    } catch (_) {
      _notice('播放偏好未能保存，请重试');
    }
  }

  void _back() {
    if (_showFullscreen && !_television) {
      _rotate();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _closed = true;
    final enhancementClosed = _enhancement.close();
    LanController.current?.detachPlayback(_lanIdentity);
    widget.handoff?.fail('接收端已退出播放');
    widget.store.removeListener(_accessChanged);
    _danmaku.dispose();
    _preloader.dispose();
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _healthTimer?.cancel();
    _errorTimer?.cancel();
    _pictureInPictureExitTimer?.cancel();
    if (_pictureInPictureHandlerInstalled) {
      AppDevice.channel.setMethodCallHandler(null);
    }
    _interactions.dispose();
    _playerFocus.dispose();
    _menuRevision.dispose();
    unawaited(_saveProgress(flush: true));
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    unawaited(widget.repository.release(_session));
    unawaited(_loader.close().catchError((Object _) {}));
    unawaited(_encryptedPlayback.cancel().catchError((Object _) {}));
    unawaited(
      _operations.catchError((Object _) {}).then((_) async {
        await _interactions.pendingRates.catchError((Object _) {});
        await enhancementClosed.catchError((Object _) {});
        await _player.dispose();
        await _encryptedPlayback.close();
      }),
    );
    if (Platform.isWindows) {
      unawaited(windowManager.setFullScreen(false));
    } else if (_mobile || _television && Platform.isAndroid) {
      unawaited(
        (_orientationController?.releasePlayback(this) ??
                SystemChrome.setPreferredOrientations(
                  AppOrientationController.orientations(
                    television: _television,
                  ),
                ))
            .catchError((Object _) {}),
      );
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inherited = Theme.of(context);
    final theme = _television ? televisionTheme(inherited) : inherited;
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final fullscreen = _showFullscreen;
          final overlayBrightness = fullscreen
              ? Brightness.dark
              : Theme.of(context).brightness;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppTheme.systemBars(overlayBrightness),
            child: _buildPlayer(context),
          );
        },
      ),
    );
  }

  Widget _buildPlayer(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.detail.drama.title;
    final fullscreen = _showFullscreen;
    final pictureInPicture = _pictureInPictureVisible;
    return PopScope(
      canPop: _television || !fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && fullscreen && !_television) {
          _rotate();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _back,
          const SingleActivator(LogicalKeyboardKey.goBack): _back,
        },
        child: Focus(
          focusNode: _playerFocus,
          onKeyEvent: (_, event) {
            if (_television ||
                _panelOpen ||
                !_playerFocus.hasPrimaryFocus ||
                !(ModalRoute.of(context)?.isCurrent ?? true)) {
              return KeyEventResult.ignored;
            }
            return _interactions.key(event);
          },
          autofocus: !_television,
          canRequestFocus: !_television,
          skipTraversal: _television,
          child: Scaffold(
            backgroundColor: fullscreen || pictureInPicture
                ? AppColors.black
                : theme.scaffoldBackgroundColor,
            appBar: pictureInPicture || fullscreen || _mobile
                ? null
                : AppBar(
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    actions: [
                      IconButton(
                        tooltip: '旋转与全屏',
                        onPressed: _rotate,
                        icon: const Icon(Icons.screen_rotation_alt_rounded),
                      ),
                    ],
                  ),
            body: pictureInPicture
                ? _videoPane(context)
                : SafeArea(
                    top: !_television && (fullscreen || _mobile),
                    bottom: !fullscreen,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final desktop = constraints.maxWidth >= 840;
                        if (fullscreen) {
                          return _videoPane(context);
                        }
                        if (desktop ||
                            constraints.maxWidth >
                                constraints.maxHeight * 1.3) {
                          return Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(child: _videoPane(context)),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: desktop ? 340 : 220,
                                child: PlayerDesktopPanelView(
                                  episodes: widget.detail.episodes,
                                  currentIndex: _index,
                                  seriesEntries: _currentSeriesEntries,
                                  currentDramaId: widget.detail.drama.id,
                                  onSeasonSelected: _switchSeason,
                                  onSelectEpisode: (index) => _play(index),
                                ),
                              ),
                            ],
                          );
                        }
                        if (_mobile) {
                          final height = (constraints.maxWidth / _aspectRatio)
                              .clamp(0.0, constraints.maxHeight * .56);
                          return Column(
                            children: [
                              SizedBox(
                                height: height,
                                width: double.infinity,
                                child: _videoPane(context),
                              ),
                              Expanded(
                                child: PlayerMobilePanelView(
                                  detail: widget.detail,
                                  currentIndex: _index,
                                  store: widget.store,
                                  repository: widget.repository,
                                  seriesEntries: _currentSeriesEntries,
                                  onSeasonSelected: _switchSeason,
                                  onSelectEpisode: (index) => _play(index),
                                  onSubmitDownload: _submitDownloadSelection,
                                ),
                              ),
                            ],
                          );
                        }
                        final height = (constraints.maxWidth / _aspectRatio)
                            .clamp(0.0, constraints.maxHeight * .64);
                        return Column(
                          children: [
                            SizedBox(
                              height: height,
                              width: double.infinity,
                              child: _videoPane(context),
                            ),
                            Expanded(
                              child: PlayerDesktopPanelView(
                                episodes: widget.detail.episodes,
                                currentIndex: _index,
                                seriesEntries: _currentSeriesEntries,
                                currentDramaId: widget.detail.drama.id,
                                onSeasonSelected: _switchSeason,
                                onSelectEpisode: (index) => _play(index),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _videoPane(BuildContext context) {
    return PlayerViewportView(
      television: _television,
      fullscreen: _showFullscreen,
      pictureInPictureVisible: _pictureInPictureVisible,
      mobile: _mobile,
      detail: widget.detail,
      index: _index,
      plan: _plan,
      loading: _loading,
      loadingMessage: _loadingMessage,
      error: _error,
      localFailure: _localFailure,
      saveWarning: _saveWarning,
      player: _player,
      playbackRequested: _playIntent,
      videoController: _video,
      danmaku: _danmaku,
      danmakuEnabled: _danmakuEnabled,
      aspectRatio: _aspectRatio,
      interactions: _interactions,
      enhancement: _enhancement,
      enhancementForUi: _enhancementForUi,
      speed: _speed,
      qualityLabel: _qualityLabel,
      showControlsOnPlaybackReady: _showControlsOnPlaybackReady,
      panelOpen: _panelOpen,
      canUsePictureInPicture: _canUsePictureInPicture,
      playerFocus: _playerFocus,
      videoPaneKey: _videoPaneKey,
      allowOnlineFallback: widget.allowOnlineFallback,
      localOnly: widget.localOnly,
      isMediaIdNull: widget.mediaId == null,
      repository: widget.repository,
      store: widget.store,
      videoBuilder: widget.videoBuilder,
      onTogglePlayback: _togglePlayback,
      onSeek: _seek,
      onSeekTo: _seekTo,
      onPlay: _play,
      onRotate: _rotate,
      onBack: _back,
      onRetry: _retry,
      onSwitchOnline: _switchOnline,
      onSaveProgress: _saveProgress,
      onOpenPanel: _openPanel,
      onToggleDanmaku: _toggleDanmaku,
      onRetryDanmaku: _retryDanmakuFromControls,
      onPushToDevice: _pushToDevice,
      onEnterPictureInPicture: _enterPictureInPicture,
      onTelevisionEpisodes: _televisionEpisodes,
      onTelevisionSettings: _televisionSettings,
    );
  }
}
