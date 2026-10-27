import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostic_runner.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/pages/settings/settings_page.dart';
import 'package:THLRedLook/pages/settings/source_diagnostics_page.dart';
import 'package:THLRedLook/views/catalog/catalog_filters.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/home/home_catalog_view.dart';
import 'ios_full_ui_test.dart' as h;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  SharedPreferences.setMockInitialValues({});
  testWidgets(
    'iOS search resilience, diagnostics, and native file export',
    (t) async {
      final semantics = t.ensureSemantics();
      try {
        expect(Platform.isIOS, true);
        expect(DramaCover.imagesDisabled, true);
        final rows = <Map<String, Object?>>[];
        final script = await kPresetJsSources
            .firstWhere((s) => s.id == 'hongguo')
            .loadScript();
        final tabs = <String>[];
        final recorder = SourceDiagnostics();
        final client = MockClient((r) async {
          Object data;
          if (r.url.path.contains('device_register')) {
            data = {
              'device_id_str': '7345678901234567100',
              'install_id_str': '7345678901234567200',
            };
          } else {
            final tab = r.url.queryParameters['tab_type']!;
            tabs.add(tab);
            final next = r.url.queryParameters['offset'] != '0';
            data = {
              'code': 0,
              'search_tabs': tab == '29'
                  ? [
                      {'tab_type': 11, 'title': '综合', 'data': []},
                      {'tab_type': 1, 'title': '小说', 'data': []},
                      {'tab_type': 2, 'title': '听书', 'data': []},
                    ]
                  : [
                      {
                        'tab_type': 11,
                        'title': '综合',
                        'has_more': !next,
                        'next_offset': next ? 12 : 6,
                        'passback': 'synthetic-cursor',
                        'data': [
                          {
                            'video_data': [
                              {
                                'series_id': next
                                    ? '7345678901234567001'
                                    : '7345678901234567000',
                                'title': '合成剧',
                                'episode_cnt': 30,
                              },
                            ],
                          },
                        ],
                      },
                    ],
            };
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'x-tt-logid': 'synthetic-ios-log-001',
            },
          );
        });
        final runtime = CatPawJsRuntime(client, recorder, '合成分类故障模拟', false);
        await t.runAsync(() async {
          await runtime.init(script);
          final first = await runtime.search('private-query');
          final second = await runtime.search('private-query', page: 2);
          expect(first.list.single['vod_id'], '7345678901234567000');
          expect(second.list.single['vod_id'], '7345678901234567001');
          expect(tabs, ['29', '11', '11']);
        });
        runtime.dispose();
        client.close();
        rows.add({
          'stage': 'synthetic-general-fallback',
          'tabs': tabs,
          'pages': [1, 1],
        });

        await app.main([]);
        await h.wait(
          t,
          () =>
              find.byType(HomeScreen).evaluate().isNotEmpty &&
              find.byType(CatalogFilters).evaluate().isNotEmpty,
          'home ready',
        );
        await h.tap(t, h.key('toggle-search'));
        for (final query in ['觉醒伪神', '满院亲戚全是上古大妖第四季']) {
          await h.tap(t, find.byType(TextField).first);
          await t.enterText(find.byType(TextField).first, query);
          await t.pump(const Duration(milliseconds: 250));
          expect(
            t.widget<TextField>(find.byType(TextField).first).controller!.text,
            query,
          );
          await h.tap(t, find.byTooltip('搜索').last);
          await t.pump(const Duration(milliseconds: 350));
          await h.wait(
            t,
            () =>
                find.byType(HomeCatalogView).evaluate().isNotEmpty &&
                !h.catalog(t).loading &&
                h.catalog(t).gridKey.endsWith('-$query'),
            'search response',
          );
          final catalog = h.catalog(t);
          expect(catalog.error, isNull);
          expect(catalog.items, isNotEmpty);
          rows.add({
            'stage': 'live-search',
            'query': query,
            'count': catalog.items.length,
          });
          if (catalog.hasMore) {
            final ids = catalog.items.map((d) => d.id).toList();
            for (
              var i = 0;
              i < 15 && h.catalog(t).items.length == ids.length;
              i++
            ) {
              await t.drag(
                find.byType(CustomScrollView).last,
                const Offset(0, -600),
              );
              await t.pump(const Duration(milliseconds: 250));
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
            }
            await h.wait(
              t,
              () =>
                  !h.catalog(t).loadingMore &&
                  (h.catalog(t).items.length > ids.length ||
                      h.catalog(t).error != null ||
                      !h.catalog(t).hasMore),
              'automatic search pagination',
            );
            expect(h.catalog(t).error, isNull);
            expect(h.catalog(t).items.take(ids.length).map((d) => d.id), ids);
            expect(
              h.catalog(t).items.map((d) => d.id).toSet().length,
              h.catalog(t).items.length,
            );
            rows.add({
              'stage': 'live-pagination',
              'query': query,
              'count': h.catalog(t).items.length,
            });
          }
        }
        await binding.takeScreenshot('ios-search');
        await h.tap(t, h.key('home-appbar-settings-button'));
        await h.wait(
          t,
          () => find.byType(SettingsScreen).evaluate().isNotEmpty,
          'settings',
        );
        await h.reveal(t, h.key('settings-source-diagnostics'));
        await h.tap(t, h.key('settings-source-diagnostics'));
        await h.wait(
          t,
          () => find.byType(SourceDiagnosticsPage).evaluate().isNotEmpty,
          'diagnostic page',
        );
        final cachedGuest = CatPawJsRuntime.cachedDeviceSession;
        await h.tap(t, h.key('source-diagnostics-run'));
        await h.wait(
          t,
          () => !SourceDiagnosticRunner.shared.running,
          'live diagnosis',
          seconds: 180,
        );
        expect(SourceDiagnosticRunner.shared.failureCount, 0);
        expect(SourceDiagnosticRunner.shared.successCount, greaterThan(3));
        expect(CatPawJsRuntime.cachedDeviceSession, cachedGuest);
        rows.add({
          'stage': 'active-diagnostic',
          'result': SourceDiagnosticRunner.shared.result,
        });
        for (final entry in recorder.entries) {
          SourceDiagnostics.shared.add(entry);
        }
        await t.pump(const Duration(milliseconds: 350));
        await h.tap(t, h.key('source-diagnostics-copy'));
        final copied = await t.runAsync(
          () => Clipboard.getData(Clipboard.kTextPlain),
        );
        expect(copied?.text, contains('synthetic-ios-log-001'));
        expect(copied?.text, contains('SEARCH_TAB_MISSING'));
        expect(copied?.text, isNot(contains('private-query')));
        expect(copied?.text, contains('1.0.0+262901343'));
        rows.add({'stage': 'copy', 'bytes': utf8.encode(copied!.text!).length});
        await binding.takeScreenshot('ios-diagnostics');
        const nativeUI = bool.fromEnvironment('NATIVE_EXPORT_UI');
        if (nativeUI) {
          for (var attempt = 0; attempt < 2; attempt++) {
            await h.tap(t, h.key('source-diagnostics-export'));
            debugPrint('THL_NATIVE_EXPORT_READY $attempt');
            await h.wait(
              t,
              () => find.text('导出中…').evaluate().isEmpty,
              'native export dismissed $attempt',
              seconds: 240,
            );
            expect(find.text('日志导出失败，请重试；也可复制报告'), findsNothing);
            if (attempt == 1) {
              await h.wait(
                t,
                () => find.text('已完成诊断日志导出').evaluate().isNotEmpty,
                'native file save completed',
              );
            }
            final temporary = Directory.systemTemp
                .listSync()
                .whereType<Directory>()
                .where(
                  (d) => d.path.split('/').last.startsWith('THL-diagnostics-'),
                );
            expect(temporary, isEmpty);
            rows.add({
              'stage': 'native-export',
              'attempt': attempt,
              'completed': attempt == 1,
              'temporaryCleaned': true,
            });
          }
        }
        await h.tap(t, find.byTooltip('返回').last);
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(t.takeException(), isNull);
        binding.reportData = {
          ...?binding.reportData,
          'platform': 'iOS 27',
          'remoteImagesDisabled': true,
          'results': rows,
        };
        debugPrint('THL_DIAGNOSTICS_RESULTS ${jsonEncode(rows)}');
      } finally {
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 13)),
  );
}
