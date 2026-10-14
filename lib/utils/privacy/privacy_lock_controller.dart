import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/privacy/privacy_settings.dart';
import 'gesture_hasher.dart';

class PrivacyLockController extends ChangeNotifier {
  PrivacyLockController(this.preferences) {
    _load();
  }

  static const _keyEnabled = 'privacy_mode_enabled';
  static const _keySalt = 'privacy_gesture_salt';
  static const _keyHash = 'privacy_gesture_hash';
  static const _keyTimeout = 'privacy_lock_timeout_seconds';

  final SharedPreferences preferences;

  bool _isLocked = false;
  DateTime? _backgroundTimestamp;
  PrivacySettings _settings = const PrivacySettings();

  bool get isLocked => _isLocked;
  PrivacySettings get settings => _settings;
  bool get enabled => _settings.enabled;
  bool get hasGesture => _settings.hasGesture;
  int get autoLockSeconds => _settings.autoLockSeconds;

  void _load() {
    final enabled = preferences.getBool(_keyEnabled) ?? false;
    final salt = preferences.getString(_keySalt) ?? '';
    final hash = preferences.getString(_keyHash) ?? '';
    final timeout = preferences.getInt(_keyTimeout) ?? 60;
    final hasGesture = salt.isNotEmpty && hash.isNotEmpty;

    _settings = PrivacySettings(
      enabled: enabled && hasGesture,
      hasGesture: hasGesture,
      autoLockSeconds: timeout,
    );

    if (_settings.enabled && _settings.hasGesture) {
      _isLocked = true;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (value && !_settings.hasGesture) {
      throw StateError('请先设置手势密码');
    }
    await preferences.setBool(_keyEnabled, value);
    _settings = _settings.copyWith(enabled: value);
    if (!value) {
      _isLocked = false;
    }
    notifyListeners();
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    await preferences.setInt(_keyTimeout, seconds);
    _settings = _settings.copyWith(autoLockSeconds: seconds);
    notifyListeners();
  }

  Future<void> saveGesture(List<int> pattern) async {
    if (pattern.length < 4) {
      throw ArgumentError('手势至少需要连接4个点');
    }
    final salt = GestureHasher.generateSalt();
    final hash = GestureHasher.hashPattern(pattern, salt);
    await preferences.setString(_keySalt, salt);
    await preferences.setString(_keyHash, hash);
    await preferences.setBool(_keyEnabled, true);

    _settings = _settings.copyWith(
      enabled: true,
      hasGesture: true,
    );
    _isLocked = false;
    notifyListeners();
  }

  bool verifyGesture(List<int> pattern) {
    if (!_settings.hasGesture) return false;
    final salt = preferences.getString(_keySalt) ?? '';
    final hash = preferences.getString(_keyHash) ?? '';
    if (salt.isEmpty || hash.isEmpty) return false;

    final target = GestureHasher.hashPattern(pattern, salt);
    final match = GestureHasher.constantTimeCompare(target, hash);
    if (match) {
      _isLocked = false;
      _backgroundTimestamp = null;
      notifyListeners();
    }
    return match;
  }

  Future<void> clearGesture() async {
    await preferences.remove(_keySalt);
    await preferences.remove(_keyHash);
    await preferences.setBool(_keyEnabled, false);
    _settings = _settings.copyWith(
      enabled: false,
      hasGesture: false,
    );
    _isLocked = false;
    notifyListeners();
  }

  void lock() {
    if (_settings.enabled && _settings.hasGesture && !_isLocked) {
      _isLocked = true;
      notifyListeners();
    }
  }

  void unlock() {
    if (_isLocked) {
      _isLocked = false;
      _backgroundTimestamp = null;
      notifyListeners();
    }
  }

  bool _isInBackground = false;
  bool get isInBackground => _isInBackground;
  bool get isBlurred => (_settings.enabled && _settings.hasGesture) && _isInBackground;

  void handleLifecycleChange(AppLifecycleState state) {
    if (!_settings.enabled || !_settings.hasGesture) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _isInBackground = true;
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        _backgroundTimestamp ??= DateTime.now();
        if (_settings.autoLockSeconds == 0) {
          _isLocked = true;
        }
      }
      notifyListeners();
    } else if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      if (_isLocked) {
        notifyListeners();
        return;
      }
      final bgTime = _backgroundTimestamp;
      if (bgTime != null) {
        final elapsed = DateTime.now().difference(bgTime).inSeconds;
        if (_settings.autoLockSeconds == 0 ||
            elapsed >= _settings.autoLockSeconds) {
          _isLocked = true;
        }
      }
      _backgroundTimestamp = null;
      notifyListeners();
    }
  }
}
