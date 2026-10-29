import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HongguoGuestSession {
  static final shared = HongguoGuestSession();
  static const sessionKey = 'thl_hongguo_device_session';
  static const createdKey = 'thl_hongguo_guest_created_at';

  HongguoGuestSession({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;
  String? value;
  DateTime? createdAt;
  bool _loaded = false;
  int _generation = 0;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Completer<void>? _initializing;

  Future<void>? get initialization => _initializing?.future;

  Completer<void> beginInitialization() => _initializing ??= Completer<void>();

  void completeInitialization(Completer<void> owner) {
    if (identical(_initializing, owner)) _initializing = null;
    if (!owner.isCompleted) owner.complete();
  }

  static bool valid(String? value) {
    if (value == null || value.isEmpty) return false;
    try {
      final data = jsonDecode(value);
      return data is Map &&
          ['iid', 'device_id'].every(
            (key) =>
                data[key] is String &&
                RegExp(r'^[1-9]\d{9,23}$').hasMatch(data[key] as String),
          );
    } catch (_) {
      return false;
    }
  }

  Future<SharedPreferences?> _preferences() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  DateTime? _date(int? milliseconds) =>
      milliseconds == null || milliseconds <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(milliseconds);

  Future<void> preload() async {
    if (_loaded) return;
    if (_loading != null) return _loading;
    final generation = _generation;
    _loading = () async {
      try {
        final prefs = await _preferences();
        if (_generation != generation) return;
        final stored = prefs?.getString(sessionKey);
        value = valid(stored) ? stored : null;
        createdAt = _date(prefs?.getInt(createdKey));
      } finally {
        _loaded = true;
        _loading = null;
      }
    }();
    await _loading;
  }

  Future<T> _serialize<T>(Future<T> Function() run) {
    final previous = _writes;
    final completed = Completer<void>();
    _writes = completed.future;
    return () async {
      try {
        await previous;
        return await run();
      } finally {
        completed.complete();
      }
    }();
  }

  void accept(String json) {
    if (!valid(json)) return;
    if (value != json) createdAt = now();
    value = json;
    final initializing = _initializing;
    if (initializing != null) completeInitialization(initializing);
    _loaded = true;
    _generation++;
    final created = createdAt;
    unawaited(
      _serialize(() async {
        final prefs = await _preferences();
        try {
          await prefs?.setString(sessionKey, json);
          await prefs?.setInt(createdKey, created?.millisecondsSinceEpoch ?? 0);
        } catch (_) {}
      }),
    );
  }

  Future<bool> refresh() async {
    await preload();
    return _serialize(() async {
      final generation = _generation;
      final prefs = await _preferences();
      try {
        await prefs?.reload();
      } catch (_) {
        return false;
      }
      if (_generation != generation) return false;
      final stored = prefs?.getString(sessionKey);
      if (!valid(stored)) return false;
      final storedCreated = _date(prefs?.getInt(createdKey));
      final currentCreated = createdAt;
      if (stored == value) {
        if (storedCreated != null &&
            (currentCreated == null || storedCreated.isAfter(currentCreated))) {
          createdAt = storedCreated;
        }
        return false;
      }
      if (storedCreated != null &&
          currentCreated != null &&
          storedCreated.isBefore(currentCreated)) {
        return false;
      }
      value = stored;
      createdAt = storedCreated;
      _generation++;
      return true;
    });
  }

  Future<void> get pendingWrites => _writes;

  void resetForTesting([String? session, DateTime? created]) {
    value = valid(session) ? session : null;
    createdAt = created;
    _loaded = true;
    _loading = null;
    _generation++;
    final initializing = _initializing;
    if (initializing != null) completeInitialization(initializing);
  }
}
