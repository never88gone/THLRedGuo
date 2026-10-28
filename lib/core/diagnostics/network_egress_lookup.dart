import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class NetworkEgressResult {
  const NetworkEgressResult({
    required this.at,
    this.ip = '',
    this.country = '',
    this.countryCode = '',
    this.region = '',
    this.city = '',
    this.provider = '',
    this.error = '',
  });
  final DateTime at;
  final String ip;
  final String country;
  final String countryCode;
  final String region;
  final String city;
  final String provider;
  final String error;
  static const notice = 'IP 归属地由查询服务估算；代理分流时可能与红果接口出口不同，不能单独证明风控。';
  String get location {
    final values = [country, region, city].where((value) => value.isNotEmpty);
    return values.isEmpty ? '归属地未知' : values.join(' · ');
  }

  String get summary => ip.isEmpty
      ? '出口 IP：检测失败（$error）'
      : '出口 IP：$ip · $location${countryCode.isEmpty ? '' : ' [$countryCode]'}';
  List<String> get reportLines => [
    '  - 出口 IP: ${ip.isEmpty ? '未取得' : ip}',
    '  - IP 归属地区: $location${countryCode.isEmpty ? '' : ' [$countryCode]'}',
    '  - IP 查询来源: $provider',
    '  - IP 检测时间: ${at.toUtc().toIso8601String()}',
    if (error.isNotEmpty) '  - IP 检测状态: $error',
    '  - IP 说明: $notice',
  ];
}

class NetworkEgressLookup {
  const NetworkEgressLookup({this.client});
  final http.Client? client;

  static NetworkEgressResult? parse(
    String body, {
    required String provider,
    DateTime? at,
  }) {
    if (utf8.encode(body).length > 32768) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map || data['success'] == false) return null;
      final ip = data['ip'];
      if (ip is! String || InternetAddress.tryParse(ip) == null) return null;
      String text(String key) =>
          (data[key] is String ? data[key] as String : '')
              .replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), '')
              .trim()
              .runes
              .take(100)
              .map(String.fromCharCode)
              .join();
      final code = text('country_code').toUpperCase();
      return NetworkEgressResult(
        at: at ?? DateTime.now().toUtc(),
        ip: ip,
        country: text('country'),
        countryCode: RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : '',
        region: text('region'),
        city: text('city'),
        provider: provider,
      );
    } catch (_) {
      return null;
    }
  }

  Future<NetworkEgressResult> lookup() async {
    final transport = client ?? http.Client();
    final failures = <String>[];
    try {
      for (final provider in [
        ('IP.SB', 'https://api.ip.sb/geoip'),
        ('IPWho.is', 'https://ipwho.is/'),
      ]) {
        final abort = Completer<void>();
        final timer = Timer(const Duration(seconds: 4), () {
          if (!abort.isCompleted) abort.complete();
        });
        try {
          final request =
              http.AbortableRequest(
                  'GET',
                  Uri.parse(provider.$2),
                  abortTrigger: abort.future,
                )
                ..headers.addAll({
                  'Accept': 'application/json',
                  'User-Agent': 'THLRedLook/1.0.0 diagnostics',
                });
          final response = await transport
              .send(request)
              .timeout(const Duration(seconds: 4));
          final bytes = <int>[];
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 4),
          )) {
            if (bytes.length + chunk.length > 32768) {
              throw const FormatException('RESPONSE_TOO_LARGE');
            }
            bytes.addAll(chunk);
          }
          if (response.statusCode != 200) {
            failures.add('${provider.$1}: HTTP_${response.statusCode}');
            continue;
          }
          final result = parse(utf8.decode(bytes), provider: provider.$1);
          if (result != null) return result;
          failures.add('${provider.$1}: INVALID_RESPONSE');
        } catch (error) {
          failures.add(
            '${provider.$1}: ${error is TimeoutException || abort.isCompleted
                ? 'TIMEOUT'
                : error is FormatException
                ? 'INVALID_RESPONSE'
                : 'CONNECTION'}',
          );
        } finally {
          timer.cancel();
          if (!abort.isCompleted) abort.complete();
        }
      }
    } finally {
      if (client == null) transport.close();
    }
    return NetworkEgressResult(
      at: DateTime.now().toUtc(),
      provider: 'IP.SB / IPWho.is',
      error: failures.join('; '),
    );
  }
}
