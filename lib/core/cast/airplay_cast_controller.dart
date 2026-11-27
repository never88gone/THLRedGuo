import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/cast/airplay_media_proxy.dart';
import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/core/player/ios_encrypted_stream.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';

class AirPlayCastController {
  AirPlayCastController({
    required this.onActivated,
    required this.onDeactivated,
    required this.onStatusUpdated,
    required this.onEnded,
    required this.onError,
  }) {
    _channel.setMethodCallHandler(_handleCall);
  }

  static const MethodChannel _channel = MethodChannel('duanju/airplay_cast');

  final void Function(String routeName, double position) onActivated;
  final void Function(double lastPosition) onDeactivated;
  final void Function(HawCastStatus status) onStatusUpdated;
  final void Function(int episodeIndex) onEnded;
  final void Function(String message) onError;

  IosEncryptedStream? _encryptedStream;
  LanMediaFileProxy? _fileProxy;
  bool _isClosingStreams = false;

  bool get isAvailable => !kIsWeb && Platform.isIOS;

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'onAirPlayStateChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        final active = args['active'] == true;
        final pos = (args['position'] as num?)?.toDouble() ?? 0.0;
        final routeName = args['routeName']?.toString().trim() ?? '';
        if (active) {
          onActivated(routeName.isNotEmpty ? routeName : 'AirPlay 设备', pos);
        } else {
          await closeStreams();
          onDeactivated(pos);
        }
        return null;
      case 'airPlayStatus':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        onStatusUpdated(
          HawCastStatus(
            sessionId: 'airplay',
            state: HawCastPlayState.fromCode(
              (args['state'] as num?)?.toInt() ?? 0,
            ),
            position: (args['position'] as num?)?.toDouble() ?? 0.0,
            duration: (args['duration'] as num?)?.toDouble() ?? 0.0,
            volume: (args['volume'] as num?)?.toDouble() ?? 1.0,
            rate: (args['rate'] as num?)?.toDouble() ?? 1.0,
          ),
        );
        return null;
      case 'onAirPlayEnded':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        onEnded((args['episodeIndex'] as num?)?.toInt() ?? 0);
        return null;
      case 'onAirPlayCancelled':
        await closeStreams();
        return null;
      case 'onAirPlayError':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        onError(args['message']?.toString() ?? 'AirPlay 视频投屏失败');
        return null;
      default:
        return null;
    }
  }

  Future<({String url, Map<String, String> headers})> _prepareStream(
    PlaybackPlan plan,
  ) async {
    await closeStreams();
    if (!plan.local &&
        plan.decryptionKey.isEmpty &&
        plan.url.startsWith('http')) {
      return (url: plan.url, headers: plan.headers);
    }
    if (plan.decryptionKey.isNotEmpty) {
      final stream = IosEncryptedStream();
      _encryptedStream = stream;
      final prepared = await stream.openWithOptions(plan, allowLan: true);
      return (url: prepared.url, headers: const <String, String>{});
    }
    if (plan.local) {
      final proxy = LanMediaFileProxy();
      _fileProxy = proxy;
      final lanUrl = await proxy.open(plan.url);
      return (url: lanUrl, headers: const <String, String>{});
    }
    throw AppFailure('当前视频源不支持 AirPlay 投屏');
  }

  Future<bool> startPicker({
    required PlaybackPlan plan,
    required String title,
    required String dramaTitle,
    required int episodeIndex,
    required double position,
    double rate = 1.0,
  }) async {
    if (!isAvailable) return false;
    final stream = await _prepareStream(plan);
    DiaryService.add(
      '[Cast-AirPlay] 准备纯视频流: ep=${episodeIndex + 1}, encrypted=${plan.decryptionKey.isNotEmpty}',
    );
    final triggered = await _channel.invokeMethod<bool>('startAirPlayPicker', {
      'url': stream.url,
      'headers': stream.headers,
      'position': position > 0 ? position : 0.0,
      'rate': rate > 0 ? rate : 1.0,
      'title': title,
      'dramaTitle': dramaTitle,
      'episodeIndex': episodeIndex,
    });
    if (triggered != true) {
      await closeStreams();
      return false;
    }
    return true;
  }

  Future<bool> replaceItem({
    required PlaybackPlan plan,
    required String title,
    required String dramaTitle,
    required int episodeIndex,
    required double position,
    double rate = 1.0,
  }) async {
    if (!isAvailable) return false;
    final stream = await _prepareStream(plan);
    final ok = await _channel.invokeMethod<bool>('replaceItem', {
      'url': stream.url,
      'headers': stream.headers,
      'position': position > 0 ? position : 0.0,
      'rate': rate > 0 ? rate : 1.0,
      'title': title,
      'dramaTitle': dramaTitle,
      'episodeIndex': episodeIndex,
    });
    return ok == true;
  }

  Future<bool> sendControl(
    HawCastControlCommand command, {
    double? position,
    double? rate,
    double? volume,
  }) async {
    if (!isAvailable) return false;
    final args = <String, dynamic>{'action': command.action};
    if (position != null) args['position'] = position;
    if (rate != null) args['rate'] = rate;
    if (volume != null) args['volume'] = volume;
    final ok = await _channel.invokeMethod<bool>('control', args);
    return ok == true;
  }

  Future<void> stop() async {
    if (isAvailable) {
      await _channel.invokeMethod<void>('stop').catchError((Object _) {});
    }
    await closeStreams();
  }

  Future<void> closeStreams() async {
    if (_isClosingStreams) return;
    _isClosingStreams = true;
    try {
      final enc = _encryptedStream;
      _encryptedStream = null;
      await enc?.close().catchError((Object _) {});
      final proxy = _fileProxy;
      _fileProxy = null;
      await proxy?.close().catchError((Object _) {});
    } finally {
      _isClosingStreams = false;
    }
  }
}
