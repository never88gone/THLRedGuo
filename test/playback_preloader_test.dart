import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/player/playback_preloader.dart';
import 'package:THLRedLook/models/catalog/models.dart';

class _PreloadRepository extends AppRepository {
  final pending = Completer<PlaybackPlan?>();
  int calls = 0;
  int cancellations = 0;
  final released = <String>[];

  @override
  Future<PlaybackPlan?> preload(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool online = false,
  }) {
    calls++;
    return pending.future;
  }

  @override
  Future<void> cancelPreload() async {
    cancellations++;
  }

  @override
  Future<void> release(String session) async {
    released.add(session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImmediatePreloadRepository extends AppRepository {
  _ImmediatePreloadRepository(this.now);
  final DateTime Function() now;
  int calls = 0;
  @override
  Future<PlaybackPlan?> preload(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool online = false,
  }) async {
    calls++;
    return PlaybackPlan(
      url: 'memory:synthetic',
      session: 'synthetic-$calls',
      expiresAt: now().add(const Duration(seconds: 30)).millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> release(String session) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const drama = Drama(
    id: 'hongguo:synthetic',
    source: 'hongguo',
    title: '合成剧集',
  );
  final episode = Episode({'index': 2, 'url': 'synthetic'}, 2);
  const plan = PlaybackPlan(
    url: '/synthetic/next.mp4',
    local: true,
    session: 'synthetic-next',
  );

  test('prefetch follows actual remaining time at each playback speed', () {
    expect(
      PlaybackPreloader.shouldPrepare(
        duration: const Duration(minutes: 4),
        position: const Duration(seconds: 1),
      ),
      false,
    );
    expect(
      PlaybackPreloader.shouldPrepare(
        duration: const Duration(minutes: 4),
        position: const Duration(seconds: 220),
      ),
      true,
    );
    expect(
      PlaybackPreloader.shouldPrepare(
        duration: const Duration(minutes: 4),
        position: const Duration(seconds: 220),
        rate: 0.5,
      ),
      false,
    );
    expect(
      PlaybackPreloader.shouldPrepare(
        duration: const Duration(minutes: 4),
        position: const Duration(seconds: 230),
        rate: 0.5,
      ),
      true,
    );
    expect(
      PlaybackPreloader.shouldPrepare(
        duration: const Duration(minutes: 4),
        position: const Duration(seconds: 200),
        rate: 2,
      ),
      true,
    );
    expect(
      PlaybackPreloader.shouldPrepare(
        duration: Duration.zero,
        position: Duration.zero,
      ),
      false,
    );
    expect(
      PlaybackPreloader.shouldPrepare(
        duration: const Duration(seconds: 10),
        position: const Duration(seconds: 10),
      ),
      false,
    );
  });

  testWidgets('a four-minute episode prepares a thirty-second URL only once', (
    t,
  ) async {
    final began = DateTime(2026, 10, 29);
    var now = began;
    final repository = _ImmediatePreloadRepository(() => now);
    final preloader = PlaybackPreloader(repository, now: () => now);
    addTearDown(preloader.dispose);
    for (var seconds = 0; seconds < 240; seconds++) {
      now = began.add(Duration(seconds: seconds));
      if (PlaybackPreloader.shouldPrepare(
        duration: const Duration(minutes: 4),
        position: Duration(seconds: seconds),
      )) {
        preloader.prepare(drama, episode);
      }
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(repository.calls, 1);
    expect(preloader.take(drama, episode)?.session, 'synthetic-1');
  });

  test('缓冲与恢复播放反复切换时，保留同一次预加载并接受结果', () async {
    final repository = _PreloadRepository();
    final preloader = PlaybackPreloader(repository);
    addTearDown(preloader.dispose);
    preloader.prepare(drama, episode);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    for (var i = 0; i < 5; i++) {
      preloader.pause();
      preloader.prepare(drama, episode);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    expect(repository.calls, 1);
    expect(repository.cancellations, 0);
    repository.pending.complete(plan);
    await Future<void>.delayed(Duration.zero);
    expect(preloader.take(drama, episode)?.session, 'synthetic-next');
  });

  test('切集清理仍取消预加载，迟到结果被释放而不能发布', () async {
    final repository = _PreloadRepository();
    final preloader = PlaybackPreloader(repository);
    addTearDown(preloader.dispose);
    preloader.prepare(drama, episode);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    preloader.clear();
    repository.pending.complete(plan);
    await Future<void>.delayed(Duration.zero);
    expect(repository.cancellations, 1);
    expect(repository.released, ['synthetic-next']);
    expect(preloader.take(drama, episode), isNull);
  });
}
