import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/views/player/player_quality_sheet_view.dart';

void main() {
  for (final qualities in <List<int>>[
    [540, 360],
    [],
    [1080, 720, 540, 480, 360],
  ]) {
    testWidgets('quality menu shows source-provided choices $qualities', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerQualitySheetView(
              qualities: qualities,
              selectedQuality: 0,
              actualQuality: qualities.firstOrNull ?? 0,
              isLocal: false,
              onQualitySelected: (q) => selected = q,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quality-option-0')), findsOneWidget);
      if (!qualities.contains(1080)) {
        expect(find.byKey(const ValueKey('quality-option-1080')), findsNothing);
      }
      if (qualities.isNotEmpty) {
        final option = find.byKey(
          ValueKey('quality-option-${qualities.first}'),
        );
        await tester.ensureVisible(option);
        await tester.tap(option);
        expect(selected, qualities.first);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
