import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/pages/feed/video_feed_page.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/views/home/home_catalog_view.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';

Future<void> waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required String stage,
}) async {
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (!condition() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  expect(condition(), isTrue, reason: stage);
}

Future<void> ready(WidgetTester tester) async {
  await waitFor(
    tester,
    () => find.byType(LunaExoVideoView).evaluate().isNotEmpty,
    stage: 'video surface',
  );
  final player = tester
      .widget<LunaExoVideoView>(find.byType(LunaExoVideoView).first)
      .player;
  await waitFor(
    tester,
    () =>
        player.state.position.inMilliseconds > 0 &&
        (player.state.width ?? 0) > 0 &&
        !player.state.buffering,
    stage: 'picture and playback',
  );
  await tester.runAsync(
    () => player.waitForVideoFrame().timeout(const Duration(seconds: 20)),
  );
  expect(await tester.runAsync(player.audioTrackCount), greaterThan(0));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('home and recommendation first batch and automatic paging', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    expect(DramaCover.imagesDisabled, true);
    final clock = Stopwatch()..start();
    app.main([]);
    HomeCatalogView catalog() =>
        t.widget<HomeCatalogView>(find.byType(HomeCatalogView).first);
    await waitFor(
      t,
      () =>
          find.byType(HomeScreen).evaluate().isNotEmpty &&
          find.byType(HomeCatalogView).evaluate().isNotEmpty &&
          catalog().items.isNotEmpty,
      stage: 'home first list',
    );
    final first = catalog().items.length;
    debugPrint(
      'LIST_RESULT ${jsonEncode({'stage': 'home-first', 'ms': clock.elapsedMilliseconds, 'count': first})}',
    );
    expect(catalog().error, isNull);
    for (
      var i = 0;
      i < 10 && catalog().items.length == first && catalog().hasMore;
      i++
    ) {
      await t.drag(find.byType(CustomScrollView).last, const Offset(0, -600));
      await t.pump(const Duration(milliseconds: 300));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    }
    await waitFor(
      t,
      () =>
          catalog().items.length > first ||
          !catalog().hasMore ||
          catalog().error != null,
      stage: 'home automatic pagination',
    );
    expect(catalog().error, isNull);
    expect(
      catalog().items.map((d) => d.id).toSet().length,
      catalog().items.length,
    );
    debugPrint(
      'LIST_RESULT ${jsonEncode({'stage': 'home-more', 'count': catalog().items.length})}',
    );
    final feedClock = Stopwatch()..start();
    await t.tap(find.byKey(const ValueKey('bottom-nav-1')));
    await t.pump();
    await waitFor(
      t,
      () =>
          find.byType(VideoFeedScreen).evaluate().isNotEmpty &&
          t
              .widget<VideoFeedScreen>(find.byType(VideoFeedScreen))
              .controller
              .items
              .isNotEmpty,
      stage: 'feed first list',
    );
    final feed = t
        .widget<VideoFeedScreen>(find.byType(VideoFeedScreen))
        .controller;
    debugPrint(
      'LIST_RESULT ${jsonEncode({'stage': 'feed-first', 'ms': feedClock.elapsedMilliseconds, 'count': feed.items.length})}',
    );
    expect(feed.error, isNull);
    await ready(t);
    debugPrint(
      'LIST_RESULT ${jsonEncode({'stage': 'feed-playing', 'ms': feedClock.elapsedMilliseconds})}',
    );
    await waitFor(
      t,
      () => !feed.loadingMore,
      stage: 'feed background pagination',
    );
    final initial = feed.items.length;
    await t.runAsync(feed.loadMore);
    expect(feed.moreError, isNull);
    expect(feed.items.map((d) => d.drama.id).toSet().length, feed.items.length);
    expect(feed.items.length, greaterThanOrEqualTo(initial));
    debugPrint(
      'LIST_RESULT ${jsonEncode({'stage': 'feed-more', 'count': feed.items.length, 'hasMore': feed.hasMore})}',
    );
    await t.tap(find.byKey(const ValueKey('bottom-nav-0')));
    await t.pump(const Duration(milliseconds: 300));
    expect(feed.active, false);
    await t.tap(find.byKey(const ValueKey('bottom-nav-1')));
    await t.pump(const Duration(milliseconds: 300));
    expect(feed.items, isNotEmpty);
    await ready(t);
    await t.tap(find.byKey(const ValueKey('bottom-nav-0')));
    await t.pump(const Duration(milliseconds: 300));
  });
}
