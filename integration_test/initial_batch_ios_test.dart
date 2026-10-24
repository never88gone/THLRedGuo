import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/pages/feed/video_feed_page.dart';
import 'package:THLRedLook/views/home/home_catalog_view.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/catalog/catalog_filters.dart';
import 'list_loading_ios_test.dart' as h;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'full initial catalog viewport and gesture-driven automatic paging',
    (t) async {
      expect(Platform.isIOS, true);
      expect(DramaCover.imagesDisabled, true);
      SharedPreferences.setMockInitialValues({});
      final rows = <Map<String, Object?>>[];
      void record(Map<String, Object?> row) {
        rows.add(row);
        debugPrint('BATCH_RESULT ${jsonEncode(row)}');
      }

      final clock = Stopwatch()..start();
      app.main([]);
      HomeCatalogView catalog() =>
          t.widget<HomeCatalogView>(find.byType(HomeCatalogView).first);
      await h.waitFor(
        t,
        () =>
            find.byType(HomeCatalogView).evaluate().isNotEmpty &&
            catalog().items.isNotEmpty,
        stage: 'cold first home list',
      );
      expect(catalog().items.length, greaterThanOrEqualTo(12));
      expect(catalog().error, isNull);
      record({
        'stage': 'cold-home',
        'ms': clock.elapsedMilliseconds,
        'count': catalog().items.length,
      });
      Future<void> more(String genre) async {
        await h.waitFor(
          t,
          () => catalog().scrollController.hasClients && !catalog().loading,
          stage: 'catalog layout $genre',
        );
        final before = catalog().items.length;
        final ids = catalog().items.map((d) => d.id).toList();
        final position = catalog().scrollController.position;
        expect(position.maxScrollExtent, greaterThan(0));
        record({
          'stage': 'viewport',
          'genre': genre,
          'count': before,
          'viewport': position.viewportDimension,
          'extent': position.maxScrollExtent,
        });
        for (var i = 0; i < 12 && catalog().items.length == before; i++) {
          await t.drag(
            find.byType(CustomScrollView).last,
            const Offset(0, -550),
          );
          await t.pump(const Duration(milliseconds: 300));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
        }
        await h.waitFor(
          t,
          () => catalog().items.length > before || catalog().error != null,
          stage: 'catalog automatic paging $genre',
        );
        expect(catalog().error, isNull);
        expect(catalog().items.length, greaterThan(before));
        expect(catalog().items.take(ids.length).map((d) => d.id), ids);
        expect(
          catalog().items.map((d) => d.id).toSet().length,
          catalog().items.length,
        );
        expect(find.text('加载更多'), findsNothing);
        record({
          'stage': 'home-more',
          'genre': genre,
          'before': before,
          'count': catalog().items.length,
        });
      }

      await h.waitFor(
        t,
        () =>
            find.byType(CatalogFilters).evaluate().isNotEmpty &&
            t
                    .widget<CatalogFilters>(find.byType(CatalogFilters).first)
                    .categories
                    .length ==
                4,
        stage: 'four App categories',
      );
      expect(
        t
            .widget<CatalogFilters>(find.byType(CatalogFilters).first)
            .categories
            .map((c) => c.name),
        ['全部', '真人剧', '漫剧', 'AI剧'],
      );
      await more('all');
      for (final genre in ['playlet', 'motion_comic', 'ai_playlet']) {
        final chip = find.byKey(ValueKey('category-app:discover:$genre'));
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pump();
        await h.waitFor(
          t,
          () =>
              catalog().gridKey.contains('app:discover:$genre-') &&
              !catalog().loading &&
              catalog().items.isNotEmpty,
          stage: 'selected category $genre',
        );
        expect(catalog().error, isNull);
        expect(catalog().items.length, greaterThanOrEqualTo(12));
        record({
          'stage': 'category-first',
          'genre': genre,
          'count': catalog().items.length,
        });
        await more(genre);
      }
      final feedClock = Stopwatch()..start();
      await t.tap(find.byKey(const ValueKey('bottom-nav-1')));
      await t.pump();
      await h.waitFor(
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
      final initialCount = feed.items.length;
      record({
        'stage': 'feed-first',
        'ms': feedClock.elapsedMilliseconds,
        'count': initialCount,
      });
      await h.ready(t);
      final viewed = <String>[feed.current!.drama.id];
      record({
        'stage': 'feed-playing',
        'ms': feedClock.elapsedMilliseconds,
        'count': feed.items.length,
      });
      for (var i = 1; i <= 4; i++) {
        await t.drag(
          find.byKey(const ValueKey('feed-pager')),
          const Offset(0, -650),
        );
        await t.pump(const Duration(milliseconds: 400));
        await h.waitFor(
          t,
          () => feed.index == i,
          stage: 'recommendation swipe $i',
        );
        await h.ready(t);
        viewed.add(feed.current!.drama.id);
        expect(feed.error, isNull);
        expect(feed.moreError, isNull);
        record({'stage': 'feed-swipe', 'index': i, 'count': feed.items.length});
      }
      expect(viewed.toSet(), hasLength(5));
      expect(feed.items.length, greaterThan(initialCount));
      expect(
        feed.items.map((item) => item.drama.id).toSet().length,
        feed.items.length,
      );
      await t.drag(
        find.byKey(const ValueKey('feed-pager')),
        const Offset(0, 650),
      );
      await t.pump(const Duration(milliseconds: 400));
      await h.waitFor(
        t,
        () => feed.index == 3,
        stage: 'previous recommendation',
      );
      await h.ready(t);
      expect(feed.current!.drama.id, viewed[3]);
      await t.tap(find.byKey(const ValueKey('bottom-nav-0')));
      await t.pump(const Duration(milliseconds: 300));
      expect(feed.active, false);
      final retained = catalog().items.map((d) => d.id).toList();
      await t.tap(find.byKey(const ValueKey('bottom-nav-1')));
      await t.pump(const Duration(milliseconds: 300));
      expect(feed.index, 3);
      await h.ready(t);
      await t.tap(find.byKey(const ValueKey('bottom-nav-0')));
      await t.pump(const Duration(milliseconds: 300));
      expect(catalog().items.map((d) => d.id), retained);
      expect(t.takeException(), isNull);
      record({
        'stage': 'complete',
        'feedUnique': viewed.toSet().length,
        'feedCount': feed.items.length,
        'tabReturn': true,
      });
      binding.reportData = {
        'results': rows,
        'imagesDisabled': true,
        'version': '1.0.0',
      };
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
