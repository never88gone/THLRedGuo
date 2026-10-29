import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final root = Directory('build/verification/flutter-guest-20261029');
  await root.create(recursive: true);
  final run = Platform.environment['THL_GUEST_UI_RUN'] ?? '';
  final suffix = RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(run) ? '-$run' : '';
  await integrationDriver(
    timeout: const Duration(minutes: 40),
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      if (data == null) return;
      for (final raw in data['screenshots'] as List? ?? const []) {
        final shot = Map<String, dynamic>.from(raw as Map);
        final name = shot['screenshotName'] as String;
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) continue;
        await File(
          '${root.path}/$name.png',
        ).writeAsBytes((shot['bytes'] as List).cast<int>());
      }
      final result = Map<String, dynamic>.from(data)..remove('screenshots');
      await File(
        '${root.path}/ui-results$suffix.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    },
  );
}
