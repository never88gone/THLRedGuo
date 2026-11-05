import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/js/js_source_models.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';

class JsSourceService extends ChangeNotifier {
  JsSourceService(this._repository, [this._preferences]) {
    current = this;
  }

  static JsSourceService? current;
  static const _activeSourceKey = 'active_js_source_id';
  final AppRepository _repository;
  SharedPreferences? _preferences;
  List<JsSourceMeta> _sources = [];
  String _activeSourceId = '';
  bool _initialized = false;
  bool _disposed = false;
  int _pendingOperations = 0;
  Future<void>? _initializing;

  List<JsSourceMeta> get sources => List.unmodifiable(_sources);
  String get activeSourceId => _activeSourceId;
  bool get initialized => _initialized;
  bool get loading => _pendingOperations > 0;
  JsSourceMeta? get activeSource =>
      _sources.where((source) => source.id == _activeSourceId).firstOrNull ??
      _sources.firstOrNull;

  Future<T> _withLoading<T>(Future<T> Function() operation) async {
    if (_disposed) throw StateError('数据源管理已关闭');
    _pendingOperations++;
    notifyListeners();
    try {
      return await operation();
    } finally {
      _pendingOperations--;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _withLoading(() async {
      unawaited(CatPawJsRuntime.preloadDeviceSession());
      await _repository.jsSourceScan();
      _sources = await _repository.jsSourceList();
      for (final preset in kPresetJsSources) {
        final script = await preset.loadScript();
        if (_sources.any(
          (source) =>
              source.id == preset.id &&
              JsSourceMeta.isVersionNewer(
                source.version,
                JsSourceMeta.scriptVersion(script),
              ),
        )) {
          continue;
        }
        if (!await _repository.jsSourceSaveAndLoad(script, preset.fileName)) {
          throw StateError('内置数据源导入失败，请重试');
        }
      }
      _sources = await _repository.jsSourceList();
      _preferences ??= await SharedPreferences.getInstance();
      var saved = _preferences?.getString(_activeSourceKey) ?? '';
      if (!_sources.any((source) => source.id == saved)) {
        saved = _sources.firstOrNull?.id ?? '';
      }
      if (saved.isNotEmpty && !await _repository.jsSourceSetActive(saved)) {
        throw StateError('数据源启用失败，请重试');
      }
      _activeSourceId = saved;
      _initialized = true;
    }).whenComplete(() => _initializing = null);
  }

  Future<bool> switchSource(String sourceId) async {
    if (_activeSourceId == sourceId) return true;
    if (!_sources.any((source) => source.id == sourceId)) return false;
    return _withLoading(() async {
      final ok = await _repository.jsSourceSetActive(sourceId);
      if (ok) {
        _activeSourceId = sourceId;
        _preferences ??= await SharedPreferences.getInstance();
        await _preferences?.setString(_activeSourceKey, sourceId);
      }
      return ok;
    });
  }

  Future<bool> importScript(String script, String fileName) =>
      _withLoading(() async {
        final ok = await _repository.jsSourceSaveAndLoad(script, fileName);
        if (ok) {
          _sources = await _repository.jsSourceList();
          if (!_sources.any((source) => source.id == _activeSourceId) &&
              _sources.isNotEmpty) {
            await switchSource(_sources.first.id);
          }
        }
        return ok;
      });

  Future<bool> importFromUrl(String url) => _withLoading(() async {
    HttpClient? client;
    try {
      final uri = Uri.parse(url.trim());
      if (!{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        return false;
      }
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Mozilla/5.0 THLRedLook/1.0.0');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.contentLength > 4 * 1024 * 1024) {
        return false;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > 4 * 1024 * 1024) {
          throw const FormatException('数据源脚本超过大小限制');
        }
        bytes.add(chunk);
      }
      final script = utf8.decode(bytes.takeBytes());
      if (script.trim().isEmpty) return false;
      var fileName = uri.pathSegments.lastOrNull ?? 'remote_source.js';
      if (!fileName.toLowerCase().endsWith('.js')) fileName = '$fileName.js';
      return await importScript(script, fileName);
    } on Exception {
      return false;
    } finally {
      client?.close(force: true);
    }
  });

  Future<bool> removeSource(String sourceId) => _withLoading(() async {
    if (_activeSourceId == sourceId) {
      final other = _sources
          .where((source) => source.id != sourceId)
          .firstOrNull;
      if (other != null) await switchSource(other.id);
    }
    final ok = await _repository.jsSourceRemove(sourceId);
    if (ok) {
      _sources = await _repository.jsSourceList();
      if (!_sources.any((source) => source.id == _activeSourceId)) {
        _activeSourceId = _sources.firstOrNull?.id ?? '';
        _preferences ??= await SharedPreferences.getInstance();
        if (_activeSourceId.isEmpty) {
          await _preferences?.remove(_activeSourceKey);
        } else {
          await _preferences?.setString(_activeSourceKey, _activeSourceId);
        }
      }
    }
    return ok;
  });

  Future<void> reload() => _withLoading(() async {
    await _repository.jsSourceScan();
    _sources = await _repository.jsSourceList();
    _activeSourceId = await _repository.jsSourceGetActive();
  });

  Future<void> clearAll() => _withLoading(() async {
    if (!await _repository.jsSourceClearAll()) {
      throw StateError('数据源清理失败，请重试');
    }
    _sources = [];
    _activeSourceId = '';
    _preferences ??= await SharedPreferences.getInstance();
    await _preferences?.remove(_activeSourceKey);
  });

  @override
  void dispose() {
    _disposed = true;
    if (identical(current, this)) current = null;
    super.dispose();
  }
}
