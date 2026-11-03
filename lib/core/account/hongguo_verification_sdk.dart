import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../diagnostics/source_diagnostics.dart';
import 'hongguo_account_session.dart';

class HongguoVerificationSdk {
  static const urls = [
    'https://lf-rc1.yhgfb-cn-static.com/obj/rc-verifycenter/verifycenter/@latest/index.js',
    'https://lf-rc2.yhgfb-cn-static.com/obj/rc-verifycenter/verifycenter/@latest/index.js',
    'https://lf-cdn-tos.bytescm.com/obj/rc-verifycenter/verifycenter/@latest/index.js',
  ];
  static Future<String>? _pending;
  static String? _cached;
  static DateTime _expires = DateTime(2000);
  static Future<String> load() async {
    if (_cached != null && _expires.isAfter(DateTime.now())) return _cached!;
    return _pending ??= () async {
      try {
        _cached = await download();
        _expires = DateTime.now().add(const Duration(minutes: 30));
        return _cached!;
      } finally {
        _pending = null;
      }
    }();
  }

  static Future<String> download() async {
    for (final address in urls) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final source = await (() async {
          final request = await client.getUrl(Uri.parse(address));
          request.followRedirects = false;
          final response = await request.close();
          if (response.statusCode != 200) {
            throw const FormatException();
          }
          final bytes = <int>[];
          await for (final chunk in response) {
            if (bytes.length + chunk.length > 256 * 1024) {
              throw const FormatException();
            }
            bytes.addAll(chunk);
          }
          final source = utf8.decode(bytes);
          if (source.length < 1024 || !source.contains('verifySDK')) {
            throw const FormatException();
          }
          return source;
        })().timeout(const Duration(seconds: 10));
        return source;
      } catch (_) {
        SourceDiagnostics.shared.add(
          SourceDiagnosticEntry(
            at: DateTime.now(),
            context: '红果登录',
            stage: '验证组件加载',
            host: Uri.parse(address).host,
            errorCode: 'VERIFICATION_SDK_FETCH',
          ),
        );
      } finally {
        client.close(force: true);
      }
    }
    throw const HongguoAccountFailure(
      '官方验证组件暂时无法加载，请检查网络或使用红果 App 扫码登录',
      'VERIFICATION_SDK_UNAVAILABLE',
    );
  }
}
