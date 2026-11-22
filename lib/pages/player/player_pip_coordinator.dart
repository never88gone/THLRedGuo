import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/core/player/encrypted_playback.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/core/player/pip_manager.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/player/player_pip_bounds.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';

/// 画中画（Picture in Picture）状态与通道协调器
/// 负责管理与原生系统的画中画生命周期、原生会话参数同步与错误处理
class PlayerPipCoordinator {
  PlayerPipCoordinator({
    required this.getContext,
    required this.isMounted,
    required this.isClosed,
    required this.getDetail,
    required this.getCurrentIndex,
    required this.setCurrentIndex,
    required this.getPlan,
    required this.getPlayer,
    required this.getRequestedQuality,
    required this.getSpeed,
    required this.getAspectRatio,
    required this.getVideoPaneKey,
    required this.isFeed,
    required this.isLocalOnly,
    required this.getPlayIntent,
    required this.getIsLoading,
    required this.getError,
    required this.getOpenedIndex,
    required this.getLifecycleState,
    required this.getStore,
    required this.getEncryptedPlayback,
    required this.onStatusChanged,
    required this.onEpisodeAdvanced,
    required this.onPlay,
    required this.onSeekTo,
    required this.onDismissOverlays,
    required this.onNotice,
    required this.onApplyLifecycleVisibility,
  });

  final BuildContext Function() getContext;
  final bool Function() isMounted;
  final bool Function() isClosed;
  final DramaDetail Function() getDetail;
  final int Function() getCurrentIndex;
  final void Function(int index) setCurrentIndex;
  final PlaybackPlan? Function() getPlan;
  final Player Function() getPlayer;
  final int Function() getRequestedQuality;
  final double Function() getSpeed;
  final double Function() getAspectRatio;
  final GlobalKey Function() getVideoPaneKey;
  final bool isFeed;
  final bool isLocalOnly;
  final bool Function() getPlayIntent;
  final bool Function() getIsLoading;
  final Object? Function() getError;
  final int Function() getOpenedIndex;
  final AppLifecycleState Function() getLifecycleState;
  final LocalStore Function() getStore;
  final EncryptedPlayback Function() getEncryptedPlayback;

  final VoidCallback onStatusChanged;
  final void Function(int nextIndex) onEpisodeAdvanced;
  final Future<void> Function(int index, {double position}) onPlay;
  final Future<void> Function(Duration target) onSeekTo;
  final VoidCallback onDismissOverlays;
  final void Function(String message) onNotice;
  final void Function({bool pauseWhenHidden}) onApplyLifecycleVisibility;

  bool supported = false;
  bool active = false;
  bool requested = false;
  bool handlerInstalled = false;

  bool _lastNativeAutoEnter = false;
  int _lastNativeWidth = 0, _lastNativeHeight = 0;
  Timer? _exitTimer;
  int? _originalIndex;

  bool get isPlatformSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get canUse =>
      getStore().playbackPreferences.pictureInPicture &&
      isPlatformSupported &&
      supported;

  bool get isVisible =>
      active ||
      (defaultTargetPlatform == TargetPlatform.android && requested);

  bool get shouldAutoEnter =>
      defaultTargetPlatform == TargetPlatform.android &&
      !isFeed &&
      !isClosed() &&
      canUse &&
      !getIsLoading() &&
      getError() == null &&
      getOpenedIndex() == getCurrentIndex() &&
      getPlayIntent();

  void configure() {
    if (isFeed || !isPlatformSupported) return;
    syncSession();
    unawaited(refreshStatus());
  }

  void syncSession() {
    handlerInstalled = true;
    _originalIndex ??= getCurrentIndex();
    PipManager.instance.registerPictureInPictureSession(
      detail: getDetail(),
      episodeIndex: getCurrentIndex(),
      positionMs: getPlayer().state.position.inMilliseconds,
      quality: getRequestedQuality(),
      speed: getSpeed(),
      localOnly: isLocalOnly,
      onEpisodeAdvanced: (nextIndex) {
        if (isMounted() && !isClosed()) {
          setCurrentIndex(nextIndex);
          onEpisodeAdvanced(nextIndex);
        }
      },
      onRestoreCurrentPlayer: (positionMs) {
        if (isMounted() && !isClosed()) {
          final advanced =
              _originalIndex != null && _originalIndex != getCurrentIndex();
          _originalIndex = null;
          setStatus(active: false);
          if (advanced) {
            unawaited(
              onPlay(
                getCurrentIndex(),
                position: positionMs > 0 ? positionMs / 1000.0 : 0.0,
              ),
            );
          } else {
            if (positionMs > 0) {
              unawaited(onSeekTo(Duration(milliseconds: positionMs)));
            }
            if (getPlayIntent() && !getIsLoading() && getError() == null) {
              unawaited(getPlayer().play());
            }
          }
        }
      },
      onPictureInPictureStatusChanged: (nextActive, error, position) {
        if (isMounted() && !isClosed()) {
          if (nextActive) {
            onDismissOverlays();
          }
          if (error != null && error.isNotEmpty) {
            onNotice(
              '画中画提示: ${PlayerPipBoundsCalculator.localizeError(error)}',
            );
          }
          if (nextActive) {
            _originalIndex = getCurrentIndex();
            if (Platform.isIOS && getPlayer().state.playing) {
              unawaited(getPlayer().pause());
            }
          } else {
            final advanced =
                _originalIndex != null && _originalIndex != getCurrentIndex();
            _originalIndex = null;
            if (advanced) {
              unawaited(
                onPlay(
                  getCurrentIndex(),
                  position: position != null && position > 0
                      ? position / 1000.0
                      : 0.0,
                ),
              );
            } else {
              if (position != null && position > 0) {
                unawaited(onSeekTo(Duration(milliseconds: position)));
              }
              if (getPlayIntent() && !getIsLoading() && getError() == null) {
                unawaited(getPlayer().play());
              }
            }
          }
          setStatus(
            active: nextActive,
            requested: false,
            delayHiddenPause: !nextActive,
          );
          syncNativeConfig();
        }
      },
    );
  }

  Future<void> refreshStatus() async {
    if (!isPlatformSupported) return;
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'pictureInPictureStatus',
      );
      if (!isMounted() || isClosed()) return;
      setStatus(
        supported: status?['supported'] == true,
        active: status?['active'] == true,
      );
    } on PlatformException {
      if (isMounted() && !isClosed()) {
        setStatus(supported: false, active: false);
      }
    } on MissingPluginException {
      if (isMounted() && !isClosed()) {
        setStatus(supported: false, active: false);
      }
    }
  }

  void setStatus({
    bool? supported,
    bool? active,
    bool? requested,
    bool delayHiddenPause = false,
  }) {
    final nextSupported = supported ?? this.supported;
    final nextActive = active ?? this.active;
    final nextRequested =
        requested ?? (nextActive ? false : this.requested);

    this.supported = nextSupported;
    this.active = nextActive;
    this.requested = nextRequested;

    onStatusChanged();
    syncNativeConfig();

    final lifecycleState = getLifecycleState();
    if (isVisible ||
        lifecycleState == AppLifecycleState.resumed ||
        lifecycleState == AppLifecycleState.inactive) {
      _exitTimer?.cancel();
      onApplyLifecycleVisibility(pauseWhenHidden: false);
      return;
    }
    _exitTimer?.cancel();
    onApplyLifecycleVisibility(pauseWhenHidden: !delayHiddenPause);
    if (delayHiddenPause) {
      _exitTimer = Timer(const Duration(milliseconds: 700), () {
        if (!isClosed() &&
            !isVisible &&
            getLifecycleState() != AppLifecycleState.resumed &&
            getLifecycleState() != AppLifecycleState.inactive) {
          onApplyLifecycleVisibility();
        }
      });
    }
  }

  (int, int) aspectDimensions() =>
      PlayerPipBoundsCalculator.aspectDimensions(getAspectRatio());

  void syncNativeConfig({bool force = false}) {
    if (defaultTargetPlatform != TargetPlatform.android || isFeed) {
      return;
    }
    final autoEnter = shouldAutoEnter;
    final dimensions = aspectDimensions();
    final width = dimensions.$1;
    final height = dimensions.$2;
    if (!force &&
        autoEnter == _lastNativeAutoEnter &&
        width == _lastNativeWidth &&
        height == _lastNativeHeight) {
      return;
    }
    _lastNativeAutoEnter = autoEnter;
    _lastNativeWidth = width;
    _lastNativeHeight = height;
    final sourceRect = autoEnter ? calculateSourceRect() : null;
    final arguments = <String, dynamic>{
      'autoEnter': autoEnter,
      'width': width,
      'height': height,
      ...?sourceRect,
    };
    unawaited(
      AppDevice.channel
          .invokeMethod<dynamic>('updatePictureInPictureConfig', arguments)
          .catchError((Object _) => null),
    );
  }

  Map<String, int>? calculateSourceRect() =>
      PlayerPipBoundsCalculator.calculateSourceRect(
        videoPaneKey: getVideoPaneKey(),
        aspectRatio: getAspectRatio(),
      );

  Future<void> enterPictureInPicture() async {
    if (isClosed()) return;
    if (!canUse) {
      onNotice('画中画未开启或当前设备暂不支持');
      return;
    }
    if (getIsLoading()) {
      onNotice('正在加载视频，请稍候开启画中画');
      return;
    }
    if (getError() != null) {
      onNotice('视频播放出错，无法开启画中画');
      return;
    }
    if (requested) {
      if (defaultTargetPlatform != TargetPlatform.android) {
        onNotice('正在启动画中画，请稍候...');
      }
      return;
    }
    onDismissOverlays();
    final wasPlaying = getPlayer().state.playing;
    if (Platform.isIOS && wasPlaying) {
      await getPlayer().pause();
    }
    final (width, height) = aspectDimensions();
    if (defaultTargetPlatform != TargetPlatform.android) {
      onNotice('正在启动画中画...');
    }
    setStatus(requested: true);

    await WidgetsBinding.instance.endOfFrame;
    if (!isMounted() || isClosed()) return;

    final plan = getPlan();
    final player = getPlayer();
    final mediaUrl = plan?.url.isNotEmpty == true
        ? plan!.url
        : (player is LunaExoPlayer ? player.mediaUri : '');
    final headers = plan?.headers ?? const <String, String>{};

    String targetUrl = mediaUrl;
    Map<String, String> targetHeaders = headers;
    final isEncryptedStream =
        Platform.isIOS &&
        plan != null &&
        plan.decryptionKey.isNotEmpty &&
        !plan.local;

    if (isEncryptedStream) {
      onNotice('正在准备画中画视频...');
      try {
        final prepared = await getEncryptedPlayback().prepare(
          plan,
          forceCache: true,
          progress: (val) {
            if (isMounted() && !isClosed()) {
              onNotice('正在准备画中画 ${(val * 100).round()}%');
            }
          },
        );
        if (isClosed() || !isMounted()) return;
        targetUrl = prepared.url;
        targetHeaders = prepared.headers;
      } catch (e, st) {
        DiaryService.warn('PiP', '准备画中画加密视频失败', e);
        debugPrint('[PiP-Dart] 准备画中画加密视频失败: $e\n$st');
        onNotice('准备画中画视频失败: $e');
        setStatus(requested: false);
        if (Platform.isIOS && wasPlaying && !isClosed()) {
          unawaited(getPlayer().play());
        }
        return;
      }
    }

    _exitTimer?.cancel();
    _exitTimer = Timer(const Duration(seconds: 8), () {
      if (!isClosed() && requested && !active) {
        setStatus(requested: false);
        onNotice('无法进入画中画，请检查系统设置');
        if (Platform.isIOS && wasPlaying && !isClosed()) {
          unawaited(getPlayer().play());
        }
      }
    });

    final sourceRect = calculateSourceRect();
    final detail = getDetail();
    final arguments = <String, dynamic>{
      'width': width,
      'height': height,
      if (targetUrl.isNotEmpty) 'url': targetUrl,
      if (targetHeaders.isNotEmpty) 'headers': targetHeaders,
      'title': detail.drama.title,
      'dramaId': detail.drama.id,
      'episodeIndex': getCurrentIndex(),
      'detail': detail.toJson(),
      'position': getPlayer().state.position.inMilliseconds,
      'speed': getSpeed(),
    };
    if (sourceRect != null) arguments.addAll(sourceRect);
    syncSession();
    debugPrint(
      '[PiP-Dart] enterPictureInPicture args: url=$targetUrl, pos=${arguments['position']}, sourceRect=$sourceRect',
    );
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'enterPictureInPicture',
        arguments,
      );
      debugPrint('[PiP-Dart] enterPictureInPicture return: $status');
      if (!isMounted() || isClosed()) return;
      final isSupported = status?['supported'] == true;
      final isActive = status?['active'] == true;
      final isRequested = status?['requested'] == true;
      final error = status?['error'] as String?;
      setStatus(
        supported: isSupported,
        active: isActive,
        requested: isRequested && !isActive,
      );
      if (!isSupported) {
        _exitTimer?.cancel();
        onNotice('当前系统或设备不支持画中画');
        if (Platform.isIOS && wasPlaying && !isClosed()) {
          unawaited(getPlayer().play());
        }
      } else if (!isActive && !isRequested) {
        _exitTimer?.cancel();
        onNotice(PlayerPipBoundsCalculator.localizeError(error));
        if (Platform.isIOS && wasPlaying && !isClosed()) {
          unawaited(getPlayer().play());
        }
      }
    } on PlatformException catch (e) {
      _exitTimer?.cancel();
      setStatus(requested: false);
      onNotice(PlayerPipBoundsCalculator.localizeError(e.message));
      if (Platform.isIOS && wasPlaying && !isClosed()) {
        unawaited(getPlayer().play());
      }
    } on MissingPluginException {
      _exitTimer?.cancel();
      setStatus(supported: false, requested: false);
      onNotice('当前平台不支持画中画');
      if (Platform.isIOS && wasPlaying && !isClosed()) {
        unawaited(getPlayer().play());
      }
    } catch (e, st) {
      _exitTimer?.cancel();
      setStatus(requested: false);
      DiaryService.warn('PiP', '启动画中画异常', e);
      debugPrint('[PiP-Dart] 启动画中画异常: $e\n$st');
      onNotice('启动画中画异常: $e');
      if (Platform.isIOS && wasPlaying && !isClosed()) {
        unawaited(getPlayer().play());
      }
    }
  }

  Future<void> restoreFromPictureInPicture() async {
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'stopPictureInPicture',
      );
      final position = (status?['position'] as num?)?.toInt();
      if (position != null && position > 0) {
        await onSeekTo(Duration(milliseconds: position));
      }
    } catch (e) {
      DiaryService.warn('PiP', '停止画中画异常', e);
    }
    setStatus(active: false, requested: false);
    if (getPlayIntent() && !getIsLoading() && getError() == null) {
      unawaited(getPlayer().play());
    }
  }

  void cancelExitTimer() {
    _exitTimer?.cancel();
    _exitTimer = null;
  }

  void dispose() {
    cancelExitTimer();
    if (handlerInstalled) {
      PipManager.instance.notifyPlayerDisposed();
      handlerInstalled = false;
    }
  }
}
