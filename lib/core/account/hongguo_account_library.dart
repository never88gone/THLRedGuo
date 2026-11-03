import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/catalog/models.dart';
import 'hongguo_account_service.dart';
import 'hongguo_account_session.dart';

class HongguoAccountLibrary extends ChangeNotifier {
  HongguoAccountLibrary({HongguoAccountService? service})
    : service = service ?? HongguoAccountService() {
    this.service.session.addListener(_accountChanged);
    _revision = this.service.session.revision;
  }
  static final shared = HongguoAccountLibrary();
  final HongguoAccountService service;
  int _revision = 0, _favoriteGeneration = 0;
  final _progressGeneration = <String, int>{};
  final _history = <String, WatchEntry>{};
  final _historyIds = <String>{};
  final _favorites = <String, Drama>{};
  final _loaded = <bool>{};
  final _loads = <bool, Future<List<WatchEntry>>>{};
  final _reportedAt = <String, DateTime>{};
  final _retryAt = <String, DateTime>{};
  final _reportErrors = <String, Object>{};
  final _pendingReports = <String, Future<void>>{};
  Future<void> _writes = Future.value();
  bool get active => service.session.loggedIn;
  static String id(String value) =>
      value.startsWith('hongguo:') ? value.substring('hongguo:'.length) : value;
  bool handles(String value) =>
      active &&
      (value.startsWith('hongguo:') || RegExp(r'^\d{10,30}$').hasMatch(value));
  WatchEntry? watched(String value) => _history[id(value)];
  bool following(String value) => _favorites.containsKey(id(value));
  Drama? favorite(String value) => _favorites[id(value)];
  void _accountChanged() {
    if (_revision == service.session.revision) return;
    _revision = service.session.revision;
    _favoriteGeneration++;
    _progressGeneration.clear();
    _history.clear();
    _historyIds.clear();
    _favorites.clear();
    _loaded.clear();
    _loads.clear();
    _reportedAt.clear();
    _retryAt.clear();
    _reportErrors.clear();
    _pendingReports.clear();
    notifyListeners();
  }

  void _check(int owner) {
    if (!active || owner != service.session.revision) {
      throw const HongguoAccountFailure('账号已切换，请重试', 'CANCELLED');
    }
  }

  Future<List<WatchEntry>> load(bool history, {bool refresh = false}) {
    final pending = _loads[history];
    if (pending != null) return pending;
    if (!refresh && _loaded.contains(history)) {
      return Future.value(entries(history));
    }
    final owner = _revision, generation = _favoriteGeneration;
    final progressSnapshot = Map.of(_progressGeneration);
    late final Future<List<WatchEntry>> task;
    task = () async {
      try {
        _check(owner);
        final rows = await service.library(history: history);
        _check(owner);
        if (history) {
          _historyIds.clear();
          _historyIds.addAll(rows.map((row) => id(row.drama.id)));
          _historyIds.addAll(
            _progressGeneration.entries
                .where(
                  (entry) => entry.value > (progressSnapshot[entry.key] ?? 0),
                )
                .map((entry) => entry.key),
          );
          for (final row in rows) {
            final key = id(row.drama.id), current = _history[id(row.drama.id)];
            if (current == null || !current.updatedAt.isAfter(row.updatedAt)) {
              _history[key] = row;
            }
          }
        } else if (generation == _favoriteGeneration) {
          _favorites.clear();
          for (final row in rows) {
            _favorites[id(row.drama.id)] = row.drama;
          }
        }
        _loaded.add(history);
        notifyListeners();
        return entries(history);
      } finally {
        if (identical(_loads[history], task)) _loads.remove(history);
      }
    }();
    return _loads[history] = task;
  }

  List<WatchEntry> entries(bool history) {
    final rows = history
        ? _historyIds
              .map((key) => _history[key])
              .whereType<WatchEntry>()
              .toList()
        : [
            for (final drama in _favorites.values)
              WatchEntry(
                drama: drama,
                episode: 0,
                position: 0,
                duration: 0,
                updatedAt: DateTime(2000),
              ),
          ];
    if (history) rows.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return rows;
  }

  Future<void> prepare(Drama drama) async {
    if (!handles(drama.id)) return;
    await Future.wait([load(false), refreshProgress(drama)]);
  }

  Future<WatchEntry?> refreshProgress(Drama drama) async {
    final key = id(drama.id);
    final owner = _revision, generation = _progressGeneration[key] ?? 0;
    _check(owner);
    final entry = await service.progress(drama);
    _check(owner);
    if (generation == (_progressGeneration[key] ?? 0)) {
      if (entry == null) {
        _history.remove(id(drama.id));
        _historyIds.remove(id(drama.id));
      } else {
        _history[id(drama.id)] = entry;
      }
      notifyListeners();
    }
    return watched(drama.id);
  }

  Future<void> _write(Future<void> Function() operation) {
    final owner = _revision;
    final next = _writes.catchError((Object _) {}).then((_) async {
      _check(owner);
      await operation();
      _check(owner);
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _setFollowing(Drama drama, bool follow, int owner) async {
    await service.setFollowing(drama, follow);
    _check(owner);
    _favoriteGeneration++;
    if (follow) {
      final remaining = Map.of(_favorites)..remove(id(drama.id));
      _favorites.clear();
      _favorites[id(drama.id)] = drama;
      _favorites.addAll(remaining);
    } else {
      _favorites.remove(id(drama.id));
    }
    notifyListeners();
  }

  Future<void> setFollowing(Drama drama, bool follow) {
    final owner = _revision;
    return _write(() => _setFollowing(drama, follow, owner));
  }

  Future<void> toggle(Drama drama) async {
    final owner = _revision;
    await load(false);
    _check(owner);
    await _write(() => _setFollowing(drama, !following(drama.id), owner));
  }

  Future<void> report(
    WatchEntry entry, {
    required String itemId,
    bool force = false,
  }) {
    final key = id(entry.drama.id),
        reportKey = '${id(entry.drama.id)}:${entry.episode}';
    final now = DateTime.now();
    if (!force) {
      final pending = _pendingReports[reportKey];
      if (pending != null) return pending;
      if ((_retryAt[reportKey] ?? DateTime(2000)).isAfter(now)) {
        return Future.error(_reportErrors[reportKey]!);
      }
      if (now.difference(_reportedAt[reportKey] ?? DateTime(2000)).inSeconds <
          30) {
        return Future.value();
      }
    }
    final owner = _revision;
    late final Future<void> task;
    task =
        _write(() async {
              await service.updateProgress(entry, itemId: itemId);
              _check(owner);
              _progressGeneration[key] = (_progressGeneration[key] ?? 0) + 1;
              _history[key] = entry;
              _historyIds.add(key);
              _reportedAt[reportKey] = DateTime.now();
              _retryAt.remove(reportKey);
              _reportErrors.remove(reportKey);
              notifyListeners();
            })
            .catchError((Object error) {
              if (owner == _revision) {
                _retryAt[reportKey] = DateTime.now().add(
                  const Duration(seconds: 30),
                );
                _reportErrors[reportKey] = error;
              }
              throw error;
            })
            .whenComplete(() {
              if (identical(_pendingReports[reportKey], task)) {
                _pendingReports.remove(reportKey);
              }
            });
    return _pendingReports[reportKey] = task;
  }

  Future<void> flush() async {
    await Future.wait(_pendingReports.values.toList());
  }

  @override
  void dispose() {
    service.session.removeListener(_accountChanged);
    service.dispose();
    super.dispose();
  }
}
