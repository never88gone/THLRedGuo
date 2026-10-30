import 'package:THLRedLook/models/catalog/models.dart';

enum PlaybackRecoveryAction { cache, alternative, refresh, stop }

class PlaybackRecovery {
  static const maxAttempts = 5;
  int _attempts = 0;
  int _attemptLimit = maxAttempts;
  bool _cacheAttempted = false;
  Duration _retryDelay = Duration.zero;
  int get attempts => _attempts;
  int get attemptLimit => _attemptLimit;
  bool get cacheAttempted => _cacheAttempted;
  Duration get retryDelay => _retryDelay;

  static int attemptLimitFor(String errorCode) =>
      const {'EMPTY_RESPONSE', 'RESPONSE_NOT_UTF8'}.contains(errorCode)
      ? 2
      : maxAttempts;

  static bool audioOutputFailed(String error) =>
      error.toLowerCase().contains('could not open/initialize audio device');

  void reset() {
    _attempts = 0;
    _attemptLimit = maxAttempts;
    _cacheAttempted = false;
    _retryDelay = Duration.zero;
  }

  PlaybackRecoveryAction next(
    PlaybackPlan? plan, {
    bool allowCache = false,
    bool decryptedStream = false,
    String errorCode = '',
  }) {
    _attemptLimit = attemptLimitFor(errorCode);
    if (_attempts >= _attemptLimit) {
      return PlaybackRecoveryAction.stop;
    }
    _attempts++;
    _retryDelay = _attemptLimit == 2
        ? Duration(seconds: _attempts == 1 ? 1 : 3)
        : Duration(milliseconds: 300 * _attempts);
    if (allowCache &&
        !_cacheAttempted &&
        plan != null &&
        !plan.local &&
        (plan.decryptionKey.isNotEmpty || decryptedStream)) {
      _cacheAttempted = true;
      return PlaybackRecoveryAction.cache;
    }
    if (plan?.hasAlternative == true) {
      return PlaybackRecoveryAction.alternative;
    }
    return PlaybackRecoveryAction.refresh;
  }
}

class PlaybackHealth {
  static const stallTimeout = Duration(seconds: 20);
  Duration? _position;
  DateTime? _lastProgress;

  void reset() {
    _position = null;
    _lastProgress = null;
  }

  bool stalled({
    required Duration position,
    required bool playing,
    bool buffering = false,
    required bool foreground,
    required DateTime now,
  }) {
    if ((!playing && !buffering) || !foreground || position != _position) {
      _position = position;
      _lastProgress = now;
      return false;
    }
    _lastProgress ??= now;
    return now.difference(_lastProgress!) >= stallTimeout;
  }
}
