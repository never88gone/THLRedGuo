import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'source_diagnostics.dart';

class DiagnosticLogExporter {
  static Future<bool> export(String report) async {
    final content = SourceDiagnostics.redact(report);
    final bytes = Uint8List.fromList(utf8.encode(content));
    if (bytes.isEmpty || bytes.length > 512 * 1024) {
      throw const FormatException('诊断报告为空或超过大小限制');
    }
    if (Platform.isIOS) {
      final result = await const MethodChannel('duanju/device')
          .invokeMapMethod<String, dynamic>('exportDiagnostics', {
            'report': content,
          });
      return result?['completed'] == true;
    }
    final saved = await FilePicker.saveFile(
      fileName:
          'THL-diagnostics-${DateTime.now().toUtc().millisecondsSinceEpoch}.txt',
      bytes: bytes,
      mimeType: 'text/plain',
    );
    return saved != null;
  }
}
