import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;

import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';

class HawCastService extends ChangeNotifier {
  HawCastService._();

  static final HawCastService instance = HawCastService._();

  static const String serviceType = '_thl-cast._tcp';
  static const int defaultPort = 18188;
  static const Duration _requestTimeout = Duration(seconds: 6);

  final http.Client _client = http.Client();
  final Map<String, HawCastDevice> _manualDevices = {};
  final Map<String, HawCastDevice> _discoveredDevices = {};

  nsd.Discovery? _discovery;
  Timer? _statusTimer;
  int _scanGeneration = 0;

  bool _scanning = false;
  String? _scanError;
  HawCastDevice? _activeDevice;
  String _activeSessionId = '';
  String _activeTitle = '';
  String _activeDramaTitle = '';
  int _activeEpisodeIndex = 0;
  HawCastStatus _status = const HawCastStatus();
  bool _casting = false;

  bool get scanning => _scanning;
  String? get scanError => _scanError;
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
    if (notify) {
      notifyListeners();
    }
  }

  void _onServicesChanged() {
    final services = _discovery?.services ?? const <nsd.Service>[];
    final nextMap = <String, HawCastDevice>{};

    for (final service in services) {
      final port = service.port ?? defaultPort;
      if (port <= 0) continue;

      final host = _pickBestHost(service);
      if (host == null || host.isEmpty) continue;

      final txt = service.txt ?? const {};
      String readTxt(String key) {
        final raw = txt[key];
        if (raw == null || raw.isEmpty) return '';
        return utf8.decode(raw, allowMalformed: true).trim();
      }

      final proto = readTxt('proto');
      if (proto.isNotEmpty && proto != 'haw') continue;

      final rawName = service.name?.trim() ?? '';
      final name = rawName.isNotEmpty ? rawName : '糖葫芦接收器 ($host)';
      final model = readTxt('model').isNotEmpty ? readTxt('model') : 'THLPlay';
      final capsStr = readTxt('caps');
      final caps = capsStr.isNotEmpty
          ? capsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : const ['aes128', 'hls', 'mp4'];

      final id = '$host:$port';
      nextMap[id] = HawCastDevice(
        id: id,
        name: name,
        host: host,
        port: port,
        model: model,
        caps: caps,
      );
    }

    _discoveredDevices
      ..clear()
      ..addAll(nextMap);
    notifyListeners();
  }

  String? _pickBestHost(nsd.Service service) {
    final addrs = service.addresses ?? const <InternetAddress>[];
    String? fallbackIpv6;
    for (final addr in addrs) {
      if (addr.isLoopback) continue;
      if (addr.type == InternetAddressType.IPv4) {
        return addr.address;
      }
      if (!addr.isLinkLocal && fallbackIpv6 == null) {
        fallbackIpv6 = addr.address;
      }
    }
    if (fallbackIpv6 != null) return fallbackIpv6;
    final host = service.host?.trim();
    if (host != null && host.isNotEmpty) {
      return host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    }
    return null;
  }

  Future<HawCastDevice?> probeManualDevice(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    var host = trimmed;
    var port = defaultPort;
    if (trimmed.startsWith('[')) {
      final endBracket = trimmed.indexOf(']');
      if (endBracket > 1) {
        host = trimmed.substring(1, endBracket);
        if (endBracket + 1 < trimmed.length && trimmed[endBracket + 1] == ':') {
          port = int.tryParse(trimmed.substring(endBracket + 2)) ?? defaultPort;
        }
      }
    } else if (trimmed.contains(':') && trimmed.indexOf(':') == trimmed.lastIndexOf(':')) {
      final parts = trimmed.split(':');
      host = parts[0].trim();
      port = int.tryParse(parts[1].trim()) ?? defaultPort;
    }

    if (host.isEmpty) return null;
    final formattedHost = host.contains(':') ? '[$host]' : host;
    final uri = Uri.parse('http://$formattedHost:$port/thl/info');

    try {
      final response = await _client.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;

      final name = decoded['name']?.toString().trim();
      final model = decoded['model']?.toString().trim();
      final capsRaw = decoded['caps'];
      final caps = capsRaw is List
          ? capsRaw.map((e) => e.toString()).toList()
          : const ['aes128', 'hls', 'mp4'];

      final device = HawCastDevice(
        id: '$host:$port',
        name: (name != null && name.isNotEmpty) ? name : '糖葫芦接收器 ($host)',
        host: host,
        port: port,
        model: (model != null && model.isNotEmpty) ? model : 'THLPlay',
        caps: caps,
        manual: true,
      );
      _manualDevices[device.id] = device;
      notifyListeners();
      return device;
    } catch (e) {
      DiaryService.add('[Cast] 手动探测 $host:$port 失败: $e');
      return null;
    }
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

      final sessionId = body['session_id']?.toString() ?? request.sessionId;
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

  Future<bool> sendControl(
    HawCastControlCommand command, {
    double? position,
    double? rate,
    double? volume,
  }) async {
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
        if (command == HawCastControlCommand.play) {
          _status = HawCastStatus(
            sessionId: _status.sessionId,
            mediaId: _status.mediaId,
            state: HawCastPlayState.playing,
            position: _status.position,
            duration: _status.duration,
            volume: _status.volume,
            rate: _status.rate,
          );
        } else if (command == HawCastControlCommand.pause) {
          _status = HawCastStatus(
            sessionId: _status.sessionId,
            mediaId: _status.mediaId,
            state: HawCastPlayState.paused,
            position: _status.position,
            duration: _status.duration,
            volume: _status.volume,
            rate: _status.rate,
          );
        } else if (command == HawCastControlCommand.seek && position != null) {
          _status = HawCastStatus(
            sessionId: _status.sessionId,
            mediaId: _status.mediaId,
            state: _status.state,
            position: position,
            duration: _status.duration,
            volume: _status.volume,
            rate: _status.rate,
          );
        } else if (command == HawCastControlCommand.volume && volume != null) {
          _status = HawCastStatus(
            sessionId: _status.sessionId,
            mediaId: _status.mediaId,
            state: _status.state,
            position: _status.position,
            duration: _status.duration,
            volume: volume,
            rate: _status.rate,
          );
        }
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopCasting({bool notifyRemote = true}) async {
    _statusTimer?.cancel();
    _statusTimer = null;
    if (notifyRemote && _activeDevice != null && _casting) {
      await sendControl(HawCastControlCommand.stop);
    }
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
    if (device == null || !_casting) return;
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
