import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;

import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';

class HawCastDiscoveryHelper {
  static Map<String, HawCastDevice> parseServices(
    List<nsd.Service> services, {
    required int defaultPort,
  }) {
    final nextMap = <String, HawCastDevice>{};
    for (final service in services) {
      final port = service.port ?? defaultPort;
      if (port <= 0) continue;

      final host = pickBestHost(service);
      if (host == null || host.isEmpty) continue;

      final txt = service.txt ?? const {};
      String readTxt(String key) {
        final raw = txt[key];
        if (raw == null || raw.isEmpty) return '';
        return utf8.decode(raw, allowMalformed: true).trim();
      }

      final proto = readTxt('proto');
      if (proto.isNotEmpty && proto != 'haw') continue;

      final rawName = service.name?.trim() ?? '';
      final name = rawName.isNotEmpty ? rawName : '糖葫芦接收器 ($host)';
      final model = readTxt('model').isNotEmpty ? readTxt('model') : 'THLPlay';
      final capsStr = readTxt('caps');
      final caps = capsStr.isNotEmpty
          ? capsStr
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList()
          : const ['aes128', 'hls', 'mp4'];

      final id = '$host:$port';
      nextMap[id] = HawCastDevice(
        id: id,
        name: name,
        host: host,
        port: port,
        model: model,
        caps: caps,
      );
    }
    return nextMap;
  }

  static String? pickBestHost(nsd.Service service) {
    final addrs = service.addresses ?? const <InternetAddress>[];
    String? linkLocalIpv4;
    String? otherIpv4;
    String? fallbackIpv6;
    for (final addr in addrs) {
      if (addr.isLoopback) continue;
      if (addr.type == InternetAddressType.IPv4) {
        final ip = addr.address;
        if (ip.startsWith('169.254.')) {
          linkLocalIpv4 ??= ip;
        } else if (ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            _isPrivate172(ip)) {
          return ip;
        } else {
          otherIpv4 ??= ip;
        }
      } else if (!addr.isLinkLocal && fallbackIpv6 == null) {
        fallbackIpv6 = addr.address;
      }
    }
    if (otherIpv4 != null) return otherIpv4;
    if (linkLocalIpv4 != null) return linkLocalIpv4;
    if (fallbackIpv6 != null) return fallbackIpv6;
    final host = service.host?.trim();
    if (host != null && host.isNotEmpty) {
      return host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    }
    return null;
  }

  static bool _isPrivate172(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }

  static Future<HawCastDevice?> probeManualDevice(
    http.Client client,
    String input, {
    required int defaultPort,
    required Duration timeout,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    var host = trimmed;
    var port = defaultPort;
    if (trimmed.startsWith('[')) {
      final endBracket = trimmed.indexOf(']');
      if (endBracket > 1) {
        host = trimmed.substring(1, endBracket);
        if (endBracket + 1 < trimmed.length && trimmed[endBracket + 1] == ':') {
          port = int.tryParse(trimmed.substring(endBracket + 2)) ?? defaultPort;
        }
      }
    } else if (trimmed.contains(':') &&
        trimmed.indexOf(':') == trimmed.lastIndexOf(':')) {
      final parts = trimmed.split(':');
      host = parts[0].trim();
      port = int.tryParse(parts[1].trim()) ?? defaultPort;
    }

    if (host.isEmpty) return null;
    final formattedHost = host.contains(':') ? '[$host]' : host;
    final uri = Uri.parse('http://$formattedHost:$port/thl/info');

    try {
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;

      final name = decoded['name']?.toString().trim();
      final model = decoded['model']?.toString().trim();
      final capsRaw = decoded['caps'];
      final caps = capsRaw is List
          ? capsRaw.map((e) => e.toString()).toList()
          : const ['aes128', 'hls', 'mp4'];

      return HawCastDevice(
        id: '$host:$port',
        name: (name != null && name.isNotEmpty) ? name : '糖葫芦接收器 ($host)',
        host: host,
        port: port,
        model: (model != null && model.isNotEmpty) ? model : 'THLPlay',
        caps: caps,
        manual: true,
      );
    } catch (e) {
      DiaryService.add('[Cast] 手动探测 $host:$port 失败: $e');
      return null;
    }
  }
}
