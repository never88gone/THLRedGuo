import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HongguoPlaybackProfile {
  static const _channel = MethodChannel('duanju/device');
  static int _revision = 0;
  static Map<String, dynamic>? _runtime;
  static Future<Map<String, dynamic>?>? _loading;
  static String _summary = '尚未读取';

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static int get revision => _revision;
  static String get diagnosticSummary => _summary;

  static void _recordMetadata(Map<String, dynamic>? value) {
    final version = value?['appVersion'];
    _summary =
        value?['imported'] == true &&
            version is String &&
            RegExp(r'^[0-9.]{1,32}$').hasMatch(version)
        ? '已导入红果 $version · 仅本机存储'
        : '未导入';
  }

  static Future<Map<String, dynamic>> metadata() async {
    if (!supported) return {'supported': false, 'imported': false};
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'hongguoPlaybackProfileMetadata',
    );
    _recordMetadata(value);
    return {'supported': true, ...?value};
  }

  static Future<Map<String, dynamic>?> runtimeConfiguration() async {
    if (!supported) return null;
    if (_runtime != null) return Map.of(_runtime!);
    final pending = _loading;
    if (pending != null) return pending;
    final revision = _revision;
    final future = () async {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'hongguoPlaybackProfileRuntime',
      );
      if (value?['configuration'] is! String) {
        _recordMetadata(value);
        return null;
      }
      if (revision != _revision) return runtimeConfiguration();
      _runtime = Map<String, dynamic>.of(value!);
      _recordMetadata({'imported': true, 'appVersion': value['appVersion']});
      return Map<String, dynamic>.of(value);
    }();
    _loading = future;
    try {
      return await future;
    } catch (_) {
      _summary = '暂不可访问';
      rethrow;
    } finally {
      if (identical(_loading, future)) _loading = null;
    }
  }

  static Future<Map<String, dynamic>> importApk(String path) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'importHongguoPlaybackApk',
      {'path': path},
    );
    _invalidate();
    _recordMetadata(value);
    return Map<String, dynamic>.of(value ?? {'imported': false});
  }

  static Future<void> remove() async {
    await _channel.invokeMethod<void>('removeHongguoPlaybackProfile');
    _invalidate();
    _summary = '未导入';
  }

  static void _invalidate() {
    _revision++;
    _runtime = null;
    _loading = null;
  }
}
