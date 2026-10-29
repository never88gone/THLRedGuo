import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/home/home_catalog_view.dart';
import 'package:THLRedLook/views/player/player_viewport_view.dart';

Future<void> wait(
  WidgetTester t,
  bool Function() done,
  String name, {
  int seconds = 90,
}) async {
  debugPrint('UI_WAIT $name');
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done() && DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  if (!done()) {
    final texts = t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .take(70)
        .toList();
    debugPrint('UI_TIMEOUT $name ${jsonEncode(texts)}');
  }
  expect(done(), isTrue, reason: name);
}

Finder key(String value) => find.byKey(ValueKey(value));
Finder get tiles => find.byType(DramaTile);
Future<void> tap(WidgetTester t, Finder f) async {
  expect(f, findsWidgets);
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 350));
}

Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    final scroll = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .last;
    await t.scrollUntilVisible(f, 300, scrollable: scroll, maxScrolls: 35);
  }
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 250));
}

HomeCatalogView catalog(WidgetTester t) =>
    t.widget<HomeCatalogView>(find.byType(HomeCatalogView).last);
PlayerViewportView viewport(WidgetTester t) =>
    t.widget<PlayerViewportView>(find.byType(PlayerViewportView).last);
Future<void> controls(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  if (find
      .byKey(const ValueKey('player-toggle'))
      .hitTestable()
      .evaluate()
      .isEmpty) {
    final rect = tester.getRect(
      find.byKey(const ValueKey('player-gesture-surface')),
    );
    await tester.tapAt(
      Offset(rect.left + rect.width * .08, rect.top + rect.height * .45),
    );
    await tester.pump(const Duration(milliseconds: 350));
  }
  await wait(
    tester,
    () => find
        .byKey(const ValueKey('player-toggle'))
        .hitTestable()
        .evaluate()
        .isNotEmpty,
    'controls within viewport',
  );
}

Future<void> seekWithSlider(WidgetTester tester, double seconds) async {
  await controls(tester);
  final slider = find.byKey(const ValueKey('player-progress'));
  final widget = tester.widget<Slider>(slider);
  final rect = tester.getRect(slider);
  final fraction = seconds / widget.max;
  await tester.tapAt(
    Offset(rect.left + 24 + (rect.width - 48) * fraction, rect.center.dy),
  );
  await tester.pump(const Duration(milliseconds: 400));
}
