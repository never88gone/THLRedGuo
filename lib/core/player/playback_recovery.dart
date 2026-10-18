import 'package:THLRedLook/models/catalog/models.dart';

enum PlaybackRecoveryAction { alternative, refresh, stop }

class PlaybackRecovery {
  static const maxAttempts = 5;
  int _attempts = 0;
  int get attempts => _attempts;

  void reset() {
    _attempts = 0;
  }

  PlaybackRecoveryAction next(PlaybackPlan? plan) {
    if (_attempts >= maxAttempts) {
      return PlaybackRecoveryAction.stop;
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
