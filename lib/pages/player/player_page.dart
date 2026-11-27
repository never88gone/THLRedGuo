import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/account/hongguo_account_session.dart';
import 'player_pip_coordinator.dart';
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
import 'package:THLRedLook/core/player/pip_manager.dart';
import 'package:THLRedLook/core/danmaku/danmaku_controller.dart';
import 'package:THLRedLook/views/download/download_picker.dart';
import 'package:THLRedLook/pages/downloads/downloads_page.dart';
import 'package:THLRedLook/pages/anchor/anchor_detail_page.dart';
import 'package:THLRedLook/core/account/hongguo_account_social.dart';
import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/models/danmaku/danmaku_models.dart';
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
import 'package:THLRedLook/core/player/background_audio_service.dart';
import 'package:THLRedLook/views/player/player_desktop_panel_view.dart';
import 'package:THLRedLook/views/player/player_viewport_view.dart';
import 'package:THLRedLook/views/player/player_quality_sheet_view.dart';
import 'package:THLRedLook/views/player/player_speed_sheet_view.dart';
import 'package:THLRedLook/views/player/player_danmaku_sheet_view.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/views/comment/comment_sheet_view.dart';
import 'package:THLRedLook/utils/player/player_dialog_helper.dart';
import 'package:THLRedLook/core/player/playback_lease.dart';
import 'package:THLRedLook/views/feed/feed_player_overlay.dart';
import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/core/cast/haw_cast_player_helper.dart';
import 'package:THLRedLook/core/cast/haw_cast_service.dart';
import 'package:THLRedLook/views/player/haw_cast_overlay.dart';
import 'package:THLRedLook/views/player/haw_cast_sheet.dart';

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
    this.feed = false,
    this.playbackQueue,
    this.onOpenDetail,
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
  final bool feed;
  final PlaybackLeaseQueue? playbackQueue;
  final VoidCallback? onOpenDetail;
  @visibleForTesting
  final Player Function()? playerFactory;
  @visibleForTesting
  final Widget Function(Widget controls)? videoBuilder;
  @override
  State<PlayerScreen> createState() => PlayerScreenState();
}

class PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late DramaDetail _detail;
  DramaDetail get currentDetail => _detail;
  late final Player _player;
  PlaybackLease? _playbackLease;
  late final VideoController? _video;
  late final VideoEnhancementController _enhancement;
  late final PlaybackLoader _loader;
  late final PlaybackPreloader _preloader;
  bool _preloadEnabled = true;
  late final DanmakuController _danmaku;
  int _seekSequence = 0;
  bool _danmakuEnabled = true;
  DanmakuStyle _danmakuStyle = const DanmakuStyle();
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
  Timer? _diagnosticsTimer;
  Timer? _volumeSaveTimer;
  Future<void> _operations = Future<void>.value();
  late int _index;
  late final int _profileEpoch;
  int _openedIndex = -1;
  int _generation = 0;
  int _seasonSwitchTicket = 0;
  int _requestedQuality = 0;
  PlaybackDecoderMode _decoderMode = PlaybackDecoderMode.hardware;
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
  bool _encryptedVideoOutputFailed = false;
  late final PlayerPipCoordinator _pipCoordinator;
  bool get _pictureInPictureActive => _pipCoordinator.active;
  bool get _pictureInPictureRequested => _pipCoordinator.requested;
  bool get _pictureInPictureVisible => _pipCoordinator.isVisible;
  bool get _canUsePictureInPicture => !_television && _pipCoordinator.canUse;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  String _loadingMessage = '正在准备播放';
  String? _error;
  String? _saveWarning;
  Timer? _saveWarningTimer;
  bool _saveWarningDismissed = false;
  PlaybackPlan? _plan;
  final GlobalKey _videoCaptureKey = GlobalKey();
  ui.Image? _transitionSnapshot;
  bool _transitionSnapshotVisible = false;
  int _transitionDirection = 1;
  bool _switchingEpisode = false;
  bool _switchingSlowHint = false;
  Timer? _switchingHintTimer;
  Timer? _snapshotFadeTimer;
  double _speed = 1;
  double _aspectRatio = 9 / 16;
  double _resumePosition = 0;
  bool _rotating = false;
  bool _television = false;
  AppOrientationController? _orientationController;
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
    pictureInPicture: widget.store.playbackPreferences.pictureInPicture,
    decoderMode: _decoderMode,
    danmaku: _danmakuEnabled,
    danmakuStyle: _danmakuStyle,
    preload: _preloadEnabled,
    enhancement: _enhancement.preferences,
    volume: _player.state.volume,
    fillStyle: widget.store.playbackPreferences.fillStyle,
    backgroundAudio: widget.store.playbackPreferences.backgroundAudio,
    episodeTransition: widget.store.playbackPreferences.episodeTransition,
  );
  String get _qualityLabel {
    if (_plan?.offline == true) return '本地原画';
    final q = _plan?.quality ?? 0;
    if (q > 0) return '${q}P';
    return _requestedQuality > 0 ? '${_requestedQuality}P' : '自动';
  }

  String get _session => _plan?.session ?? '';
  bool get _castingActive => HawCastService.instance.isCasting;
  double get _currentPosition {
    if (_castingActive &&
        HawCastService.instance.activeEpisodeIndex == _index &&
        HawCastService.instance.status.position > 0) {
      return HawCastService.instance.status.position;
    }
    return _openedIndex == _index && _player.state.position.inMilliseconds > 0
        ? _player.state.position.inMilliseconds / 1000
        : _resumePosition;
  }

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
    if (HongguoAccountSocial.shared.active) {
      unawaited(
        HongguoAccountSocial.shared
            .load(_detail.drama)
            .catchError((Object _) {}),
      );
    }
    _playbackLease = widget.playbackQueue?.acquire();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialIndex;
    _profileEpoch = widget.handoff?.profileEpoch ?? widget.store.profileEpoch;
    final preferences = widget.store.playbackPreferences;
    _speed = preferences.speed;
    _requestedQuality = preferences.quality;
    _decoderMode = preferences.decoderMode;
    _autoAdvance = preferences.autoAdvance;
    _danmakuEnabled = preferences.danmaku;
    _danmakuStyle = preferences.danmakuStyle;
    _preloadEnabled = preferences.preload;
    _loader = PlaybackLoader(widget.repository);
    _preloader = PlaybackPreloader(widget.repository);
    _danmaku = DanmakuController(widget.repository)
      ..setEnabled(_danmakuEnabled);
    widget.store.addListener(_accessChanged);
    final castService = HawCastService.instance;
    castService.addListener(_onCastServiceChanged);
    castService.onExternalCastActivated = _handleExternalCastActivated;
    castService.onExternalCastStopped = _handleExternalCastStopped;
    castService.onExternalCastEnded = _handleExternalCastEnded;
    _player =
        widget.playerFactory?.call() ??
        ((Platform.isAndroid || Platform.isIOS)
            ? LunaExoPlayer()
            : Player(
                configuration: PlayerConfiguration(
                  bufferSize: 32 * 1024 * 1024,
                  logLevel: Platform.isWindows
                      ? MPVLogLevel.v
                      : MPVLogLevel.error,
                ),
              ));
    if (_player is LunaExoPlayer) {
      _player.setDecoderMode(preferences.decoderMode);
    } else if (_player.platform is NativePlayer) {
      unawaited(
        (_player.platform as NativePlayer)
            .setProperty('keep-open', 'yes')
            .catchError((Object _) {}),
      );
    }
    unawaited(_player.setVolume(preferences.volume));
    _video = widget.videoBuilder == null && _player is! LunaExoPlayer
        ? VideoController(
            _player,
            configuration: VideoControllerConfiguration(
              enableHardwareAcceleration:
                  !Platform.isIOS &&
                  preferences.decoderMode == PlaybackDecoderMode.hardware,
              hwdec: preferences.decoderMode == PlaybackDecoderMode.hardware
                  ? (Platform.isWindows ? 'auto-copy-safe' : 'auto-safe')
                  : 'no',
            ),
          )
        : null;
    _enhancement = VideoEnhancementController(
      player: _player,
      video: _video,
      preferences: preferences.enhancement,
      category: _detail.drama.category,
      tags: _detail.drama.tags,
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
      onVolumeChanged: _onVolumeChanged,
      onTogglePlayback: _togglePlayback,
      onSeek: _seekTo,
      onFullscreen: _rotate,
      onEpisode: (direction) {
        final next = _index + direction;
        if (next < 0) return '已经是第一集';
        if (next >= _detail.episodes.length) return '已经是最后一集';
        unawaited(_play(next));
        return '第 ${_detail.episodes[next].number} 集';
      },
    );
    _playerFocus.addListener(() {
      if (!_playerFocus.hasPrimaryFocus && !_closed) _interactions.cancel();
    });
    _pipCoordinator = PlayerPipCoordinator(
      getContext: () => context,
      isMounted: () => mounted,
      isClosed: () => _closed,
      getDetail: () => _detail,
      getCurrentIndex: () => _index,
      setCurrentIndex: (idx) {
        _index = idx;
        _openedIndex = idx;
        _menuRevision.value++;
        unawaited(_saveProgress(flush: true));
      },
      getPlan: () => _plan,
      getPlayer: () => _player,
      getRequestedQuality: () => _requestedQuality,
      getSpeed: () => _speed,
      getAspectRatio: () => _aspectRatio,
      getVideoPaneKey: () => _videoPaneKey,
      isFeed: widget.feed,
      isLocalOnly: widget.localOnly,
      getPlayIntent: () => _playIntent,
      getIsLoading: () => _loading,
      getError: () => _error,
      getOpenedIndex: () => _openedIndex,
      getLifecycleState: () => _lifecycleState,
      getStore: () => widget.store,
      getEncryptedPlayback: () => _encryptedPlayback,
      onStatusChanged: () {
        if (mounted && !_closed) setState(() {});
      },
      onEpisodeAdvanced: (nextIndex) {},
      onPlay: (idx, {position = 0.0}) => _play(idx, position: position),
      onSeekTo: (target) => _seekTo(target),
      onDismissOverlays: _dismissOverlaysForPictureInPicture,
      onNotice: (msg) => _notice(msg),
      onApplyLifecycleVisibility: ({pauseWhenHidden = true}) =>
          _applyLifecycleVisibility(pauseWhenHidden: pauseWhenHidden),
    );
    _configurePictureInPicture();
    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (_enhancement.handlePlaybackError(error)) return;
        if (!_closed && _acceptErrors && mounted && error.trim().isNotEmpty) {
          if (!_pendingError) {
            DiaryService.add(
              '[Play] 原生播放错误: 剧=${_detail.drama.cleanSourceId}, 集=${_detail.episodes[_index].number}, ${playbackFailureSummary(AppFailure(error, code: 'native_stream'))}',
            );
          }
          final videoOutputFailed = PlaybackRecovery.videoOutputFailed(error);
          if (Platform.isAndroid && videoOutputFailed) {
            _encryptedVideoOutputFailed = true;
            if (_player is LunaExoPlayer) {
              _player.setDecoderMode(PlaybackDecoderMode.compatible);
            }
          }
          _queueRecovery(
            force:
                videoOutputFailed || PlaybackRecovery.audioOutputFailed(error),
          );
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
          final currentPosition = _player.state.position > Duration.zero
              ? _player.state.position
              : Duration(milliseconds: (_resumePosition * 1000).round());
          if (duration <= Duration.zero ||
              currentPosition < duration - const Duration(seconds: 2)) {
            _queueRecovery();
          } else if (_autoAdvance &&
              (_foreground || BackgroundAudioService.instance.isRunning) &&
              !_panelOpen &&
              _index + 1 < _detail.episodes.length) {
            _play(_index + 1, showControlsOnReady: false);
          } else if (_autoAdvance &&
              (_foreground || BackgroundAudioService.instance.isRunning) &&
              !_panelOpen &&
              _index + 1 >= _detail.episodes.length &&
              _nextPlayableSeason != null) {
            final nextSeason = _nextPlayableSeason!;
            _notice('本季已完结，正在自动播放下一季：${nextSeason.drama.title}');
            unawaited(_switchSeason(nextSeason.drama));
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
          _syncNativePictureInPictureConfig();
          if (BackgroundAudioService.instance.isRunning) {
            unawaited(
              BackgroundAudioService.instance.update(
                title: _detail.drama.title,
                episode: '第 ${_detail.episodes[_index].number} 集',
                isPlaying: true,
              ),
            );
          }
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
    BackgroundAudioService.instance.registerCallbacks(
      onTogglePlayback: _togglePlayback,
      onPrevious: () {
        if (_index > 0) unawaited(_play(_index - 1));
      },
      onNext: () {
        if (_index + 1 < _detail.episodes.length) {
          unawaited(_play(_index + 1));
        }
      },
    );
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
          widget.repository.catalogUpdates.current(_detail.drama),
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
      _detail.drama,
      widget.store.seriesDramasFor(_detail.drama),
    );
  }

  HongguoSeriesEntry? get _nextPlayableSeason {
    final entries = _currentSeriesEntries;
    if (entries.isEmpty) return null;
    final currentIndex = entries.indexWhere((e) => e.drama.id == _detail.drama.id);
    if (currentIndex < 0 || currentIndex + 1 >= entries.length) return null;
    for (var i = currentIndex + 1; i < entries.length; i++) {
      if (entries[i].playable && entries[i].drama.id != _detail.drama.id) {
        return entries[i];
      }
    }
    return null;
  }

  Future<void> _discoverSeasons() async {
    try {
      final entries = await discoverSeriesSeasons(
        anchor: _detail.drama,
        repository: widget.repository,
        store: widget.store,
        existingEntries: _seriesEntries,
      );
      if (mounted && !_closed && entries.isNotEmpty) {
        setState(() {
          _seriesEntries = entries;
        });
      }
    } catch (e) {
      DiaryService.warn('Series', '多季信息发现失败', e);
    }
  }

  Future<void> _switchSeason(Drama seasonDrama) async {
    if (_closed || !mounted) return;
    if (seasonDrama.id == _detail.drama.id) return;
    if (_currentSeriesEntries.any(
      (entry) => entry.drama.id == seasonDrama.id && !entry.playable,
    )) {
      return;
    }

    final ticket = ++_seasonSwitchTicket;

    final anchor = _detail.drama;
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
      if (widget.feed) return;

      // 1. 保存当前季度的观看进度
      await _saveProgress(flush: true);

      // 2. 清理旧播放状态与弹幕
      _preloader.clear();
      _danmaku.setPlan(null);
      _recovery.reset();
      _encryptedVideoOutputFailed = false;
      _forceOnline = false;
      _localFailure = false;

      if (!mounted || _closed || ticket != _seasonSwitchTicket) return;

      // 3. 原地更新季状态、选集索引与系列季入口列表
      setState(() {
        _detail = nextDetail;
        _index = initialIndex;
        _resumePosition = initialPosition;
        _openedIndex = -1;
        _seriesEntries = hongguoSeriesEntries(nextDetail.drama, [
          ..._currentSeriesEntries.map((entry) => entry.drama),
          ...widget.store.seriesDramasFor(nextDetail.drama),
        ], lockedEntries: _currentSeriesEntries);
      });

      // 4. 加载新一季的社交数据与关联季信息
      if (HongguoAccountSocial.shared.active) {
        unawaited(
          HongguoAccountSocial.shared
              .load(_detail.drama)
              .catchError((Object _) {}),
        );
      }
      widget.repository.catalogUpdates.publish(
        widget.repository.catalogUpdates.current(_detail.drama),
        retryCover: true,
      );
      unawaited(_discoverSeasons());

      // 5. 立即就地开始播放新一季的目标集
      await _play(
        initialIndex,
        position: initialPosition,
      );

      // 6. 刷新画中画会话
      _syncPictureInPictureSession();
      _syncNativePictureInPictureConfig();
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
    if (!_closed && mounted) {
      setState(() {});
    }
    _syncNativePictureInPictureConfig();
  }

  void _syncPictureInPictureSession() => _pipCoordinator.syncSession();

  void _configurePictureInPicture() => _pipCoordinator.configure();

  void _dismissOverlaysForPictureInPicture() {
    _interactions.cancel();
    if (!mounted || _closed) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.removeCurrentSnackBar();
    final route = ModalRoute.of(context);
    if (route != null && route.isActive && !route.isCurrent) {
      Navigator.of(context).popUntil((item) => item == route);
    }
    if (_panelOpen) {
      setState(() => _panelOpen = false);
    }
  }

  void _syncNativePictureInPictureConfig({bool force = false}) =>
      _pipCoordinator.syncNativeConfig(force: force);

  void _applyLifecycleVisibility({bool pauseWhenHidden = true}) {
    if (_closed) return;
    final visible =
        _lifecycleState == AppLifecycleState.resumed ||
        _lifecycleState == AppLifecycleState.inactive ||
        _pictureInPictureVisible;
    _foreground = visible;
    _enhancement.setForeground(_foreground);
    _syncDanmaku();
    _syncPreload();
    _health.reset();
    if (!visible) _interactions.cancel();
    final bgAudio = widget.store.playbackPreferences.backgroundAudio;
    final autoPip = _pipCoordinator.shouldAutoEnter;

    if (!visible &&
        (_lifecycleState == AppLifecycleState.paused ||
            _lifecycleState == AppLifecycleState.hidden)) {
      if (bgAudio && _playIntent && !_closed) {
        unawaited(
          BackgroundAudioService.instance.start(
            title: _detail.drama.title,
            episode: '第 ${_detail.episodes[_index].number} 集',
            isPlaying: _player.state.playing,
          ),
        );
      } else if (autoPip) {
        Future.delayed(const Duration(milliseconds: 650), () {
          if (!mounted || _closed) return;
          if (!_pictureInPictureVisible &&
              (_lifecycleState == AppLifecycleState.paused ||
                  _lifecycleState == AppLifecycleState.hidden)) {
            if (!_lifecyclePaused) {
              _resumeAfterInterruption = _playIntent;
              _lifecyclePaused = true;
            }
            setState(() => _playIntent = false);
            unawaited(_player.pause());
            unawaited(_saveProgress(flush: true));
          }
        });
      } else if (pauseWhenHidden) {
        if (!_lifecyclePaused) {
          _resumeAfterInterruption = _playIntent;
          _lifecyclePaused = true;
        }
        setState(() => _playIntent = false);
        unawaited(_player.pause());
        unawaited(_saveProgress(flush: true));
      }
    }
    if (visible) {
      unawaited(BackgroundAudioService.instance.stop());
      if (_lifecyclePaused) {
        _lifecyclePaused = false;
        final resume = _resumeAfterInterruption;
        _resumeAfterInterruption = false;
        setState(() => _playIntent = resume);
        if (resume && !_loading && _error == null && _openedIndex == _index) {
          unawaited(_player.play());
        }
      }
    }
    if (visible && _pendingError) {
      _queueRecovery();
    }
  }

  Future<void> _toggleBackgroundAudio() async {
    final prefs = widget.store.playbackPreferences;
    final next = !prefs.backgroundAudio;
    await saveUserChange(
      context,
      () => widget.store.setPlaybackPreferences(prefs.copyWith(backgroundAudio: next)),
    );
    if (mounted) setState(() {});
    _interactions.hint(next ? '已开启后台听剧模式' : '已关闭后台听剧模式');
    if (!next) {
      unawaited(BackgroundAudioService.instance.stop());
    } else if (!_foreground && _player.state.playing) {
      unawaited(
        BackgroundAudioService.instance.start(
          title: _detail.drama.title,
          episode: '第 ${_detail.episodes[_index].number} 集',
          isPlaying: true,
        ),
      );
    }
  }

  Future<void> _enterPictureInPicture() =>
      _pipCoordinator.enterPictureInPicture();

  Future<void> _restoreFromPictureInPicture() =>
      _pipCoordinator.restoreFromPictureInPicture();

  Future<void> _togglePictureInPicture() async {
    if (_television || !_canUsePictureInPicture) return;
    if (_pictureInPictureVisible) {
      await _restoreFromPictureInPicture();
    } else {
      await _enterPictureInPicture();
    }
  }

  void _attachLanPlayback() {
    LanController.current?.attachPlayback(
      LanPlaybackHost(
        identity: _lanIdentity,
        title:
            '${_detail.drama.title} · 第 ${_detail.episodes[_index].number} 集',
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
          drama: _detail.drama,
          episodeID: _detail.episodes[index].id,
          episode: _detail.episodes[index].number,
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

  void _onCastServiceChanged() {
    if (mounted && !_closed) {
      setState(() {});
    }
  }

  void _handleExternalCastActivated() {
    if (!mounted || _closed) return;
    _playIntent = false;
    unawaited(_player.pause());
    unawaited(_saveProgress(flush: true));
    setState(() {});
  }

  void _handleExternalCastStopped(double resumePos) {
    if (!mounted || _closed) return;
    setState(() => _playIntent = true);
    unawaited(_play(_index, position: resumePos));
  }

  void _handleExternalCastEnded(int episodeIndex) {
    if (!mounted || _closed) return;
    if (_autoAdvance &&
        episodeIndex == _index &&
        _index + 1 < _detail.episodes.length) {
      unawaited(_play(_index + 1));
    }
  }

  Future<void> _openCast() async {
    if (_panelOpen || _closed || _loading || widget.feed) return;
    _interactions.cancel();
    setState(() => _panelOpen = true);
    try {
      await showHawCastSheet(
        context,
        onCastToDevice: (device) async {
          final index = _index;
          final castPlan = await HawCastPlayerHelper.resolveCastablePlan(
            drama: _detail.drama,
            episode: _detail.episodes[index],
            currentPlan: _plan,
            encryptedPlayback: _encryptedPlayback,
            repository: widget.repository,
            requestedQuality: _requestedQuality,
          );
          if (castPlan == null) return false;
          final req = HawCastPlayerHelper.buildPlayRequest(
            detail: _detail,
            episodeIndex: index,
            plan: castPlan,
            startPosition: _currentPosition,
          );
          final ok = await HawCastService.instance.startCasting(device, req);
          if (ok && mounted && !_closed) {
            _plan ??= castPlan;
            _playIntent = false;
            await _player.pause();
            await _saveProgress(flush: true);
            if (mounted) setState(() {});
          }
          return ok;
        },
        onStartAirPlay: HawCastService.instance.isAirPlaySupported
            ? () async {
                final index = _index;
                final plan = await HawCastPlayerHelper.resolveAirPlayPlan(
                  drama: _detail.drama,
                  episode: _detail.episodes[index],
                  currentPlan: _plan,
                  encryptedPlayback: _encryptedPlayback,
                  repository: widget.repository,
                  requestedQuality: _requestedQuality,
                );
                if (plan == null) return false;
                _plan ??= plan;
                return HawCastService.instance.startAirPlayCast(
                  plan: plan,
                  title: '第 ${_detail.episodes[index].number} 集',
                  dramaTitle: _detail.drama.title,
                  episodeIndex: index,
                  startPosition: _currentPosition,
                  rate: _speed,
                );
              }
            : null,
        onDisconnect: () {
          unawaited(_stopCast());
        },
      );
    } finally {
      if (mounted && !_closed) setState(() => _panelOpen = false);
    }
  }

  Future<void> _stopCast() async {
    final resumePos = HawCastService.instance.status.position;
    await HawCastService.instance.stopCasting();
    if (!mounted || _closed) return;
    setState(() {
      _playIntent = true;
    });
    await _play(_index, position: resumePos);
  }

  DateTime _lastPreloadCheck = DateTime.fromMillisecondsSinceEpoch(0);

  void _syncPreload() {
    if (_closed) return;
    final now = DateTime.now();
    if (now.difference(_lastPreloadCheck).inMilliseconds < 800) return;
    _lastPreloadCheck = now;
    if (!_preloadEnabled ||
        !_foreground ||
        widget.localOnly ||
        _plan?.offline == true ||
        _loading ||
        _error != null ||
        _openedIndex != _index ||
        widget.store.profileEpoch != _profileEpoch ||
        widget.store.locked ||
        _index + 1 >= _detail.episodes.length) {
      _preloader.clear();
      return;
    }
    final state = _player.state;
    if (!state.playing || state.buffering || !_playIntent) {
      _preloader.pause();
      return;
    }
    if (!PlaybackPreloader.shouldPrepare(
      duration: state.duration,
      position: state.position,
      rate: _speed,
    )) {
      _preloader.pause();
      return;
    }
    _preloader.prepare(
      _detail.drama,
      _detail.episodes[_index + 1],
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
    if (widget.feed) return;
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
            decryptedStream: _encryptedPlayback.isStreamPlan(current),
            allowCache:
                !_encryptedVideoOutputFailed &&
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
      } catch (e) {
        DiaryService.warn('Recover', '恢复过程释放资源异常', e);
      }
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

  void _onVolumeChanged(double volume) {
    _volumeSaveTimer?.cancel();
    _volumeSaveTimer = Timer(const Duration(milliseconds: 350), () {
      if (_closed || !mounted) return;
      final current = widget.store.playbackPreferences;
      if ((current.volume - volume).abs() > 0.5) {
        unawaited(
          widget.store.setPlaybackPreferences(current.copyWith(volume: volume)),
        );
      }
    });
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
    _syncNativePictureInPictureConfig();
  }

  final int _watchAccountRevision = HongguoAccountSession.shared.revision;

  Future<void> _saveProgress({bool flush = false}) async {
    if (_openedIndex < 0 ||
        widget.store.profileEpoch != _profileEpoch ||
        _watchAccountRevision != HongguoAccountSession.shared.revision) {
      return;
    }
    final position = _player.state.position.inMilliseconds / 1000;
    final duration = _player.state.duration.inMilliseconds / 1000;
    final canSaveZero =
        flush &&
        (_savedProgressKey?.startsWith(
              '${widget.mediaId ?? _detail.drama.id}:$_openedIndex:',
            ) ??
            false);
    if (!position.isFinite ||
        !duration.isFinite ||
        (position < .1 && !canSaveZero) ||
        duration <= 0) {
      return;
    }
    final store = widget.store;
    final progressKey =
        '${widget.mediaId ?? _detail.drama.id}:$_openedIndex:$position:$duration';
    if (_savedProgressKey == progressKey &&
        _saveWarning == null &&
        (!flush || !store.usesAccountLibrary(_detail.drama.id))) {
      if (flush && widget.mediaId == null) LanController.current?.flush();
      return;
    }
    final entry = WatchEntry(
      drama: widget.repository.catalogUpdates.current(_detail.drama),
      episode: _detail.episodes[_openedIndex].number,
      position: position,
      duration: duration,
      updatedAt: DateTime.now(),
    );
    final itemId =
        ((_plan?.danmakuId.isNotEmpty ?? false)
                ? _plan!.danmakuId
                : _detail.episodes[_openedIndex].id)
            .split(':')
            .last;
    try {
      await Future<void>.value();
      if (store.profileEpoch != _profileEpoch) return;
      if (widget.mediaId == null) {
        await store.saveWatch(entry, itemId: itemId, force: flush);
        if (flush) LanController.current?.flush();
      } else {
        await store.saveMediaWatch(widget.mediaId!, entry);
      }
      _savedProgressKey = progressKey;
      if (mounted && !_closed && _saveWarning != null) {
        _saveWarningTimer?.cancel();
        setState(() => _saveWarning = null);
      }
    } catch (error) {
      if (mounted && !_closed) {
        if (!flush) return;
        if (!_saveWarningDismissed) {
          _saveWarningTimer?.cancel();
          setState(
            () => _saveWarning = error is HongguoAccountFailure
                ? '账号观看进度尚未同步，请检查网络后重试。'
                : '观看进度尚未保存，请检查存储空间后重试。',
          );
          _saveWarningTimer = Timer(const Duration(seconds: 4), () {
            if (mounted && !_closed && _saveWarning != null) {
              setState(() => _saveWarning = null);
            }
          });
        }
      }
    }
  }

  void _dismissSaveWarning() {
    _saveWarningTimer?.cancel();
    if (mounted && !_closed) {
      setState(() {
        _saveWarning = null;
        _saveWarningDismissed = true;
      });
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operations.catchError((Object _) {}).then((_) => operation());
    _operations = next;
    return next;
  }

  Future<void> _captureTransitionSnapshot(int nextIndex) async {
    if (_closed || !mounted || widget.videoBuilder != null || _openedIndex < 0) {
      return;
    }
    try {
      final boundary =
          _videoCaptureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return;
      final dpr = (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0).clamp(
        1.0,
        2.0,
      );
      final image = await boundary
          .toImage(pixelRatio: dpr)
          .timeout(const Duration(milliseconds: 120));
      if (_closed || !mounted) {
        image.dispose();
        return;
      }
      _snapshotFadeTimer?.cancel();
      final previous = _transitionSnapshot;
      setState(() {
        _transitionSnapshot = image;
        _transitionSnapshotVisible = true;
        _transitionDirection = nextIndex >= _index ? 1 : -1;
      });
      previous?.dispose();
    } catch (_) {}
  }

  void _dismissTransitionSnapshot({bool immediate = false}) {
    _switchingHintTimer?.cancel();
    _snapshotFadeTimer?.cancel();
    final current = _transitionSnapshot;
    if (current == null) {
      if (_transitionSnapshotVisible || _switchingSlowHint) {
        setState(() {
          _transitionSnapshotVisible = false;
          _switchingSlowHint = false;
        });
      }
      return;
    }
    if (immediate || !mounted || _closed) {
      _transitionSnapshot = null;
      _transitionSnapshotVisible = false;
      _switchingSlowHint = false;
      current.dispose();
      if (mounted && !_closed) setState(() {});
      return;
    }
    setState(() {
      _transitionSnapshotVisible = false;
      _switchingSlowHint = false;
    });
    _snapshotFadeTimer = Timer(const Duration(milliseconds: 260), () {
      if (_transitionSnapshot == current) {
        if (mounted && !_closed) {
          setState(() => _transitionSnapshot = null);
        } else {
          _transitionSnapshot = null;
        }
        current.dispose();
      }
    });
  }

  void _finishEpisodeSwitchLoading() {
    _switchingHintTimer?.cancel();
    if (!mounted || _closed) return;
    setState(() {
      _loading = false;
      _switchingEpisode = false;
      _switchingSlowHint = false;
    });
    _dismissTransitionSnapshot();
  }

  Future<void> _waitForNextFrameReady(int ticket) async {
    if (_closed || !mounted || ticket != _generation || widget.videoBuilder != null) {
      return;
    }
    if (_video != null) {
      try {
        await _video.waitUntilFirstFrameRendered.timeout(
          const Duration(milliseconds: 450),
        );
      } catch (_) {}
      if (!_closed &&
          mounted &&
          ticket == _generation &&
          _playIntent &&
          (_player.state.buffering || (_player.state.width ?? 0) <= 0)) {
        final ready = Completer<void>();
        late final StreamSubscription<bool> bufSub;
        late final StreamSubscription<VideoParams> paramSub;
        void check() {
          if (ready.isCompleted) return;
          if (!_player.state.buffering && (_player.state.width ?? 0) > 0) {
            ready.complete();
          }
        }
        bufSub = _player.stream.buffering.listen((_) => check());
        paramSub = _player.stream.videoParams.listen((_) => check());
        check();
        await ready.future.timeout(
          const Duration(milliseconds: 450),
          onTimeout: () {},
        );
        await bufSub.cancel();
        await paramSub.cancel();
      }
    } else if (_player is LunaExoPlayer) {
      try {
        await _player.waitForVideoFrame().timeout(
          const Duration(milliseconds: 450),
        );
      } catch (_) {}
    }
    if (!_closed && mounted && ticket == _generation) {
      final frame = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!frame.isCompleted) frame.complete();
      });
      WidgetsBinding.instance.scheduleFrame();
      await frame.future.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () {},
      );
    }
  }

  Future<void> _play(
    int index, {
    double position = 0,
    PlaybackRecoveryAction? recoveryAction,
    PlaybackPlan? recoveryPlan,
    bool playWhenReady = true,
    PlaybackPlan? handoffPlan,
    bool? showControlsOnReady,
  }) async {
    await _playbackLease?.ready;
    if (_closed ||
        widget.store.profileEpoch != _profileEpoch ||
        index < 0 ||
        index >= _detail.episodes.length) {
      return;
    }
    if (recoveryAction != null &&
        recoveryAction != PlaybackRecoveryAction.cache) {
      final previousGeneration = _generation;
      await Future<void>.delayed(_recovery.retryDelay);
      if (_closed || previousGeneration != _generation) return;
    }
    _interactions.cancel();
    _saveWarningTimer?.cancel();
    _saveWarning = null;
    _saveWarningDismissed = false;
    if (widget.handoff != null &&
        handoffPlan == null &&
        recoveryAction == null) {
      _handoffOwned = false;
      widget.handoff?.fail('接收端已更换播放内容');
    }
    if (index != _index) _forceOnline = false;
    final forceEncryptedCache =
        !_encryptedVideoOutputFailed &&
        (recoveryAction != null &&
            (_recovery.cacheAttempted ||
                (_plan?.decryptionKey.isNotEmpty ?? false)));
    final warmed =
        handoffPlan ??
        (recoveryAction == null && _preloadEnabled && !widget.localOnly
            ? _preloader.take(
                _detail.drama,
                _detail.episodes[index],
                quality: _requestedQuality,
                online: _forceOnline,
              )
            : null);
    _preloader.clear();
    final isEpisodeSwitch =
        recoveryAction == null && (_openedIndex >= 0 || _plan != null);
    final previousOpenedIndex = _openedIndex;
    final ticket = ++_generation;
    if (isEpisodeSwitch && previousOpenedIndex >= 0) {
      await _captureTransitionSnapshot(index);
      if (_closed || widget.store.profileEpoch != _profileEpoch || ticket != _generation) {
        return;
      }
    }
    _enhancement.suspend();
    _seekSequence++;
    _danmaku.setPlan(null);
    _acceptErrors = false;
    _pendingError = false;
    _requireRecovery = false;
    _errorTimer?.cancel();
    _switchingHintTimer?.cancel();
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
    final effectiveShowControls = showControlsOnReady ??
        (!_preferences.quietEpisodeAdvance ||
            (!_television && !_showFullscreen));
    _showControlsOnPlaybackReady = effectiveShowControls;
    final isSeamlessAdvance =
        !effectiveShowControls &&
        recoveryAction == null &&
        (index == _index + 1 || warmed != null);
    if (!isEpisodeSwitch) {
      _dismissTransitionSnapshot(immediate: true);
    }
    setState(() {
      _index = index;
      _loading = !isEpisodeSwitch && !isSeamlessAdvance && warmed == null;
      _switchingEpisode = isEpisodeSwitch;
      _switchingSlowHint = false;
      _error = null;
      _localFailure = false;
      _loadingMessage = switch (recoveryAction) {
        PlaybackRecoveryAction.cache => '正在尝试本集缓存解密',
        PlaybackRecoveryAction.alternative => '正在切换备用线路',
        PlaybackRecoveryAction.refresh =>
          '正在重新获取播放地址（${_recovery.attempts}/${_recovery.attemptLimit}）',
        _ => '正在准备播放',
      };
    });
    if (isEpisodeSwitch) {
      _switchingHintTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted &&
            !_closed &&
            ticket == _generation &&
            _switchingEpisode) {
          setState(() => _switchingSlowHint = true);
        }
      });
    }
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
        if (isEpisodeSwitch) {
          await _player.pause();
        } else if (!isSeamlessAdvance || _player is LunaExoPlayer) {
          await _player.stop();
        }
        await _encryptedPlayback.cancel();
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
              _detail.drama,
              _detail.episodes[index],
              failedPlan!,
              quality: _requestedQuality,
            )
          : warmed != null
          ? await _loader.use(warmed)
          : await _loader.load(
              _detail.drama,
              _detail.episodes[index],
              quality: _requestedQuality,
              localOnly: widget.localOnly,
              online: _forceOnline,
            );
      if (prepared == null) {
        return;
      }
      if (_castingActive &&
          HawCastService.instance.mode == CastProtocolMode.airplay) {
        final airPlayPlan = await HawCastPlayerHelper.resolveAirPlayPlan(
          drama: _detail.drama,
          episode: _detail.episodes[index],
          currentPlan: prepared,
          encryptedPlayback: _encryptedPlayback,
          repository: widget.repository,
          requestedQuality: _requestedQuality,
        );
        if (airPlayPlan == null) {
          throw AppFailure('当前剧集暂无可用的 AirPlay 投屏地址');
        }
        final ok = await HawCastService.instance.replaceAirPlayEpisode(
          plan: airPlayPlan,
          title: '第 ${_detail.episodes[index].number} 集',
          dramaTitle: _detail.drama.title,
          episodeIndex: index,
          startPosition: position > 0 ? position : 0.0,
          rate: _speed,
        );
        if (!ok) {
          throw AppFailure('切换下一集 AirPlay 视频失败');
        }
        if (_closed || ticket != _generation) return;
        _plan = airPlayPlan;
        _openedIndex = index;
        if (mounted) {
          _finishEpisodeSwitchLoading();
          _danmaku.setPlan(airPlayPlan);
          _syncDanmaku();
          _menuRevision.value++;
        }
        return;
      }
      if (_castingActive && HawCastService.instance.activeDevice != null) {
        final castPlan = HawCastPlayerHelper.isRemotePlayablePlan(prepared)
            ? prepared
            : await HawCastPlayerHelper.resolveCastablePlan(
                drama: _detail.drama,
                episode: _detail.episodes[index],
                currentPlan: prepared,
                encryptedPlayback: _encryptedPlayback,
                repository: widget.repository,
                requestedQuality: _requestedQuality,
              );
        if (castPlan == null) {
          throw AppFailure('当前剧集暂无可用的在线投屏地址');
        }
        final req = HawCastPlayerHelper.buildPlayRequest(
          detail: _detail,
          episodeIndex: index,
          plan: castPlan,
          startPosition: position > 0 ? position : 0.0,
        );
        final ok = await HawCastService.instance.startCasting(
          HawCastService.instance.activeDevice!,
          req,
        );
        if (!ok) {
          throw AppFailure('推送剧集至投屏设备失败，请检查设备连接');
        }
        if (_closed || ticket != _generation) return;
        _plan = castPlan;
        _openedIndex = index;
        if (mounted) {
          _finishEpisodeSwitchLoading();
          _danmaku.setPlan(castPlan);
          _syncDanmaku();
          _menuRevision.value++;
        }
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
        if (_player is! LunaExoPlayer && platform is NativePlayer) {
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
          await platform.setProperty('keep-open', 'yes');
        }
        _plan = plan;
        installed = true;
        _acceptErrors = true;
        DiaryService.add(
          '[Play] 打开媒体: 剧=${_detail.drama.cleanSourceId}, 集=${_detail.episodes[index].number}, local=${plan.local}, encrypted=${plan.decryptionKey.isNotEmpty}, host=${Uri.tryParse(plan.url)?.host}',
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
        DiaryService.add(
          '[Play] 清晰度判定: 请求=${_requestedQuality > 0 ? "${_requestedQuality}P" : "自动(优先高清)"}, '
          '源下发=${plan.quality > 0 ? "${plan.quality}P" : "未知"}, '
          '当前集可选=[${plan.qualities.map((q) => "${q}P").join('/')}], '
          '状态=${_requestedQuality > 0 && plan.quality > 0 && _requestedQuality != plan.quality ? "当前集无请求档位，自动回退/匹配" : "完全匹配"}',
        );
        _diagnosticsTimer?.cancel();
        _diagnosticsTimer = Timer(const Duration(seconds: 2), () async {
          if (_closed || ticket != _generation) return;
          final diag = await _getDiagnostics();
          if (diag != null) {
            DiaryService.add(diag.toDiaryLog());
          }
        });
        _enhancement.mediaReady();
        _attachLanPlayback();
        _health.reset();
        await _interactions.applySpeed();
        await _waitForNextFrameReady(ticket);
        if (mounted && !_closed && ticket == _generation) {
          _finishEpisodeSwitchLoading();
          _danmaku.setPlan(plan);
          _syncDanmaku();
          _acknowledgeHandoff();
          _menuRevision.value++;
          _syncNativePictureInPictureConfig();
          if (BackgroundAudioService.instance.isRunning) {
            unawaited(
              BackgroundAudioService.instance.update(
                title: _detail.drama.title,
                episode: '第 ${_detail.episodes[_index].number} 集',
                isPlaying: true,
              ),
            );
          }
          if (_pictureInPictureActive) {
            _syncPictureInPictureSession();
          }
        }
      });
    } catch (error) {
      DiaryService.add(
        '[Play] 播放失败: 剧=${_detail.drama.cleanSourceId}, 集=${_detail.episodes[index].number}, 阶段=$failureStage, 恢复=${_recovery.attempts}/${PlaybackRecovery.attemptLimitFor(error is AppFailure ? error.code : '')}, ${playbackFailureSummary(error)}',
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
            final action = _recovery.next(
              failed,
              errorCode: error is AppFailure ? error.code : '',
            );
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
            _switchingHintTimer?.cancel();
            _dismissTransitionSnapshot(immediate: true);
            setState(() {
              _loading = false;
              _switchingEpisode = false;
              _switchingSlowHint = false;
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
            _syncNativePictureInPictureConfig();
          if (BackgroundAudioService.instance.isRunning) {
            unawaited(
              BackgroundAudioService.instance.update(
                title: _detail.drama.title,
                episode: '第 ${_detail.episodes[_index].number} 集',
                isPlaying: true,
              ),
            );
          }
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

  bool get _isTablet {
    if (!_mobile) return false;
    if (AppLayout.isPad(context)) return true;
    final size = MediaQuery.maybeSizeOf(context);
    return defaultTargetPlatform == TargetPlatform.iOS &&
        size != null &&
        size.shortestSide >= 700;
  }

  bool get _showFullscreen =>
      !widget.feed &&
      (_television ||
          _fullscreen ||
          (_mobile &&
              !_automaticFullscreenSuppressed &&
              MediaQuery.orientationOf(context) == Orientation.landscape &&
              (_aspectRatio >= 1 || _isTablet)));

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
        if (!AppDevice.isPadDevice && !_isTablet) {
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
      }
    } catch (e) {
      DiaryService.warn('Screen', '全屏旋转切换失败', e);
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
    final nextPreferences = preferences;
    await widget.store.setPlaybackPreferences(nextPreferences);
    if (!mounted || _closed || widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    final qualityChanged = nextPreferences.quality != _requestedQuality;
    final decoderChanged =
        nextPreferences.decoderMode != _preferences.decoderMode;
    if (_player is LunaExoPlayer) {
      _player.setDecoderMode(nextPreferences.decoderMode);
    } else if (decoderChanged && Platform.isWindows) {
      final native = _player.platform;
      if (native is NativePlayer) {
        await native.setProperty(
          'hwdec',
          nextPreferences.decoderMode == PlaybackDecoderMode.hardware
              ? 'auto-copy-safe'
              : 'no',
        );
      }
    }
    _enhancement.setPreferences(nextPreferences.enhancement);
    setState(() {
      _speed = nextPreferences.speed;
      _requestedQuality = nextPreferences.quality;
      _decoderMode = nextPreferences.decoderMode;
      _autoAdvance = nextPreferences.autoAdvance;
      _danmakuEnabled = nextPreferences.danmaku;
      _danmakuStyle = nextPreferences.danmakuStyle;
      _preloadEnabled = nextPreferences.preload;
    });
    _danmaku.setEnabled(_danmakuEnabled);
    _syncDanmaku();
    if (qualityChanged) _preloader.clear();
    _syncPreload();
    _menuRevision.value++;
    await _interactions.applySpeed();
    _syncDanmaku();
    if (qualityChanged && _plan?.offline != true) {
      await _retry(quality: nextPreferences.quality);
    } else if (decoderChanged && _plan != null) {
      DiaryService.add(
        '[Player] 解码模式改变为 ${nextPreferences.decoderMode.label}，重新挂载播放器',
      );
      await _retry();
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      await widget.store.toggleFavorite(_detail.drama);
      if (mounted && !_closed) setState(() {});
    } catch (e) {
      DiaryService.warn('Store', '保存追剧记录失败', e);
      _notice('追剧记录未能保存，请检查存储空间后重试');
    }
  }

  Future<void> _toggleDanmaku() async {
    if (_detail.drama.source != 'hongguo') return;
    try {
      await _setPreferences(_preferences.copyWith(danmaku: !_danmakuEnabled));
    } catch (e) {
      DiaryService.warn('Danmaku', '保存弹幕偏好失败', e);
      _notice('弹幕偏好未能保存，请重试');
    }
  }

  Future<void> _retryDanmakuFromControls() async {
    try {
      _danmaku.retry();
      _menuRevision.value++;
    } catch (e) {
      DiaryService.warn('Danmaku', '弹幕重试异常', e);
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
      _detail,
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
          qualities: _plan?.qualities ?? const [],
          selectedQuality: _requestedQuality,
          actualQuality: _plan?.quality ?? 0,
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
      } else if (section == PlayerMenuSection.speed) {
        final chosenSpeed = await PlayerSpeedSheetView.show(
          context: context,
          currentSpeed: _preferences.speed,
          onSpeedSelected: (newSpeed) {
            unawaited(_setPreferences(_preferences.copyWith(speed: newSpeed)));
          },
        );
        if (chosenSpeed != null && chosenSpeed != _preferences.speed) {
          await _setPreferences(_preferences.copyWith(speed: chosenSpeed));
        }
      } else if (_mobile && section == PlayerMenuSection.episodes) {
        final chosenIndex = await PlayerDialogHelper.openEpisodesSheet(
          context: context,
          episodes: _detail.episodes,
          currentIndex: _index,
          dramaTitle: _detail.drama.title,
          seriesEntries: _currentSeriesEntries,
          currentDramaId: _detail.drama.id,
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
          detail: _detail,
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
          onDanmakuSettings: () {
            Navigator.pop(context);
            _openDanmakuSettings();
          },
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

  Future<void> _openComments() async {
    if (_panelOpen || _closed) return;
    _interactions.cancel();
    setState(() => _panelOpen = true);
    try {
      await CommentSheetView.show(
        context: context,
        bookId: _detail.drama.id,
        accountService: HongguoAccountService(),
      );
    } finally {
      if (mounted && !_closed) {
        setState(() => _panelOpen = false);
        _playerFocus.requestFocus();
      }
    }
  }

  Future<void> _openDanmakuSettings() async {
    if (_panelOpen || _closed) return;
    _interactions.cancel();
    setState(() => _panelOpen = true);
    try {
      await PlayerDanmakuSheetView.show(
        context: context,
        enabled: _danmakuEnabled,
        style: _preferences.danmakuStyle,
        onEnabledChanged: (val) {
          unawaited(_setPreferences(_preferences.copyWith(danmaku: val)));
        },
        onStyleChanged: (newStyle) {
          unawaited(
            _setPreferences(_preferences.copyWith(danmakuStyle: newStyle)),
          );
        },
      );
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
    } catch (e) {
      DiaryService.warn('Seek', '跳播寻址失败 target=$target', e);
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
        episodes: _detail.episodes,
        currentIndex: _index,
      );
    } finally {
      if (mounted && !_closed) setState(() => _panelOpen = false);
    }
    if (index != null && mounted && !_closed && index != _index) {
      await _play(index);
    }
  }

  Future<PlaybackTechnicalDiagnostics?> _getDiagnostics() async {
    final player = _player;
    if (player is LunaExoPlayer) {
      return player.getDiagnostics(
        requestedQuality: _requestedQuality,
        actualQuality: _plan?.quality ?? 0,
        availableQualities: _plan?.qualities ?? const [],
        mediaHost: Uri.tryParse(_plan?.url ?? '')?.host,
      );
    }
    final state = _player.state;
    final w = state.videoParams.w;
    final h = state.videoParams.h;
    const codec = 'hevc';
    return PlaybackTechnicalDiagnostics(
      playerEngine: 'MediaKit (NativePlayer)',
      decoderName: codec,
      isHardwareAccelerated: _decoderMode == PlaybackDecoderMode.hardware,
      videoWidth: w,
      videoHeight: h,
      bufferDuration: state.buffer,
      bufferingEventsCount: 0,
      requestedQuality: _requestedQuality,
      actualQuality: _plan?.quality ?? 0,
      availableQualities: _plan?.qualities ?? const [],
      isEncrypted: _plan?.decryptionKey.isNotEmpty == true,
      mediaHost: Uri.tryParse(_plan?.url ?? '')?.host,
      timestamp: DateTime.now(),
    );
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
        actualQuality: _plan?.quality ?? 0,
        favorite: widget.store.isFavorite(_detail.drama.id),
        onFavorite: _toggleFavorite,
        autoAdvance: _autoAdvance,
        danmaku: _danmakuEnabled,
        showDanmaku: _detail.drama.source == 'hongguo',
        danmakuStatus: _danmaku.status,
        onRetryDanmaku: _danmaku.canRetry ? _danmaku.retry : null,
        preload: _preloadEnabled,
        preloadStatus: _preloader.status,
        enhancement: _enhancement,
        enhancementForUi: _enhancementForUi,
        danmakuController: _danmaku,
        preloader: _preloader,
        decoderMode: _preferences.decoderMode,
        quietEpisodeAdvance: _preferences.quietEpisodeAdvance,
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
          autoAdvance: selection.autoAdvance ?? _autoAdvance,
          danmaku: selection.danmaku,
          preload: selection.preload ?? _preloadEnabled,
          enhancement: selection.enhancement,
          decoderMode: selection.decoderMode,
          quietEpisodeAdvance:
              selection.quietEpisodeAdvance ?? _preferences.quietEpisodeAdvance,
        ),
      );
    } catch (e) {
      DiaryService.warn('Preferences', '播放偏好保存失败', e);
      _notice('播放偏好未能保存，请重试');
    }
  }

  void _back() {
    if (_showFullscreen && !_television) {
      _rotate();
    } else if (_television) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    final retainStream =
        Platform.isIOS &&
        _pictureInPictureVisible &&
        _plan != null &&
        _encryptedPlayback.isStreamPlan(_plan!);
    if (retainStream) {
      PipManager.instance.retainPlaybackResource(_encryptedPlayback.close);
    }
    _closed = true;
    final castService = HawCastService.instance;
    castService.removeListener(_onCastServiceChanged);
    castService.onExternalCastActivated = null;
    castService.onExternalCastStopped = null;
    castService.onExternalCastEnded = null;
    _syncNativePictureInPictureConfig(force: true);
    if (_player is LunaExoPlayer) {
      _player.prepareForDispose();
    }
    final enhancementClosed = _enhancement.close();
    LanController.current?.detachPlayback(_lanIdentity);
    widget.handoff?.fail('接收端已退出播放');
    widget.store.removeListener(_accessChanged);
    _danmaku.dispose();
    _preloader.dispose();
    _generation++;
    BackgroundAudioService.instance.unregisterCallbacks();
    unawaited(BackgroundAudioService.instance.stop());
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _saveWarningTimer?.cancel();
    _healthTimer?.cancel();
    _errorTimer?.cancel();
    _pipCoordinator.dispose();
    _diagnosticsTimer?.cancel();
    _volumeSaveTimer?.cancel();
    final latestVolume = _player.state.volume;
    final pref = widget.store.playbackPreferences;
    if ((pref.volume - latestVolume).abs() > 0.5) {
      unawaited(
        widget.store.setPlaybackPreferences(pref.copyWith(volume: latestVolume)),
      );
    }
    _switchingHintTimer?.cancel();
    _snapshotFadeTimer?.cancel();
    _transitionSnapshot?.dispose();
    _transitionSnapshot = null;
    _interactions.dispose();
    _playerFocus.dispose();
    _menuRevision.dispose();
    unawaited(_saveProgress(flush: true));
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    unawaited(widget.repository.release(_session));
    unawaited(_loader.close().catchError((Object _) {}));
    if (!retainStream) {
      unawaited(_encryptedPlayback.cancel().catchError((Object _) {}));
    }
    final closing = _operations.catchError((Object _) {}).then((_) async {
      await _interactions.pendingRates.catchError((Object _) {});
      await enhancementClosed.catchError((Object _) {});
      if (_player is! LunaExoPlayer) {
        await _player.pause().catchError((Object _) {});
      }
      await _player.dispose();
      if (!retainStream) await _encryptedPlayback.close();
    });
    unawaited(
      (_playbackLease?.releaseAfter(closing) ?? closing).catchError(
        (Object _) {},
      ),
    );
    if (!widget.feed && Platform.isWindows) {
      unawaited(windowManager.setFullScreen(false));
    } else if (!widget.feed && (_mobile || _television && Platform.isAndroid)) {
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
          final overlayBrightness = (fullscreen || _mobile)
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
    if (widget.feed) return _videoPane(context);
    final theme = Theme.of(context);
    final title = _detail.drama.title;
    final fullscreen = _showFullscreen;
    final pictureInPicture = _pictureInPictureVisible;
    return PopScope(
      canPop: !_television && (pictureInPicture || !fullscreen),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && widget.store.usesAccountLibrary(_detail.drama.id)) {
          unawaited(_saveProgress(flush: true));
        }
        if (!didPop && fullscreen && !_television && !pictureInPicture) {
          _rotate();
        } else if (!didPop && pictureInPicture) {
          _back();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_pictureInPictureVisible) {
              unawaited(_restoreFromPictureInPicture());
            } else {
              _back();
            }
          },
          const SingleActivator(LogicalKeyboardKey.goBack): _back,
          const SingleActivator(LogicalKeyboardKey.keyP): () {
            unawaited(_togglePictureInPicture());
          },
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
            backgroundColor: fullscreen || pictureInPicture || _mobile
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
                      if (!widget.feed)
                        IconButton(
                          key: const ValueKey('appbar-cast-button'),
                          tooltip: _castingActive ? '正在投屏' : '投屏',
                          onPressed: _openCast,
                          icon: Icon(
                            _castingActive
                                ? Icons.cast_connected_rounded
                                : Icons.cast_rounded,
                            color: _castingActive ? AppColors.hongguoRed : null,
                          ),
                        ),
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
                    top: false,
                    bottom: !fullscreen,
                    left: !fullscreen,
                    right: !fullscreen,
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
                                  episodes: _detail.episodes,
                                  currentIndex: _index,
                                  seriesEntries: _currentSeriesEntries,
                                  currentDramaId: _detail.drama.id,
                                  onSeasonSelected: _switchSeason,
                                  onSelectEpisode: (index) => _play(index),
                                  onFullscreen: _rotate,
                                ),
                              ),
                            ],
                          );
                        }
                        if (_mobile) {
                          final topPadding = fullscreen
                              ? 0.0
                              : MediaQuery.paddingOf(context).top;
                          final height = (constraints.maxWidth / _aspectRatio)
                              .clamp(0.0, constraints.maxHeight * .56);
                          return Column(
                            children: [
                              SizedBox(
                                height: height + topPadding,
                                width: double.infinity,
                                child: _videoPane(
                                  context,
                                  topPadding: topPadding,
                                ),
                              ),
                              Expanded(
                                child: PlayerMobilePanelView(
                                  detail: _detail,
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
                                episodes: _detail.episodes,
                                currentIndex: _index,
                                seriesEntries: _currentSeriesEntries,
                                currentDramaId: _detail.drama.id,
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

  Widget _feedControls() {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, HongguoAccountSocial.shared]),
      builder: (context, _) {
        final social = HongguoAccountSocial.shared;
        final creator = social
            .snapshot(_detail.drama)
            ?.creators
            .firstOrNull;
        final anchor = creator == null
            ? null
            : Anchor(
                id: creator.id,
                name: creator.name,
                officialFollowing: creator.following,
                canFollow: creator.canFollow,
                relativeType: creator.relativeType,
              );
        return StreamBuilder<bool>(
          stream: _player.stream.playing,
          builder: (context, snapshot) => StreamBuilder<Duration>(
            stream: _player.stream.position,
            builder: (context, _) => FeedPlayerOverlay(
              title: _detail.drama.title,
              episodeText:
                  '第 ${_detail.episodes[_index].number} 集 · 共 ${_detail.episodes.length} 集',
              description: _detail.drama.description,
              playing: _player.state.playing,
              enabled: !_loading && _error == null,
              following: widget.store.following(_detail.drama.id) != null,
              danmakuEnabled: _danmakuEnabled,
              position: _player.state.position,
              duration: _player.state.duration,
              isLiked: widget.store.isLiked(_detail.drama.id),
              onLike: () {
                widget.store.toggleLike(_detail.drama);
                if (widget.store.usesAccountLibrary(_detail.drama.id)) {
                  final ep = _detail.episodes[_index].number;
                  final likeModel = HongguoAccountSocial.shared
                      .snapshot(_detail.drama)
                      ?.episode(ep);
                  if (likeModel != null) {
                    HongguoAccountSocial.shared.like(
                      _detail.drama,
                      likeModel,
                      !likeModel.liked,
                    );
                  }
                }
              },
              anchorName: anchor?.name ?? '',
              isAnchorFollowed: creator?.following == true,
              onToggleFollowAnchor:
                  creator == null ||
                      creator.following == null ||
                      social.busy(_detail.drama) ||
                      (!creator.canFollow && creator.following != true)
                  ? null
                  : () => unawaited(
                      saveUserChange(
                        context,
                        () => social.follow(
                          _detail.drama,
                          creator,
                          !creator.following!,
                        ),
                      ),
                    ),
              onOpenAnchorDetail: anchor == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AnchorDetailPage(
                            anchor: anchor,
                            repository: widget.repository,
                            store: widget.store,
                            initialDramas: [_detail.drama],
                          ),
                        ),
                      );
                    },
              onTogglePlayback: _togglePlayback,
              onSeek: (value) => unawaited(
                _seekTo(
                  Duration(
                    milliseconds:
                        (_player.state.duration.inMilliseconds * value).round(),
                  ),
                ),
              ),
              onFavorite: () => unawaited(
                saveUserChange(
                  context,
                  () => widget.store.toggleFavorite(_detail.drama),
                ),
              ),
              onEpisodes: () =>
                  unawaited(_openPanel(PlayerMenuSection.episodes)),
              onFullscreen: _rotate,
              onDetail: widget.onOpenDetail ?? () {},
              onDanmaku: () => unawaited(_toggleDanmaku()),
              onSettings: () =>
                  unawaited(_openPanel(PlayerMenuSection.settings)),
            ),
          ),
        );
      },
    );
  }

  Widget _videoPane(BuildContext context, {double topPadding = 0.0}) {
    return PlayerViewportView(
      topPadding: topPadding,
      television: _television,
      fullscreen: _showFullscreen,
      pictureInPictureVisible: _pictureInPictureVisible,
      mobile: _mobile,
      detail: _detail,
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
      danmakuStyle: _preferences.danmakuStyle,
      aspectRatio: _aspectRatio,
      interactions: _interactions,
      enhancement: _enhancement,
      enhancementForUi: _enhancementForUi,
      speed: _speed,
      qualityLabel: _qualityLabel,
      showControlsOnPlaybackReady: _showControlsOnPlaybackReady,
      panelOpen: _panelOpen,
      canUsePictureInPicture: _canUsePictureInPicture,
      pictureInPictureRequested: _pictureInPictureRequested,
      playerFocus: _playerFocus,
      videoPaneKey: _videoPaneKey,
      backgroundAudio: widget.store.playbackPreferences.backgroundAudio,
      onToggleBackgroundAudio: _toggleBackgroundAudio,
      episodeTransition: widget.store.playbackPreferences.episodeTransition,
      videoCaptureKey: _videoCaptureKey,
      transitionSnapshot: _transitionSnapshot,
      transitionSnapshotVisible: _transitionSnapshotVisible,
      transitionDirection: _transitionDirection,
      switchingSlowHint: _switchingSlowHint,
      allowOnlineFallback: widget.allowOnlineFallback,
      localOnly: widget.localOnly,
      isMediaIdNull: widget.mediaId == null,
      repository: widget.repository,
      store: widget.store,
      videoBuilder: widget.videoBuilder,
      controlsOverlay: widget.feed ? _feedControls() : null,
      onTogglePlayback: _togglePlayback,
      onSeek: _seek,
      onSeekTo: _seekTo,
      onPlay: _play,
      onRotate: _rotate,
      onBack: _back,
      onRetry: _retry,
      onSwitchOnline: _switchOnline,
      onSaveProgress: () async {
        _interactions.hint('正在同步账号进度...');
        await _saveProgress(flush: true);
        if (_saveWarning == null) {
          _interactions.hint('账号进度已成功同步');
        }
      },
      onDismissSaveWarning: _dismissSaveWarning,
      onOpenPanel: _openPanel,
      onComments: _openComments,
      onToggleDanmaku: _toggleDanmaku,
      onDanmakuSettings: _openDanmakuSettings,
      onRetryDanmaku: _retryDanmakuFromControls,
      onPushToDevice: _pushToDevice,
      onCast: widget.feed ? null : _openCast,
      casting: _castingActive,
      castOverlay: _castingActive
          ? HawCastOverlay(
              title:
                  '${_detail.drama.title} · 第 ${_detail.episodes[_index].number} 集',
              fullscreen: _showFullscreen,
              onBack: _back,
              onFullscreen: _rotate,
              onSwitchDevice: _openCast,
              onStopCast: _stopCast,
              onEpisodes: () => _openPanel(PlayerMenuSection.episodes),
              onPrevious: _index > 0 ? () => _play(_index - 1) : null,
              onNext: _index + 1 < _detail.episodes.length
                  ? () => _play(_index + 1)
                  : null,
            )
          : null,
      onEnterPictureInPicture: _enterPictureInPicture,
      onRestorePictureInPicture: _restoreFromPictureInPicture,
      onTelevisionEpisodes: _televisionEpisodes,
      onTelevisionSettings: _televisionSettings,
      onFetchDiagnostics: _getDiagnostics,
    );
  }
}
