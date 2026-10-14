import 'dart:io';
import 'dart:ui' as ui;

import 'package:THLRedLook/app_theme.dart';
import 'package:THLRedLook/pages/privacy/privacy_lock_page.dart';
import 'package:THLRedLook/pages/privacy/privacy_settings_page.dart';
import 'package:THLRedLook/utils/privacy/privacy_lock_controller.dart';
import 'package:THLRedLook/views/privacy/pattern_lock_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadRealFonts() async {
  const iconPath =
      '/Users/never88gone/fvm/versions/3.44.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(iconPath).existsSync()) {
    final iconFont = FontLoader('MaterialIcons');
    final iconBytes = File(iconPath).readAsBytesSync();
    iconFont.addFont(Future.value(ByteData.view(iconBytes.buffer)));
    await iconFont.load();
  }

  const chineseCandidates = [
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    '/System/Library/Fonts/STHeiti Medium.ttc',
  ];
  Uint8List? fontBytes;
  for (final candidate in chineseCandidates) {
    if (File(candidate).existsSync()) {
      try {
        fontBytes = File(candidate).readAsBytesSync();
        break;
      } catch (_) {}
    }
  }

  if (fontBytes != null) {
    for (final family in [
      'Hiragino Sans GB',
      'Roboto',
      '.SF NS',
      '.AppleSystemUIFont',
    ]) {
      try {
        final fontLoader = FontLoader(family);
        fontLoader.addFont(Future.value(ByteData.view(fontBytes.buffer)));
        await fontLoader.load();
      } catch (_) {}
    }
  }
}

Future<void> _captureAndSave(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String fileName,
) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  expect(boundary, isNotNull);

  await tester.runAsync(() async {
    final image = await boundary!.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(byteData, isNotNull);
    final pngBytes = byteData!.buffer.asUint8List();

    final paths = [
      'build/screenshots/$fileName',
      '/Users/never88gone/.gemini/antigravity/brain/1edf4dcb-87c2-413f-80c9-ef1b7fd70e27/$fileName',
    ];

    for (final p in paths) {
      final file = File(p);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(pngBytes);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  group('隐私模式 UI 截图套件', () {
    testWidgets('13. 移动端「九宫格手势解锁遮罩」(13_privacy_lock_page.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = PrivacyLockController(prefs);
      await controller.saveGesture([0, 1, 2, 5, 8]);
      controller.lock();

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RepaintBoundary(
            key: key,
            child: PrivacyLockPage(controller: controller),
          ),
        ),
      );

      final centerFinder = find.byType(PatternLockView);
      final center = tester.getCenter(centerFinder);
      final cell = 300.0 / 3;

      final gesture = await tester.startGesture(Offset(center.dx - cell, center.dy - cell));
      await gesture.moveTo(Offset(center.dx, center.dy - cell));
      await gesture.moveTo(Offset(center.dx + cell, center.dy - cell));
      await tester.pump(const Duration(milliseconds: 30));

      await _captureAndSave(tester, key, '13_privacy_lock_page.png');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('14. 移动端「隐私模式与手势锁设置」(14_privacy_settings_page.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = PrivacyLockController(prefs);
      await controller.saveGesture([0, 1, 2, 5, 8]);

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RepaintBoundary(
            key: key,
            child: PrivacySettingsPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, key, '14_privacy_settings_page.png');
    });
  });
}
