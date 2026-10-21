import 'dart:async';

class PlaybackLeaseQueue {
  Future<void> _tail = Future<void>.value();
  Future<void> get idle => _tail;

  PlaybackLease acquire() {
    final release = Completer<void>();
    final lease = PlaybackLease._(_tail, release);
    _tail = release.future;
    return lease;
  }
}

class PlaybackLease {
  PlaybackLease._(this.ready, this._release);
  final Future<void> ready;
  final Completer<void> _release;

  Future<void> releaseAfter(Future<void> closing) async {
    try {
      await Future.wait([ready, closing]);
    } finally {
      if (!_release.isCompleted) _release.complete();
    }
  }
}
