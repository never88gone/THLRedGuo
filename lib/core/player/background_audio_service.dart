import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:THLRedLook/utils/build/app_build.dart';

@pragma('vm:entry-point')
void backgroundAudioTaskEntry() {
  FlutterForegroundTask.setTaskHandler(BackgroundAudioTaskHandler());
}

class BackgroundAudioTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    BackgroundAudioService.instance.handleNotificationAction(id);
  }
}

/// 后台听剧模式服务（系统通知栏与锁屏媒体控制器）
class BackgroundAudioService {
  BackgroundAudioService._();
  static final BackgroundAudioService instance = BackgroundAudioService._();

  VoidCallback? onTogglePlayback;
  VoidCallback? onPrevious;
  VoidCallback? onNext;

  bool _running = false;
  bool _initialized = false;
  String _currentTitle = '';
  String _currentEpisode = '';
  bool _isPlaying = false;

  bool get isRunning => _running;

  void registerCallbacks({
    VoidCallback? onTogglePlayback,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
  }) {
    this.onTogglePlayback = onTogglePlayback;
    this.onPrevious = onPrevious;
    this.onNext = onNext;
  }

  void unregisterCallbacks() {
    onTogglePlayback = null;
    onPrevious = null;
    onNext = null;
  }

  void handleNotificationAction(String action) {
    switch (action) {
      case 'toggle':
        onTogglePlayback?.call();
        break;
      case 'prev':
        onPrevious?.call();
        break;
      case 'next':
        onNext?.call();
        break;
    }
  }

  Future<void> initIfNeeded() async {
    if (_initialized || !Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'thl_listening_mode',
        channelName: '$appName后台听剧',
        channelDescription: '短剧后台收听与锁屏控制中心',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        stopWithTask: true,
      ),
    );
    _initialized = true;
  }

  Future<void> start({
    required String title,
    required String episode,
    required bool isPlaying,
  }) async {
    if (!Platform.isAndroid) return;
    _currentTitle = title;
    _currentEpisode = episode;
    _isPlaying = isPlaying;

    await initIfNeeded();
    if (_running) {
      await update(title: title, episode: episode, isPlaying: isPlaying);
      return;
    }

    try {
      await FlutterForegroundTask.requestNotificationPermission();
      await FlutterForegroundTask.startService(
        serviceId: 2408,
        serviceTypes: [ForegroundServiceTypes.mediaPlayback],
        notificationTitle: title,
        notificationText: '$episode · 后台听剧模式',
        notificationButtons: [
          const NotificationButton(id: 'prev', text: '上一集'),
          NotificationButton(
            id: 'toggle',
            text: isPlaying ? '暂停' : '播放',
          ),
          const NotificationButton(id: 'next', text: '下一集'),
        ],
        callback: backgroundAudioTaskEntry,
      );
      _running = await FlutterForegroundTask.isRunningService;
    } catch (e) {
      debugPrint('BackgroundAudioService start failed: $e');
    }
  }

  Future<void> update({
    String? title,
    String? episode,
    bool? isPlaying,
  }) async {
    if (!Platform.isAndroid || !_running) return;
    _currentTitle = title ?? _currentTitle;
    _currentEpisode = episode ?? _currentEpisode;
    _isPlaying = isPlaying ?? _isPlaying;

    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: _currentTitle,
        notificationText: '$_currentEpisode · 后台听剧模式',
        notificationButtons: [
          const NotificationButton(id: 'prev', text: '上一集'),
          NotificationButton(
            id: 'toggle',
            text: _isPlaying ? '暂停' : '播放',
          ),
          const NotificationButton(id: 'next', text: '下一集'),
        ],
      );
    } catch (e) {
      debugPrint('BackgroundAudioService update failed: $e');
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid || !_running) return;
    try {
      await FlutterForegroundTask.stopService();
      _running = false;
    } catch (e) {
      debugPrint('BackgroundAudioService stop failed: $e');
    }
  }
}
