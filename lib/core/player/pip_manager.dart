import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/player/player_page.dart';

/// 全局画中画管理器，负责画中画状态监听与小窗恢复时自动跳转回播放器页面
class PipManager {
  PipManager._();
  static final PipManager instance = PipManager._();

  GlobalKey<NavigatorState>? _navigatorKey;
  AppRepository? _repository;
  LocalStore? _store;

  @visibleForTesting
  dynamic Function()? playerFactory;
  @visibleForTesting
  Widget Function(Widget controls)? videoBuilder;

  DramaDetail? _detail;
  int _episodeIndex = 0;
  bool _isPlayerActive = false;

  void Function(int positionMs)? _onRestoreCurrentPlayer;
  void Function(bool active, String? error, int? position)?
      _onPictureInPictureStatusChanged;

  void initialize({
    required GlobalKey<NavigatorState> navigatorKey,
    required AppRepository repository,
    LocalStore? store,
  }) {
    _navigatorKey = navigatorKey;
    _repository = repository;
    _store = store;

    AppDevice.channel.setMethodCallHandler(_handleMethodCall);
  }

  void updateStore(LocalStore? store) {
    _store = store;
  }

  /// 当播放器进入画中画模式时登记当前剧集上下文
  void registerPictureInPictureSession({
    required DramaDetail detail,
    required int episodeIndex,
    required int positionMs,
    required void Function(int positionMs) onRestoreCurrentPlayer,
    required void Function(bool active, String? error, int? position)
        onPictureInPictureStatusChanged,
  }) {
    _detail = detail;
    _episodeIndex = episodeIndex;
    _isPlayerActive = true;
    _onRestoreCurrentPlayer = onRestoreCurrentPlayer;
    _onPictureInPictureStatusChanged = onPictureInPictureStatusChanged;
    AppDevice.channel.setMethodCallHandler(_handleMethodCall);
  }

  /// 当播放器页面被销毁时标记界面退出，但保留剧集元数据以便小窗点击恢复时可重新打开
  void notifyPlayerDisposed() {
    _isPlayerActive = false;
    _onRestoreCurrentPlayer = null;
    _onPictureInPictureStatusChanged = null;
  }

  /// 画中画彻底关闭（小窗被关闭或播放结束）
  void notifyPictureInPictureStopped() {
    _detail = null;
    _episodeIndex = 0;
    _isPlayerActive = false;
    _onRestoreCurrentPlayer = null;
    _onPictureInPictureStatusChanged = null;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'pipLog') {
      debugPrint('[PiP-Native] ${call.arguments}');
      return true;
    }

    if (call.method == 'pictureInPictureChanged') {
      final arguments = call.arguments;
      final active = arguments is Map && arguments['active'] == true;
      final error = arguments is Map ? arguments['error'] as String? : null;
      final position =
          arguments is Map ? (arguments['position'] as num?)?.toInt() : null;

      if (!active) {
        if (!_isPlayerActive) {
          _detail = null;
        }
      }
      _onPictureInPictureStatusChanged?.call(active, error, position);
      return true;
    }

    if (call.method == 'restorePictureInPictureUI') {
      final arguments = call.arguments;
      final position =
          arguments is Map ? (arguments['position'] as num?)?.toInt() ?? 0 : 0;
      final episodeIdx =
          arguments is Map ? (arguments['episodeIndex'] as num?)?.toInt() : null;
      final rawDetail =
          arguments is Map && arguments['detail'] is Map
              ? Map<String, dynamic>.from(arguments['detail'] as Map)
              : null;

      debugPrint(
        '[PiP-Manager] restorePictureInPictureUI received: pos=$position, isPlayerActive=$_isPlayerActive',
      );

      // 1. 如果当前播放器页面还在活跃状态，直接恢复应用内播放
      if (_isPlayerActive && _onRestoreCurrentPlayer != null) {
        _onRestoreCurrentPlayer!(position);
        return true;
      }

      // 2. 如果用户之前已经关闭了播放器页面退到了其他页面，自动跳转回播放器
      DramaDetail? restoreDetail = _detail;
      if (restoreDetail == null && rawDetail != null && rawDetail.isNotEmpty) {
        try {
          restoreDetail = DramaDetail.fromJson(rawDetail);
        } catch (e) {
          debugPrint('[PiP-Manager] parse restore detail error: $e');
        }
      }

      final targetIdx = episodeIdx ?? _episodeIndex;
      final repo = _repository;
      final currentStore = _store;
      final nav = _navigatorKey?.currentState;

      if (restoreDetail != null && repo != null && currentStore != null && nav != null) {
        debugPrint(
          '[PiP-Manager] Pushing PlayerScreen back: drama=${restoreDetail.drama.title}, ep=$targetIdx, pos=$position',
        );
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerScreen(
              detail: restoreDetail!,
              initialIndex: targetIdx,
              initialPosition: position > 0 ? position / 1000.0 : 0.0,
              repository: repo,
              store: currentStore,
              playerFactory: playerFactory != null ? () => playerFactory!() : null,
              videoBuilder: videoBuilder,
            ),
          ),
        );
        return true;
      }

      return false;
    }

    return null;
  }
}
