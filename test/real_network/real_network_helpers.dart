import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:THLRedLook/core_bridge.dart';
import 'package:THLRedLook/js_source_presets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;

/// macOS 下动态库与 Frameworks 加载辅助
class MacOSFrameworkLoader {
  static bool _initialized = false;

  static void ensureFrameworksLoaded() {
    if (_initialized) return;
    _initialized = true;

    final candidates = [
      path.normalize(path.join(path.dirname(Platform.resolvedExecutable), '..', 'Frameworks')),
      path.join(Directory.current.path, 'build/macos/Build/Products/Debug/THLRedLook.app/Contents/Frameworks'),
      path.join(Directory.current.path, 'build/macos/Build/Products/Release/THLRedLook.app/Contents/Frameworks'),
      '/Volumes/MacintoshData/Work/Github/guoapp1/build/macos/Build/Products/Debug/THLRedLook.app/Contents/Frameworks',
      path.join(Directory.current.path, 'build/macos/Build/Products/Debug/duanju_app.app/Contents/Frameworks'),
      '/Volumes/MacintoshData/Work/Github/guoapp1/build/macos/Build/Products/Debug/duanju_app.app/Contents/Frameworks',
    ];

    String frameworksDir = '';
    for (final candidate in candidates) {
      if (File(path.join(candidate, 'Mpv.framework/Mpv')).existsSync()) {
        frameworksDir = candidate;
        break;
      }
    }

    final topologicalLibs = [
      // Layer 1: Independent frameworks
      'Png16.framework/Png16',
      'Harfbuzz.framework/Harfbuzz',
      'Fribidi.framework/Fribidi',
      'Dav1d.framework/Dav1d',
      'Xml2.framework/Xml2',
      'Uchardet.framework/Uchardet',
      'Mbedcrypto.framework/Mbedcrypto',
      'Avutil.framework/Avutil',
      // Layer 2: Low-level dependents
      'Freetype.framework/Freetype',
      'Mbedx509.framework/Mbedx509',
      'Swresample.framework/Swresample',
      'Swscale.framework/Swscale',
      'Avfilter.framework/Avfilter',
      // Layer 3: Mid-level codecs
      'Ass.framework/Ass',
      'Mbedtls.framework/Mbedtls',
      'Avcodec.framework/Avcodec',
      // Layer 4: Demuxers and formats
      'Avformat.framework/Avformat',
      // Layer 5: Mpv engine
      'Mpv.framework/Mpv',
    ];

    try {
      if (frameworksDir.isNotEmpty) {
        for (final lib in topologicalLibs) {
          final fullPath = path.join(frameworksDir, lib);
          if (File(fullPath).existsSync()) {
            try {
              DynamicLibrary.open(fullPath);
            } catch (e) {
              stderr.writeln('Warning: Failed to load $fullPath: $e');
            }
          }
        }
        final mpvPath = path.join(frameworksDir, 'Mpv.framework/Mpv');
        MediaKit.ensureInitialized(libmpv: mpvPath);
      } else {
        MediaKit.ensureInitialized();
      }
    } catch (e) {
      stderr.writeln('Warning: MediaKit.ensureInitialized skipped: $e');
    }
  }
}

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

/// 真实网络测试环境脚手架
class RealNetworkFixture {
  static Future<NativeRepository> setup() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = _RealHttpOverrides();

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    });

    MacOSFrameworkLoader.ensureFrameworksLoaded();

    final repo = NativeRepository();
    await repo.initialize();
    final hongguoPreset = kPresetJsSources.firstWhere((s) => s.id == 'hongguo');
    await repo.jsSourceSaveAndLoad(hongguoPreset.script, hongguoPreset.fileName);
    await repo.jsSourceSetActive('hongguo');
    return repo;
  }
}

/// 网络请求抓包与数据特征记录器
class NetworkTraceRecorder {
  final List<Map<String, dynamic>> records = [];

  void record({
    required String action,
    required String endpoint,
    required Map<String, dynamic> params,
    required Map<String, dynamic> responseSummary,
    int? latencyMs,
  }) {
    final entry = {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'endpoint': endpoint,
      'params': params,
      'latencyMs': latencyMs ?? 0,
      'response': responseSummary,
    };
    records.add(entry);
  }

  Future<void> saveToFile(String targetPath) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(records);
    await file.writeAsString(jsonStr);
  }
}

/// 播放器状态流转记录器
class PlayerStateLogger {
  final List<String> logs = [];
  final Stopwatch _stopwatch = Stopwatch()..start();

  void log(String event, {Map<String, dynamic>? details}) {
    final elapsed = _stopwatch.elapsedMilliseconds;
    final buffer = StringBuffer();
    buffer.write('[$elapsed ms] [PlayerEvent] $event');
    if (details != null && details.isNotEmpty) {
      buffer.write(' | Details: ${jsonEncode(details)}');
    }
    final line = buffer.toString();
    logs.add(line);
    print(line);
  }

  Future<void> saveToFile(String targetPath) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(logs.join('\n'));
  }
}
