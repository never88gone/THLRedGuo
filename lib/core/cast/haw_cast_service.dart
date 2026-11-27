import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;

import 'package:THLRedLook/core/cast/airplay_cast_controller.dart';
import 'package:THLRedLook/core/cast/haw_cast_discovery.dart';
import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';

class HawCastService extends ChangeNotifier {
  HawCastService._() {
    _airPlay = AirPlayCastController(
      onActivated: _handleAirPlayActivated,
      onDeactivated: _handleAirPlayDeactivated,
      onStatusUpdated: _handleAirPlayStatus,
      onEnded: (idx) => onExternalCastEnded?.call(idx),
      onError: (msg) => DiaryService.add('[Cast-AirPlay] 异常: $msg'),
    );
  }

  static final HawCastService instance = HawCastService._();

  static const String serviceType = '_thl-cast._tcp';
  static const int defaultPort = 18188;
  static const Duration _requestTimeout = Duration(seconds: 6);

  final http.Client _client = http.Client();
  final Map<String, HawCastDevice> _manualDevices = {};
  final Map<String, HawCastDevice> _discoveredDevices = {};
  late final AirPlayCastController _airPlay;

  nsd.Discovery? _discovery;
  Timer? _statusTimer;
  int _scanGeneration = 0;

  bool _scanning = false;
  String? _scanError;
  CastProtocolMode _mode = CastProtocolMode.none;
  HawCastDevice? _activeDevice;
  String _activeSessionId = '';
  String _activeTitle = '';
  String _activeDramaTitle = '';
  int _activeEpisodeIndex = 0;
  HawCastStatus _status = const HawCastStatus();
  bool _casting = false;

  VoidCallback? onExternalCastActivated;
  void Function(double resumePosition)? onExternalCastStopped;
  void Function(int episodeIndex)? onExternalCastEnded;

  bool get scanning => _scanning;
  String? get scanError => _scanError;
  CastProtocolMode get mode => _mode;
  bool get isAirPlaySupported => _airPlay.isAvailable;
  HawCastDevice? get activeDevice => _activeDevice;
  String get activeSessionId => _activeSessionId;
  String get activeTitle => _activeTitle;
  String get activeDramaTitle => _activeDramaTitle;
  int get activeEpisodeIndex => _activeEpisodeIndex;
  HawCastStatus get status => _status;
  bool get isCasting => _casting && _activeDevice != null;

  List<HawCastDevice> get devices {
    final merged = <String, HawCastDevice>{
      ..._discoveredDevices,
      ..._manualDevices,
    };
    final list = merged.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  String generateSessionId() {
    final rng = Random.secure();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final randPart = List.generate(
      8,
      (_) => rng.nextInt(16).toRadixString(16),
    ).join();
    return 'haw_$ts$randPart';
  }

  Future<void> startDiscovery() async {
    final generation = ++_scanGeneration;
    await stopDiscovery(notify: false);
    _scanning = true;
    _scanError = null;
    notifyListeners();

    try {
      final discovery = await nsd.startDiscovery(
        serviceType,
        ipLookupType: nsd.IpLookupType.any,
      );
      if (generation != _scanGeneration) {
        await nsd.stopDiscovery(discovery).catchError((Object _) {});
        return;
      }
      _discovery = discovery;
      discovery.addListener(_onServicesChanged);
      _onServicesChanged();
    } catch (e) {
      if (generation == _scanGeneration) {
        _scanning = false;
        _scanError = '未能启动自动扫描，可点击刷新重试或手动输入接收端 IP';
        DiaryService.add('[Cast] nsd 启动扫描失败: $e');
        notifyListeners();
      }
    }
  }

  Future<void> stopDiscovery({bool notify = true}) async {
    final prev = _discovery;
    _discovery = null;
    _scanning = false;
    if (prev != null) {
      prev.removeListener(_onServicesChanged);
      await nsd.stopDiscovery(prev).catchError((Object _) {});
    }
    if (notify) notifyListeners();
  }

  void _onServicesChanged() {
    final parsed = HawCastDiscoveryHelper.parseServices(
      _discovery?.services ?? const <nsd.Service>[],
      defaultPort: defaultPort,
    );
    _discoveredDevices
      ..clear()
      ..addAll(parsed);
    notifyListeners();
  }

  Future<HawCastDevice?> probeManualDevice(String input) async {
    final device = await HawCastDiscoveryHelper.probeManualDevice(
      _client,
      input,
      defaultPort: defaultPort,
      timeout: _requestTimeout,
    );
    if (device != null) {
      _manualDevices[device.id] = device;
      notifyListeners();
    }
    return device;
  }

  Future<bool> startCasting(
    HawCastDevice device,
    HawCastPlayRequest request,
  ) async {
    final uri = Uri.parse('${device.baseUrl}/thl/play');
    try {
      final response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        DiaryService.add(
          '[Cast] 起播 HTTP 失败: ${response.statusCode} ${response.body}',
        );
        return false;
      }

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic> || body['code'] != 0) {
        return false;
      }

      if (_mode == CastProtocolMode.airplay) {
        await _airPlay.stop();
      }
      final sessionId = body['session_id']?.toString() ?? request.sessionId;
      _mode = CastProtocolMode.haw;
      _activeDevice = device;
      _activeSessionId = sessionId;
      _activeTitle = request.title;
      _activeDramaTitle = request.dramaTitle;
      _activeEpisodeIndex = request.episodeIndex;
      _casting = true;
      _status = HawCastStatus(
        sessionId: sessionId,
        mediaId: request.mediaId,
        state: HawCastPlayState.buffering,
        position: request.startPosition,
      );
      _startStatusPolling();
      notifyListeners();
      DiaryService.add(
        '[Cast] 成功推送至 ${device.name}: ${request.dramaTitle} ${request.title} (encrypted=${request.decryptionKey.isNotEmpty})',
      );
      return true;
    } catch (e) {
      DiaryService.add('[Cast] 投屏请求异常: $e');
      return false;
    }
  }

  Future<bool> startAirPlayCast({
    required PlaybackPlan plan,
    required String title,
    required String dramaTitle,
    required int episodeIndex,
    required double startPosition,
    double rate = 1.0,
  }) async {
    if (!_airPlay.isAvailable) return false;
    if (_mode == CastProtocolMode.haw && _casting) {
      await stopCasting(notifyRemote: true);
    }
    _activeTitle = title;
    _activeDramaTitle = dramaTitle;
    _activeEpisodeIndex = episodeIndex;
    return _airPlay.startPicker(
      plan: plan,
      title: title,
      dramaTitle: dramaTitle,
      episodeIndex: episodeIndex,
      position: startPosition,
      rate: rate,
    );
  }

  Future<bool> replaceAirPlayEpisode({
    required PlaybackPlan plan,
    required String title,
    required String dramaTitle,
    required int episodeIndex,
    required double startPosition,
    double rate = 1.0,
  }) async {
    if (!_airPlay.isAvailable || _mode != CastProtocolMode.airplay) {
      return false;
    }
    _activeTitle = title;
    _activeDramaTitle = dramaTitle;
    _activeEpisodeIndex = episodeIndex;
    final ok = await _airPlay.replaceItem(
      plan: plan,
      title: title,
      dramaTitle: dramaTitle,
      episodeIndex: episodeIndex,
      position: startPosition,
      rate: rate,
    );
    if (ok) notifyListeners();
    return ok;
  }

  void _handleAirPlayActivated(String routeName, double position) {
    _statusTimer?.cancel();
    _statusTimer = null;
    _mode = CastProtocolMode.airplay;
    _casting = true;
    _activeSessionId = 'airplay';
    _activeDevice = HawCastDevice(
      id: 'airplay',
      name: routeName,
      host: 'airplay',
      port: 0,
      model: 'AirPlay',
      caps: const ['airplay_video'],
    );
    _status = HawCastStatus(
      sessionId: 'airplay',
      state: HawCastPlayState.playing,
      position: position,
    );
    notifyListeners();
    onExternalCastActivated?.call();
  }

  void _handleAirPlayDeactivated(double lastPosition) {
    if (_mode != CastProtocolMode.airplay) return;
    _mode = CastProtocolMode.none;
    _casting = false;
    _activeDevice = null;
    _activeSessionId = '';
    _status = const HawCastStatus();
    notifyListeners();
    onExternalCastStopped?.call(lastPosition);
  }

  void _handleAirPlayStatus(HawCastStatus nextStatus) {
    if (_mode != CastProtocolMode.airplay || !_casting) return;
    _status = nextStatus;
    notifyListeners();
  }

  Future<bool> sendControl(
    HawCastControlCommand command, {
    double? position,
    double? rate,
    double? volume,
  }) async {
    if (_mode == CastProtocolMode.airplay && _casting) {
      final ok = await _airPlay.sendControl(
        command,
        position: position,
        rate: rate,
        volume: volume,
      );
      if (ok) {
        _applyOptimisticControl(
          command,
          position: position,
          rate: rate,
          volume: volume,
        );
      }
      return ok;
    }

    final device = _activeDevice;
    if (device == null || !_casting) return false;

    final payload = <String, dynamic>{
      'cmd': 'thl_control',
      'session_id': _activeSessionId,
      'action': command.action,
      if (command == HawCastControlCommand.seek && position != null)
        'position': position,
      if (command == HawCastControlCommand.rate && rate != null) 'rate': rate,
      if (command == HawCastControlCommand.volume && volume != null)
        'volume': volume,
    };

    try {
      final uri = Uri.parse('${device.baseUrl}/thl/control');
      final response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) return false;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final ok = body is Map<String, dynamic> && body['code'] == 0;
      if (ok) {
        _applyOptimisticControl(
          command,
          position: position,
          rate: rate,
          volume: volume,
        );
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  void _applyOptimisticControl(
    HawCastControlCommand command, {
    double? position,
    double? rate,
    double? volume,
  }) {
    _status = HawCastStatus(
      sessionId: _status.sessionId,
      mediaId: _status.mediaId,
      state: switch (command) {
        HawCastControlCommand.play => HawCastPlayState.playing,
        HawCastControlCommand.pause => HawCastPlayState.paused,
        _ => _status.state,
      },
      position: (command == HawCastControlCommand.seek && position != null)
          ? position
          : _status.position,
      duration: _status.duration,
      volume: (command == HawCastControlCommand.volume && volume != null)
          ? volume
          : _status.volume,
      rate: (command == HawCastControlCommand.rate && rate != null)
          ? rate
          : _status.rate,
    );
    notifyListeners();
  }

  Future<void> stopCasting({bool notifyRemote = true}) async {
    _statusTimer?.cancel();
    _statusTimer = null;
    if (_mode == CastProtocolMode.airplay) {
      await _airPlay.stop();
    } else if (notifyRemote && _activeDevice != null && _casting) {
      await sendControl(HawCastControlCommand.stop);
    }
    _mode = CastProtocolMode.none;
    _casting = false;
    _activeDevice = null;
    _activeSessionId = '';
    _status = const HawCastStatus();
    notifyListeners();
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollStatus());
    });
  }

  Future<void> _pollStatus() async {
    final device = _activeDevice;
    if (device == null || !_casting || _mode != CastProtocolMode.haw) return;
    try {
      final uri = Uri.parse('${device.baseUrl}/thl/status');
      final response = await _client.get(uri).timeout(
        const Duration(seconds: 3),
      );
      if (response.statusCode != 200 || !_casting) return;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return;
      final nextStatus = HawCastStatus.fromJson(decoded);
      if (nextStatus.sessionId.isNotEmpty &&
          _activeSessionId.isNotEmpty &&
          nextStatus.sessionId != _activeSessionId) {
        return;
      }
      _status = nextStatus;
      notifyListeners();
    } catch (_) {}
  }
}
