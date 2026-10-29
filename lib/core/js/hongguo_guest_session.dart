import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum GuestRecoveryDecision { none, reload, renew }

class HongguoGuestSession {
  static final shared = HongguoGuestSession();
  static const sessionKey = 'thl_hongguo_device_session';
  static const createdKey = 'thl_hongguo_guest_created_at';
  static const recoveryKey = 'thl_hongguo_guest_recovery_at';
  static const recoveryInterval = Duration(minutes: 10);

  HongguoGuestSession({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;
  String? value;
  DateTime? createdAt;
  DateTime? _recoveredAt;
  bool _loaded = false;
  int _generation = 0;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<void>? recovery;

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
        _recoveredAt = _date(prefs?.getInt(recoveryKey));
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

  Future<GuestRecoveryDecision> invalidate(String expected) async {
    await preload();
    return _serialize(() async {
      final generation = _generation;
      final prefs = await _preferences();
      await prefs?.reload();
      if (_generation != generation || value != expected) {
        return value != null && value != expected
            ? GuestRecoveryDecision.reload
            : GuestRecoveryDecision.none;
      }
      final stored = prefs?.getString(sessionKey);
      if (valid(stored) && stored != expected) {
        value = stored;
        createdAt = _date(prefs?.getInt(createdKey));
        _generation++;
        return GuestRecoveryDecision.reload;
      }
      final recovered = _date(prefs?.getInt(recoveryKey)) ?? _recoveredAt;
      final time = now();
      if (recovered != null && time.difference(recovered) < recoveryInterval) {
        return GuestRecoveryDecision.none;
      }
      try {
        await prefs?.setInt(recoveryKey, time.millisecondsSinceEpoch);
        await prefs?.setString(sessionKey, '');
        await prefs?.setInt(createdKey, 0);
      } catch (_) {
        return GuestRecoveryDecision.none;
      }
      if (_generation != generation) {
        return value != null && value != expected
            ? GuestRecoveryDecision.reload
            : GuestRecoveryDecision.none;
      }
      value = null;
      createdAt = null;
      _recoveredAt = time;
      _generation++;
      return GuestRecoveryDecision.renew;
    });
  }

  Future<void> get pendingWrites => _writes;

  void resetForTesting([String? session, DateTime? created]) {
    value = valid(session) ? session : null;
    createdAt = created;
    _recoveredAt = null;
    _loaded = true;
    _loading = null;
    _generation++;
    recovery = null;
  }
}
