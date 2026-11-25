import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/core/player/desktop_pip_controller.dart';
import 'package:THLRedLook/core/player/encrypted_playback.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/core/player/pip_manager.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/player/player_pip_bounds.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';

/// 画中画（Picture in Picture）状态与通道协调器
/// 负责管理移动端原生画中画与桌面端置顶小窗的生命周期与状态同步
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
  final bool isFeed, isLocalOnly;
  final bool Function() getPlayIntent, getIsLoading;
  final Object? Function() getError;
  final int Function() getOpenedIndex;
  final AppLifecycleState Function() getLifecycleState;
  final LocalStore Function() getStore;
  final EncryptedPlayback Function() getEncryptedPlayback;

  final VoidCallback onStatusChanged, onDismissOverlays;
  final void Function(int nextIndex) onEpisodeAdvanced;
  final Future<void> Function(int index, {double position}) onPlay;
  final Future<void> Function(Duration target) onSeekTo;
  final void Function(String message) onNotice;
  final void Function({bool pauseWhenHidden}) onApplyLifecycleVisibility;

  bool supported = false, active = false, requested = false;
  bool handlerInstalled = false, _lastNativeAutoEnter = false;
  int _lastNativeWidth = 0, _lastNativeHeight = 0;
  Timer? _exitTimer;
  int? _originalIndex;
  VoidCallback? _desktopPipListener;

  bool get isDesktop => DesktopPipController.instance.isSupported;
  bool get isPlatformSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      isDesktop;
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
    if (isDesktop) {
      _desktopPipListener = () {
        if (!isMounted() || isClosed()) return;
        final act = DesktopPipController.instance.isActive;
        if (active != act) setStatus(active: act, requested: false);
      };
      DesktopPipController.instance.addListener(_desktopPipListener!);
    }
    syncSession();
    unawaited(refreshStatus());
  }

  void syncSession() {
    if (isDesktop) return;
    handlerInstalled = true;
    _originalIndex ??= getCurrentIndex();
    PipManager.instance.registerPictureInPictureSession(
      detail: getDetail(),
      episodeIndex: getCurrentIndex(),
      positionMs: getPlayer().state.position.inMilliseconds,
      quality: getRequestedQuality(),
      speed: getSpeed(),
      localOnly: isLocalOnly,
      onEpisodeAdvanced: (next) {
        if (isMounted() && !isClosed()) {
          setCurrentIndex(next);
          onEpisodeAdvanced(next);
        }
      },
      onRestoreCurrentPlayer: _handleRestorePlayer,
      onPictureInPictureStatusChanged: _handlePipStatusChanged,
    );
  }

  void _handleRestorePlayer(int positionMs) {
    if (!isMounted() || isClosed()) return;
    final adv = _originalIndex != null && _originalIndex != getCurrentIndex();
    _originalIndex = null;
    setStatus(active: false);
    if (adv) {
      unawaited(onPlay(getCurrentIndex(), position: positionMs > 0 ? positionMs / 1000.0 : 0.0));
    } else {
      if (positionMs > 0) unawaited(onSeekTo(Duration(milliseconds: positionMs)));
      if (getPlayIntent() && !getIsLoading() && getError() == null) unawaited(getPlayer().play());
    }
  }

  void _handlePipStatusChanged(bool nextActive, String? error, int? pos) {
    if (!isMounted() || isClosed()) return;
    if (nextActive) onDismissOverlays();
    if (error != null && error.isNotEmpty) {
      onNotice('画中画提示: ${PlayerPipBoundsCalculator.localizeError(error)}');
    }
    if (nextActive) {
      _originalIndex = getCurrentIndex();
      if (Platform.isIOS && getPlayer().state.playing) unawaited(getPlayer().pause());
    } else {
      final adv = _originalIndex != null && _originalIndex != getCurrentIndex();
      _originalIndex = null;
      if (adv) {
        unawaited(onPlay(getCurrentIndex(), position: (pos != null && pos > 0) ? pos / 1000.0 : 0.0));
      } else {
        if (pos != null && pos > 0) unawaited(onSeekTo(Duration(milliseconds: pos)));
        if (getPlayIntent() && !getIsLoading() && getError() == null) unawaited(getPlayer().play());
      }
    }
    setStatus(active: nextActive, requested: false, delayHiddenPause: !nextActive);
    syncNativeConfig();
  }

  Future<void> refreshStatus() async {
    if (!isPlatformSupported) return;
    if (isDesktop) {
      if (!isMounted() || isClosed()) return;
      setStatus(supported: true, active: DesktopPipController.instance.isActive);
      return;
    }
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>('pictureInPictureStatus');
      if (!isMounted() || isClosed()) return;
      setStatus(supported: status?['supported'] == true, active: status?['active'] == true);
    } catch (_) {
      if (isMounted() && !isClosed()) setStatus(supported: false, active: false);
    }
  }

  void setStatus({bool? supported, bool? active, bool? requested, bool delayHiddenPause = false}) {
    this.supported = supported ?? this.supported;
    this.active = active ?? this.active;
    this.requested = requested ?? (this.active ? false : this.requested);
    onStatusChanged();
    syncNativeConfig();

    final state = getLifecycleState();
    if (isVisible || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive) {
      _exitTimer?.cancel();
      onApplyLifecycleVisibility(pauseWhenHidden: false);
      return;
    }
    _exitTimer?.cancel();
    onApplyLifecycleVisibility(pauseWhenHidden: !delayHiddenPause);
    if (delayHiddenPause) {
      _exitTimer = Timer(const Duration(milliseconds: 700), () {
        if (!isClosed() && !isVisible && getLifecycleState() != AppLifecycleState.resumed && getLifecycleState() != AppLifecycleState.inactive) {
          onApplyLifecycleVisibility();
        }
      });
    }
  }

  (int, int) aspectDimensions() => PlayerPipBoundsCalculator.aspectDimensions(getAspectRatio());

  void syncNativeConfig({bool force = false}) {
    if (defaultTargetPlatform != TargetPlatform.android || isFeed) return;
    final autoEnter = shouldAutoEnter;
    final (w, h) = aspectDimensions();
    if (!force && autoEnter == _lastNativeAutoEnter && w == _lastNativeWidth && h == _lastNativeHeight) {
      return;
    }
    _lastNativeAutoEnter = autoEnter;
    _lastNativeWidth = w;
    _lastNativeHeight = h;
    final sourceRect = autoEnter ? calculateSourceRect() : null;
    unawaited(AppDevice.channel.invokeMethod<dynamic>('updatePictureInPictureConfig', {
      'autoEnter': autoEnter,
      'width': w,
      'height': h,
      ...?sourceRect,
    }).catchError((Object _) => null));
  }

  Map<String, int>? calculateSourceRect() =>
      PlayerPipBoundsCalculator.calculateSourceRect(videoPaneKey: getVideoPaneKey(), aspectRatio: getAspectRatio());

  void _resumeIfWasPlaying(bool wasPlaying) {
    if (Platform.isIOS && wasPlaying && !isClosed() && isMounted()) {
      unawaited(getPlayer().play());
    }
  }

  Future<void> enterPictureInPicture() async {
    if (isClosed()) return;
    if (!canUse) return onNotice('画中画未开启或当前设备暂不支持');
    if (getIsLoading()) return onNotice('正在加载视频，请稍候开启画中画');
    if (getError() != null) return onNotice('视频播放出错，无法开启画中画');
    if (requested) {
      if (defaultTargetPlatform != TargetPlatform.android) onNotice('正在启动画中画，请稍候...');
      return;
    }
    onDismissOverlays();

    if (isDesktop) {
      final success = await DesktopPipController.instance.enterPip(aspectRatio: getAspectRatio());
      if (!isMounted() || isClosed()) return;
      if (success) {
        setStatus(supported: true, active: true, requested: false);
        onNotice('已进入桌面置顶小窗播放（按 P 键还原）');
      } else {
        onNotice('进入桌面小窗失败');
      }
      return;
    }

    final wasPlaying = getPlayer().state.playing;
    if (Platform.isIOS && wasPlaying) await getPlayer().pause();
    final (width, height) = aspectDimensions();
    if (defaultTargetPlatform != TargetPlatform.android) onNotice('正在启动画中画...');
    setStatus(requested: true);
    await WidgetsBinding.instance.endOfFrame;
    if (!isMounted() || isClosed()) return;

    final plan = getPlan();
    final player = getPlayer();
    final mediaUrl = plan?.url.isNotEmpty == true ? plan!.url : (player is LunaExoPlayer ? player.mediaUri : '');
    String targetUrl = mediaUrl;
    Map<String, String> targetHeaders = plan?.headers ?? const <String, String>{};

    if (Platform.isIOS && plan != null && plan.decryptionKey.isNotEmpty && !plan.local) {
      onNotice('正在准备画中画视频...');
      try {
        final prepared = await getEncryptedPlayback().prepare(plan, forceCache: true, progress: (val) {
          if (isMounted() && !isClosed()) onNotice('正在准备画中画 ${(val * 100).round()}%');
        });
        if (isClosed() || !isMounted()) return;
        targetUrl = prepared.url;
        targetHeaders = prepared.headers;
      } catch (e) {
        DiaryService.warn('PiP', '准备画中画加密视频失败', e);
        onNotice('准备画中画视频失败: $e');
        setStatus(requested: false);
        _resumeIfWasPlaying(wasPlaying);
        return;
      }
    }

    _exitTimer?.cancel();
    _exitTimer = Timer(const Duration(seconds: 8), () {
      if (!isClosed() && requested && !active) {
        setStatus(requested: false);
        onNotice('无法进入画中画，请检查系统设置');
        _resumeIfWasPlaying(wasPlaying);
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
      ...?sourceRect,
    };
    syncSession();

    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>('enterPictureInPicture', arguments);
      if (!isMounted() || isClosed()) return;
      final isSupp = status?['supported'] == true;
      final isAct = status?['active'] == true;
      final isReq = status?['requested'] == true;
      final error = status?['error'] as String?;
      setStatus(supported: isSupp, active: isAct, requested: isReq && !isAct);
      if (!isSupp) {
        _exitTimer?.cancel();
        onNotice('当前系统或设备不支持画中画');
        _resumeIfWasPlaying(wasPlaying);
      } else if (!isAct && !isReq) {
        _exitTimer?.cancel();
        onNotice(PlayerPipBoundsCalculator.localizeError(error));
        _resumeIfWasPlaying(wasPlaying);
      }
    } catch (e) {
      _exitTimer?.cancel();
      setStatus(requested: false);
      DiaryService.warn('PiP', '启动画中画异常', e);
      onNotice('启动画中画异常: $e');
      _resumeIfWasPlaying(wasPlaying);
    }
  }

  Future<void> restoreFromPictureInPicture() async {
    if (isDesktop) {
      await DesktopPipController.instance.restorePip();
      setStatus(active: false, requested: false);
      return;
    }
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>('stopPictureInPicture');
      final pos = (status?['position'] as num?)?.toInt();
      if (pos != null && pos > 0) await onSeekTo(Duration(milliseconds: pos));
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
    if (_desktopPipListener != null) {
      DesktopPipController.instance.removeListener(_desktopPipListener!);
      _desktopPipListener = null;
    }
    if (handlerInstalled) {
      PipManager.instance.notifyPlayerDisposed();
      handlerInstalled = false;
    }
  }
}
