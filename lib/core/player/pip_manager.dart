import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/player/encrypted_playback.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/player/player_page.dart';

class _PipEpisode {
  _PipEpisode(this.index, this.source, this.playable, this.media);

  final int index;
  final PlaybackPlan source;
  final PlaybackPlan playable;
  final EncryptedPlayback media;

  Future<void> dispose(AppRepository repository) async {
    await media.close().catchError((Object _) {});
    await repository.release(source.session).catchError((Object _) {});
  }
}

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
  Future<void> Function()? _releasePlaybackResource;

  int _quality = 0;
  double _speed = 1;
  bool _localOnly = false;
  bool _advancing = false;
  int _advanceGeneration = 0;
  _PipEpisode? _currentEpisode;
  Future<_PipEpisode>? _nextEpisode;
  int? _nextEpisodeIndex;

  void Function(int positionMs)? _onRestoreCurrentPlayer;
  void Function(bool active, String? error, int? position)?
  _onPictureInPictureStatusChanged;
  void Function(int episodeIndex)? _onEpisodeAdvanced;

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

  void retainPlaybackResource(Future<void> Function() release) {
    _clearPlaybackResource();
    _releasePlaybackResource = release;
  }

  void _clearPlaybackResource() {
    final release = _releasePlaybackResource;
    _releasePlaybackResource = null;
    if (release != null) unawaited(release().catchError((Object _) {}));
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
    void Function(int episodeIndex)? onEpisodeAdvanced,
    int quality = 0,
    double speed = 1,
    bool localOnly = false,
  }) {
    if (_detail?.drama.id != detail.drama.id ||
        _episodeIndex != episodeIndex) {
      _resetAdvance();
    }
    _detail = detail;
    _episodeIndex = episodeIndex;
    _quality = quality;
    _speed = speed;
    _localOnly = localOnly;
    _isPlayerActive = true;
    _onRestoreCurrentPlayer = onRestoreCurrentPlayer;
    _onPictureInPictureStatusChanged = onPictureInPictureStatusChanged;
    _onEpisodeAdvanced = onEpisodeAdvanced;
    AppDevice.channel.setMethodCallHandler(_handleMethodCall);
  }

  /// 当播放器页面被销毁时标记界面退出，但保留剧集元数据以便小窗点击恢复时可重新打开
  void notifyPlayerDisposed() {
    _isPlayerActive = false;
    _onRestoreCurrentPlayer = null;
    _onPictureInPictureStatusChanged = null;
    _onEpisodeAdvanced = null;
  }

  /// 画中画彻底关闭（小窗被关闭或播放结束）
  void notifyPictureInPictureStopped() {
    _clearPlaybackResource();
    _resetAdvance();
    _detail = null;
    _episodeIndex = 0;
    _isPlayerActive = false;
    _onRestoreCurrentPlayer = null;
    _onPictureInPictureStatusChanged = null;
    _onEpisodeAdvanced = null;
  }

  bool get _autoAdvanceEnabled =>
      _store?.playbackPreferences.autoAdvance ?? true;

  void _resetAdvance() {
    _advanceGeneration++;
    final repository = _repository;
    final current = _currentEpisode;
    final next = _nextEpisode;
    _currentEpisode = null;
    _nextEpisode = null;
    _nextEpisodeIndex = null;
    if (repository == null) return;
    if (current != null) unawaited(current.dispose(repository));
    if (next != null) {
      unawaited(
        next
            .then((episode) => episode.dispose(repository))
            .catchError((Object _) {}),
      );
    }
  }

  Future<_PipEpisode> _buildEpisode(int index) async {
    final detail = _detail;
    final repository = _repository;
    if (detail == null || repository == null) {
      throw AppFailure('画中画剧集信息已失效', code: 'pip_context');
    }
    final episode = detail.episodes[index];
    final media = EncryptedPlayback();
    PlaybackPlan? source;
    try {
      source = _localOnly
          ? await repository.localPlayback(detail.drama, episode)
          : await repository.resolve(
              detail.drama,
              episode,
              quality: _quality,
            );
      if (source == null || source.url.isEmpty) {
        throw AppFailure('未获取到下一集播放地址', code: 'pip_next');
      }
      final playable = source.decryptionKey.isNotEmpty
          ? await media.prepare(source, forceCache: true)
          : source;
      return _PipEpisode(index, source, playable, media);
    } catch (_) {
      await media.close().catchError((Object _) {});
      if (source != null) {
        await repository.release(source.session).catchError((Object _) {});
      }
      rethrow;
    }
  }

  void _prefetchNextEpisode() {
    if (!Platform.isIOS || !_autoAdvanceEnabled) return;
    final detail = _detail;
    final repository = _repository;
    if (detail == null || repository == null) return;
    final next = _episodeIndex + 1;
    if (next >= detail.episodes.length || _nextEpisodeIndex == next) return;
    final generation = _advanceGeneration;
    final future = _buildEpisode(next);
    _nextEpisode = future;
    _nextEpisodeIndex = next;
    unawaited(
      future.then<void>(
        (episode) async {
          if (generation != _advanceGeneration) {
            await episode.dispose(repository);
          }
        },
        onError: (Object error) {
          if (generation == _advanceGeneration &&
              identical(_nextEpisode, future)) {
            _nextEpisode = null;
            _nextEpisodeIndex = null;
          }
          DiaryService.add('[PiP] 预备下一集失败: 集=${next + 1}, $error');
        },
      ),
    );
  }

  Future<_PipEpisode> _takeEpisode(int index) async {
    final pending = _nextEpisodeIndex == index ? _nextEpisode : null;
    _nextEpisode = null;
    _nextEpisodeIndex = null;
    if (pending != null) {
      try {
        return await pending;
      } catch (_) {}
    }
    return _buildEpisode(index);
  }

  Future<void> _advanceToNextEpisode() async {
    final detail = _detail;
    final repository = _repository;
    if (_advancing ||
        detail == null ||
        repository == null ||
        !_autoAdvanceEnabled) {
      return;
    }
    final next = _episodeIndex + 1;
    if (next >= detail.episodes.length) return;
    _advancing = true;
    final generation = _advanceGeneration;
    try {
      final episode = await _takeEpisode(next);
      if (generation != _advanceGeneration) {
        await episode.dispose(repository);
        return;
      }
      final status = await AppDevice.channel
          .invokeMapMethod<String, dynamic>('replacePictureInPictureItem', {
            'url': episode.playable.url,
            if (episode.playable.headers.isNotEmpty)
              'headers': episode.playable.headers,
            'episodeIndex': next,
            'speed': _speed,
          });
      if (status?['replaced'] != true || generation != _advanceGeneration) {
        await episode.dispose(repository);
        return;
      }
      final previous = _currentEpisode;
      _currentEpisode = episode;
      _episodeIndex = next;
      if (previous != null) unawaited(previous.dispose(repository));
      DiaryService.add(
        '[PiP] 自动播放下一集: 剧=${detail.drama.cleanSourceId}, 集=${detail.episodes[next].number}',
      );
      _onEpisodeAdvanced?.call(next);
      _prefetchNextEpisode();
    } catch (error) {
      DiaryService.add('[PiP] 自动播放下一集失败: 集=${next + 1}, $error');
    } finally {
      _advancing = false;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'pipLog') {
      debugPrint('[PiP-Native] ${call.arguments}');
      return true;
    }

    if (call.method == 'pictureInPictureEnded') {
      unawaited(_advanceToNextEpisode());
      return true;
    }

    if (call.method == 'pictureInPictureItemFailed') {
      final arguments = call.arguments;
      final error = arguments is Map ? arguments['error'] : null;
      DiaryService.add('[PiP] 下一集加载失败: $error');
      return true;
    }

    if (call.method == 'pictureInPictureChanged') {
      final arguments = call.arguments;
      final active = arguments is Map && arguments['active'] == true;
      final error = arguments is Map ? arguments['error'] as String? : null;
      final position = arguments is Map
          ? (arguments['position'] as num?)?.toInt()
          : null;

      if (active) {
        _prefetchNextEpisode();
      } else {
        _clearPlaybackResource();
        _resetAdvance();
        if (!_isPlayerActive) {
          _detail = null;
        }
      }
      _onPictureInPictureStatusChanged?.call(active, error, position);
      return true;
    }

    if (call.method == 'restorePictureInPictureUI') {
      final arguments = call.arguments;
      final position = arguments is Map
          ? (arguments['position'] as num?)?.toInt() ?? 0
          : 0;
      final episodeIdx = arguments is Map
          ? (arguments['episodeIndex'] as num?)?.toInt()
          : null;
      final rawDetail = arguments is Map && arguments['detail'] is Map
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

      if (restoreDetail != null &&
          repo != null &&
          currentStore != null &&
          nav != null) {
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
              playerFactory: playerFactory != null
                  ? () => playerFactory!()
                  : null,
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
