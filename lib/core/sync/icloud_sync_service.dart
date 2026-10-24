import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';

/// 跨苹果生态 (iOS / macOS / tvOS) 原生 iCloud 键值同步服务
class ICloudSyncService extends ChangeNotifier {
  ICloudSyncService._();
  static final ICloudSyncService instance = ICloudSyncService._();

  static const MethodChannel _channel = MethodChannel('duanju/icloud');

  static const String keyHistory = 'thl_icloud_sync_v1_history';
  static const String keyFollows = 'thl_icloud_sync_v1_follows';
  static const String keySettings = 'thl_icloud_sync_v1_settings';
  static const String keyMeta = 'thl_icloud_sync_v1_meta';
  static const String prefSyncEnabled = 'thl_icloud_sync_enabled';
  static const String prefLastSyncDate = 'thl_icloud_last_sync_date';

  bool _initialized = false;
  bool _isSyncing = false;
  DateTime? _lastSyncDate;
  String _lastStatusMessage = '未开启';
  Timer? _debounceTimer;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncDate => _lastSyncDate;
  String get lastStatusMessage => _lastStatusMessage;

  bool isSyncEnabled(SharedPreferences prefs) =>
      prefs.getBool(prefSyncEnabled) ?? false;

  void initialize(LocalStore store) {
    if (_initialized || !isSupported) return;
    _initialized = true;

    final timestamp = store.preferences.getInt(prefLastSyncDate);
    if (timestamp != null && timestamp > 0) {
      _lastSyncDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      _lastStatusMessage = '就绪';
    } else {
      _lastStatusMessage = isSyncEnabled(store.preferences) ? '就绪' : '未开启';
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onICloudChanged') {
        if (isSyncEnabled(store.preferences)) {
          debugPrint('☁️ [iCloud] 收到原生外部数据变动通知，触发云端同步合并...');
          await syncWithCloud(store);
        }
      }
    });

    if (isSyncEnabled(store.preferences)) {
      Future.delayed(const Duration(milliseconds: 800), () {
        syncWithCloud(store);
      });
    }
  }

  Future<void> setSyncEnabled(bool enabled, LocalStore store) async {
    await store.preferences.setBool(prefSyncEnabled, enabled);
    _lastStatusMessage = enabled ? '正在同步...' : '已停用';
    notifyListeners();
    if (enabled) {
      await syncWithCloud(store);
    }
  }

  /// 执行双向数据同步：拉取云端、合并冲突并回写最新数据
  Future<void> syncWithCloud(LocalStore store) async {
    if (!isSupported || !isSyncEnabled(store.preferences) || _isSyncing) return;

    _isSyncing = true;
    _lastStatusMessage = '正在同步...';
    notifyListeners();

    try {
      await _channel.invokeMethod('synchronize');

      // 1. 获取远端观看记录 (History)
      final historyRaw = await _channel.invokeMethod<String>('getString', {'key': keyHistory});
      final List<WatchEntry> remoteHistory = [];
      if (historyRaw != null && historyRaw.isNotEmpty) {
        try {
          final list = jsonDecode(historyRaw) as List;
          for (final item in list) {
            remoteHistory.add(WatchEntry.fromJson(Map<String, dynamic>.from(item as Map)));
          }
        } catch (e) {
          debugPrint('解析云端历史记录异常: $e');
        }
      }

      // 2. 获取远端追剧信息 (Follows)
      final followsRaw = await _channel.invokeMethod<String>('getString', {'key': keyFollows});
      final Map<String, FollowState> remoteFollows = {};
      final List<Drama> remoteDramas = [];
      if (followsRaw != null && followsRaw.isNotEmpty) {
        try {
          final map = jsonDecode(followsRaw) as Map<String, dynamic>;
          if (map['follows'] is Map) {
            final fMap = map['follows'] as Map;
            for (final entry in fMap.entries) {
              final key = entry.key.toString();
              if (entry.value is String) {
                final statusStr = (entry.value as String).toLowerCase();
                FollowStatus status;
                if (statusStr == 'watching') {
                  status = FollowStatus.watching;
                } else if (statusStr == 'watched' ||
                    statusStr == 'finished' ||
                    statusStr == 'completed') {
                  status = FollowStatus.watched;
                } else {
                  status = FollowStatus.planned;
                }
                remoteFollows[key] = FollowState(status: status);
              } else if (entry.value is Map) {
                try {
                  remoteFollows[key] = FollowState.fromJson(
                    Map<String, dynamic>.from(entry.value as Map),
                  );
                } catch (_) {}
              }
            }
          }
          if (map['dramas'] is List) {
            for (final d in map['dramas'] as List) {
              remoteDramas.add(Drama.fromJson(Map<String, dynamic>.from(d as Map)));
            }
          }
        } catch (e) {
          debugPrint('解析云端追剧信息异常: $e');
        }
      }

      // 3. 获取远端配置项 (Settings)
      final settingsRaw = await _channel.invokeMethod<String>('getString', {'key': keySettings});
      String? remoteSource;
      bool? remoteDanmaku;
      if (settingsRaw != null && settingsRaw.isNotEmpty) {
        try {
          final sMap = jsonDecode(settingsRaw) as Map<String, dynamic>;
          remoteSource = sMap['source'] as String?;
          remoteDanmaku = sMap['danmaku'] as bool?;
        } catch (e) {
          debugPrint('解析云端配置项异常: $e');
        }
      }

      // 4. 双向合并逻辑
      // 4.1 合并观看记录：同一剧集保留 updatedAt 较新者
      final Map<String, WatchEntry> mergedHistory = {};
      for (final local in store.history) {
        mergedHistory[local.drama.id] = local;
      }
      for (final remote in remoteHistory) {
        final id = remote.drama.id;
        final local = mergedHistory[id];
        if (local == null || remote.updatedAt.isAfter(local.updatedAt)) {
          mergedHistory[id] = remote;
        }
      }
      final sortedHistory = mergedHistory.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // 4.2 合并追剧列表
      final Map<String, Drama> mergedFavorites = {};
      for (final local in store.favorites) {
        mergedFavorites[local.id] = local;
      }
      for (final remote in remoteDramas) {
        mergedFavorites[remote.id] = remote;
      }

      final Map<String, FollowState> mergedStates = {};
      for (final id in mergedFavorites.keys) {
        final localState = store.following(id);
        final remoteState = remoteFollows[id];
        if (localState != null && remoteState != null) {
          // 以较高级别的状态为准
          mergedStates[id] = localState.status.index >= remoteState.status.index
              ? localState
              : remoteState;
        } else {
          mergedStates[id] = localState ??
              remoteState ??
              FollowState.initial(
                mergedFavorites[id]!,
                store.watched(id),
              );
        }
      }

      // 4.3 合并设置项
      PlaybackPreferences? updatedPlayback;
      if (remoteDanmaku != null && remoteDanmaku != store.playbackPreferences.danmaku) {
        updatedPlayback = store.playbackPreferences.copyWith(danmaku: remoteDanmaku);
      }

      // 5. 应用合并结果到本地 LocalStore
      await store.applySyncedICloudData(
        history: sortedHistory,
        favorites: mergedFavorites,
        followStates: mergedStates,
        source: remoteSource,
        playback: updatedPlayback,
      );

      // 6. 回写云端（确保云端也是最新的合并结果）
      await _channel.invokeMethod('setString', {
        'key': keyHistory,
        'value': jsonEncode(sortedHistory.take(300).map((e) => e.toJson()).toList()),
      });

      final followsPayload = {
        'follows': {for (final e in mergedStates.entries) e.key: e.value.status.name},
        'dramas': mergedFavorites.values.map((d) => d.toJson()).toList(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
      await _channel.invokeMethod('setString', {
        'key': keyFollows,
        'value': jsonEncode(followsPayload),
      });

      final settingsPayload = {
        'source': store.source,
        'danmaku': store.playbackPreferences.danmaku,
        'speed': store.playbackPreferences.speed,
        'quality': store.playbackPreferences.quality,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
      await _channel.invokeMethod('setString', {
        'key': keySettings,
        'value': jsonEncode(settingsPayload),
      });

      final metaPayload = {
        'device': defaultTargetPlatform == TargetPlatform.iOS ? 'iOS' : 'macOS',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await _channel.invokeMethod('setString', {
        'key': keyMeta,
        'value': jsonEncode(metaPayload),
      });

      await _channel.invokeMethod('synchronize');

      _lastSyncDate = DateTime.now();
      await store.preferences.setInt(prefLastSyncDate, _lastSyncDate!.millisecondsSinceEpoch);
      _lastStatusMessage = '已同步 (${sortedHistory.length}条记录, ${mergedFavorites.length}部追剧)';
    } catch (e) {
      debugPrint('iCloud 同步失败: $e');
      _lastStatusMessage = '同步遇到异常，稍后重试';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// 本地数据变动时防抖上传
  void scheduleUpload(LocalStore store) {
    if (!isSupported || !isSyncEnabled(store.preferences)) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      syncWithCloud(store);
    });
  }
}
