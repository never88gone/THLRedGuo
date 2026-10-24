import 'package:THLRedLook/models/catalog/models.dart';

enum PlaybackRecoveryAction { cache, alternative, refresh, stop }

class PlaybackRecovery {
  static const maxAttempts = 5;
  int _attempts = 0;
  bool _cacheAttempted = false;
  int get attempts => _attempts;
  bool get cacheAttempted => _cacheAttempted;
  Duration get retryDelay => Duration(milliseconds: 300 * _attempts);

  static bool audioOutputFailed(String error) =>
      error.toLowerCase().contains('could not open/initialize audio device');

  void reset() {
    _attempts = 0;
    _cacheAttempted = false;
  }

  PlaybackRecoveryAction next(
    PlaybackPlan? plan, {
    bool allowCache = false,
    bool decryptedStream = false,
  }) {
    if (_attempts >= maxAttempts) {
      return PlaybackRecoveryAction.stop;
    }
    if (allowCache &&
        !_cacheAttempted &&
        plan != null &&
        !plan.local &&
        (plan.decryptionKey.isNotEmpty || decryptedStream)) {
      _cacheAttempted = true;
      _attempts++;
      return PlaybackRecoveryAction.cache;
    }
    if (plan?.hasAlternative == true) {
      _attempts++;
      return PlaybackRecoveryAction.alternative;
    }
    _attempts++;
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
