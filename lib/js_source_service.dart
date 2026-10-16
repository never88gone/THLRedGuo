import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_bridge.dart';
import 'js_source_models.dart';
import 'js_source_presets.dart';

class JsSourceService extends ChangeNotifier {
  JsSourceService(this._repository, [this._preferences]) {
    current = this;
  }

  static JsSourceService? current;
  final AppRepository _repository;
  SharedPreferences? _preferences;

  static const String _activeSourceKey = 'active_js_source_id';

  List<JsSourceMeta> _sources = [];
  String _activeSourceId = '';
  bool _initialized = false;
  bool _loading = false;

  List<JsSourceMeta> get sources => List.unmodifiable(_sources);
  String get activeSourceId => _activeSourceId;
  bool get initialized => _initialized;
  bool get loading => _loading;

  JsSourceMeta? get activeSource {
    for (final src in _sources) {
      if (src.id == _activeSourceId) {
        return src;
      }
    }
    return _sources.isNotEmpty ? _sources.first : null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _loading = true;
    notifyListeners();

    try {
      // 扫描本地已导入的 sources 目录
      await _repository.jsSourceScan();

      // 3. 读取所有已加载的源列表
      _sources = await _repository.jsSourceList();

      for (final preset in kPresetJsSources) {
        await _repository.jsSourceSaveAndLoad(preset.script, preset.fileName);
      }
      _sources = await _repository.jsSourceList();

      // 4. 读取用户保存的活跃源偏好
      _preferences ??= await SharedPreferences.getInstance();
      var savedActiveId = _preferences?.getString(_activeSourceKey) ?? '';

      // 验证 savedActiveId 是否依然存在
      if (savedActiveId.isEmpty || !_sources.any((s) => s.id == savedActiveId)) {
        if (_sources.isNotEmpty) {
          savedActiveId = _sources.first.id;
        }
      }

      if (savedActiveId.isNotEmpty) {
        await _repository.jsSourceSetActive(savedActiveId);
        _activeSourceId = savedActiveId;
      }
    } catch (e) {
      debugPrint('初始化 JsSourceService 异常: $e');
    } finally {
      _initialized = true;
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> switchSource(String sourceId) async {
    if (_activeSourceId == sourceId) return true;
    if (!_sources.any((s) => s.id == sourceId)) return false;

    _loading = true;
    notifyListeners();

    final ok = await _repository.jsSourceSetActive(sourceId);
    if (ok) {
      _activeSourceId = sourceId;
      try {
        _preferences ??= await SharedPreferences.getInstance();
        await _preferences?.setString(_activeSourceKey, sourceId);
      } catch (_) {}
    }

    _loading = false;
    notifyListeners();
    return ok;
  }

  Future<bool> importScript(String script, String fileName) async {
    _loading = true;
    notifyListeners();

    final ok = await _repository.jsSourceSaveAndLoad(script, fileName);
    if (ok) {
      _sources = await _repository.jsSourceList();
      if (_sources.isNotEmpty &&
          (_activeSourceId.isEmpty || !_sources.any((s) => s.id == _activeSourceId))) {
        await switchSource(_sources.first.id);
      }
    }

    _loading = false;
    notifyListeners();
    return ok;
  }

  Future<bool> importFromUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return false;

    _loading = true;
    notifyListeners();

    HttpClient? client;
    try {
      final uri = Uri.parse(cleanUrl);
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Mozilla/5.0 THLRedLook/1.0.1');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final script = await response.transform(utf8.decoder).join();
      if (script.trim().isEmpty) return false;

      var fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'remote_source.js';
      if (!fileName.endsWith('.js')) {
        fileName = '$fileName.js';
      }

      return await importScript(script, fileName);
    } catch (e) {
      debugPrint('网络导入插件失败 ($url): $e');
      return false;
    } finally {
      client?.close(force: true);
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> removeSource(String sourceId) async {
    if (_activeSourceId == sourceId) {
      // 不能删除当前活跃源，除非有其他源可切换
      final other = _sources.firstWhere(
        (s) => s.id != sourceId,
        orElse: () => const JsSourceMeta(id: '', name: ''),
      );
      if (other.id.isNotEmpty) {
        await switchSource(other.id);
      }
    }

    _loading = true;
    notifyListeners();

    final ok = await _repository.jsSourceRemove(sourceId);
    if (ok) {
      _sources = await _repository.jsSourceList();
    }

    _loading = false;
    notifyListeners();
    return ok;
  }

  Future<void> reload() async {
    _loading = true;
    notifyListeners();

    await _repository.jsSourceScan();
    _sources = await _repository.jsSourceList();
    _activeSourceId = await _repository.jsSourceGetActive();

    _loading = false;
    notifyListeners();
  }

  Future<void> clearAll() async {
    _loading = true;
    notifyListeners();

    await _repository.jsSourceClearAll();
    _sources = [];
    _activeSourceId = '';
    await _preferences?.remove(_activeSourceKey);

    _loading = false;
    notifyListeners();
  }
}
