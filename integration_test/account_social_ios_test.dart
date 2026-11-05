import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/core/account/hongguo_account_library.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/account/hongguo_account_social.dart';
import 'package:THLRedLook/core/account/hongguo_social_models.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/views/account/hongguo_social_dialog.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/home/home_catalog_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    '官方账号互动页面及回读，操作后恢复原状态',
    (tester) async {
      Future<T> real<T>(Future<T> Function() action) async =>
          (await tester.runAsync(action)) as T;
      Future<void> wait(
        bool Function() done,
        String stage, {
        int seconds = 60,
      }) async {
        debugPrint('THL_SOCIAL_STAGE $stage');
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(end)) {
          final error = find.byKey(const ValueKey('account-social-error'));
          if (error.evaluate().isNotEmpty) {
            fail('$stage: ${tester.widget<Text>(error).data}');
          }
          await tester.pump(const Duration(milliseconds: 100));
          await real(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(done(), isTrue, reason: stage);
      }

      Finder key(String value) => find.byKey(ValueKey(value));
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 250));
        await wait(
          () {
            final rows = target.hitTestable();
            if (rows.evaluate().length != 1) return false;
            final widget = tester.widget(rows);
            return widget is! ButtonStyleButton || widget.onPressed != null;
          },
          'enabled target',
          seconds: 20,
        );
        await tester.tap(target.hitTestable());
        await tester.pump(const Duration(milliseconds: 250));
      }

      await app.main([]);
      await wait(
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
        'bootstrap',
      );
      expect(DramaCover.imagesDisabled, isTrue);
      expect(
        HongguoAccountSession.shared.loggedIn,
        isTrue,
        reason: 'Dedicated simulator must retain owner login',
      );
      final root = tester.widget<app.DuanjuApp>(find.byType(app.DuanjuApp));
      final store = root.store!, nav = root.navigatorKey!.currentState!;
      final localHistory = jsonEncode(
        store.history
            .map(
              (v) => {
                'id': v.drama.id,
                'episode': v.episode,
                'position': v.position,
                'duration': v.duration,
                'updatedAt': v.updatedAt.toIso8601String(),
              },
            )
            .toList(),
      );
      final localFavorites = jsonEncode(
        store.favorites.map((v) => v.id).toList(),
      );
      addTearDown(() {
        expect(
          jsonEncode(
            store.history
                .map(
                  (v) => {
                    'id': v.drama.id,
                    'episode': v.episode,
                    'position': v.position,
                    'duration': v.duration,
                    'updatedAt': v.updatedAt.toIso8601String(),
                  },
                )
                .toList(),
          ),
          localHistory,
        );
        expect(
          jsonEncode(store.favorites.map((v) => v.id).toList()),
          localFavorites,
        );
        debugPrint('THL_SOCIAL_LOCAL libraryUnchanged=true');
      });
      final model = HongguoAccountSocial.shared;
      final library = HongguoAccountLibrary.shared;
      await real(() => library.load(false));
      await wait(
        () =>
            find.byType(HomeCatalogView).evaluate().isNotEmpty &&
            !tester
                .widget<HomeCatalogView>(find.byType(HomeCatalogView).last)
                .loading,
        'catalog',
      );
      final candidates = tester
          .widget<HomeCatalogView>(find.byType(HomeCatalogView).last)
          .items
          .where((d) => d.source == 'hongguo')
          .take(8)
          .toList();
      expect(candidates, isNotEmpty);
      final proof = <String, dynamic>{
        'postersDisabled': true,
        'samples': <Object>[],
      };
      binding.reportData = proof;
      bool likedTested = false, creatorTested = false, shelfTested = false;
      for (final drama in candidates) {
        HongguoEpisodeLike? originalLike;
        HongguoCreator? originalCreator;
        final originalShelf = library.following(drama.id);
        if (originalShelf) continue;
        var shelfAttempted = false,
            likeAttempted = false,
            creatorAttempted = false;
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => DetailScreen(
              drama: drama,
              repository: root.repository,
              store: store,
            ),
          ),
        );
        try {
          await wait(
            () =>
                key('account-social-open').evaluate().isNotEmpty &&
                key('follow-status').evaluate().isNotEmpty,
            'detail',
          );
          if (!shelfTested) {
            shelfAttempted = true;
            await tap(key('follow-status'));
            await wait(
              () => library.following(drama.id) != originalShelf,
              'shelf changed',
            );
            await tap(key('follow-status'));
            await wait(
              () => library.following(drama.id) == originalShelf,
              'shelf restored',
            );
            shelfTested = true;
          }
          final selectedEpisode = tester
              .widget<HongguoSocialButton>(
                find.byType(HongguoSocialButton).first,
              )
              .episode;
          await tap(key('account-social-open'));
          await wait(
            () =>
                model.snapshot(drama) != null &&
                find.byType(LinearProgressIndicator).evaluate().isEmpty,
            'official social state',
          );
          final data = model.snapshot(drama)!;
          (proof['samples'] as List).add({
            'series': drama.cleanSourceId,
            'episode': selectedEpisode,
            'episodeStates': data.episodes.length,
            'creators': data.creators.length,
            'creatorError': data.creatorError,
          });
          debugPrint(
            'THL_SOCIAL_SAMPLE ${jsonEncode((proof['samples'] as List).last)}',
          );
          if (!likedTested && data.episode(selectedEpisode)?.liked == false) {
            originalLike = data.episode(selectedEpisode)!;
            likeAttempted = true;
            await tap(key('account-episode-like'));
            await wait(
              () =>
                  !model.busy(drama) &&
                  model.snapshot(drama)?.episode(selectedEpisode)?.liked !=
                      originalLike!.liked,
              'like changed',
            );
            await tap(find.widgetWithText(TextButton, '刷新'));
            await wait(
              () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
              'like refresh',
            );
            expect(
              model.snapshot(drama)?.episode(selectedEpisode)?.liked,
              !originalLike.liked,
            );
            await tap(key('account-episode-like'));
            await wait(
              () =>
                  !model.busy(drama) &&
                  model.snapshot(drama)?.episode(selectedEpisode)?.liked ==
                      originalLike!.liked,
              'like restored',
            );
            likedTested = true;
            proof['likeSeries'] = drama.cleanSourceId;
          }
          final available = model
              .snapshot(drama)!
              .creators
              .where(
                (v) =>
                    v.following == false &&
                    v.canFollow &&
                    v.id != HongguoAccountSession.shared.id,
              );
          if (!creatorTested && available.isNotEmpty) {
            originalCreator = available.first;
            creatorAttempted = true;
            final creatorKey = key('account-creator-${originalCreator.id}');
            await tap(creatorKey);
            bool? following() => model
                .snapshot(drama)!
                .creators
                .where((v) => v.id == originalCreator!.id)
                .first
                .following;
            await wait(
              () =>
                  !model.busy(drama) &&
                  following() == !originalCreator!.following!,
              'creator changed',
            );
            await tap(find.widgetWithText(TextButton, '刷新'));
            await wait(
              () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
              'creator refresh',
            );
            expect(following(), !originalCreator.following!);
            await tap(creatorKey);
            await wait(
              () =>
                  !model.busy(drama) &&
                  following() == originalCreator!.following,
              'creator restored',
            );
            creatorTested = true;
            proof['creatorSeries'] = drama.cleanSourceId;
          }
          await tap(find.widgetWithText(TextButton, '关闭'));
          await wait(
            () => find.byType(AlertDialog).evaluate().isEmpty,
            'close social',
          );
        } finally {
          if (creatorAttempted) {
            final fresh = await real(() => model.service.creators(drama));
            final row = fresh.firstWhere((v) => v.id == originalCreator!.id);
            if (row.following != originalCreator!.following) {
              await real(
                () => model.follow(drama, row, originalCreator!.following!),
              );
            }
          }
          if (likeAttempted) {
            final fresh = await real(() => model.service.social(drama));
            final row = fresh.episode(originalLike!.number)!;
            if (row.liked != originalLike.liked) {
              await real(() => model.like(drama, row, originalLike!.liked));
            }
          }
          if (shelfAttempted) {
            final fresh = await real(
              () => model.service.library(history: false),
            );
            final followed = fresh.any(
              (entry) => entry.drama.cleanSourceId == drama.cleanSourceId,
            );
            if (followed != originalShelf) {
              await real(() => library.setFollowing(drama, originalShelf));
            }
          }
          if (find.byType(AlertDialog).evaluate().isNotEmpty) nav.pop();
          nav.pop();
          await tester.pump(const Duration(milliseconds: 300));
        }
        if (likedTested && creatorTested && shelfTested) break;
        await real(() => Future<void>.delayed(const Duration(seconds: 2)));
      }
      proof.addAll({
        'likeAndUnlike': likedTested,
        'creatorFollowAndUnfollow': creatorTested,
        'shelfToggleAndRestore': shelfTested,
        'initialAccountStatesRestored': true,
      });
      expect(
        jsonEncode(
          store.history
              .map(
                (v) => {
                  'id': v.drama.id,
                  'episode': v.episode,
                  'position': v.position,
                  'duration': v.duration,
                  'updatedAt': v.updatedAt.toIso8601String(),
                },
              )
              .toList(),
        ),
        localHistory,
      );
      expect(
        jsonEncode(store.favorites.map((v) => v.id).toList()),
        localFavorites,
      );
      proof['localLibraryUnchanged'] = true;
      debugPrint('THL_SOCIAL_RESULT ${jsonEncode(proof)}');
      expect(
        likedTested && creatorTested && shelfTested,
        isTrue,
        reason:
            'All requested real-account interactions need a confirmed sample',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
    skip: !const bool.fromEnvironment('THL_ACCOUNT_OWNER'),
  );
}
