import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

bool accountPrivateAddress(
  InternetAddress address, {
  bool allowLoopback = false,
}) {
  if (address.isLoopback) return allowLoopback;
  var bytes = address.rawAddress;
  if (bytes.length == 16 &&
      bytes.take(10).every((v) => v == 0) &&
      bytes[10] == 255 &&
      bytes[11] == 255) {
    bytes = Uint8List.fromList(bytes.skip(12).toList());
  }
  if (bytes.length == 4) {
    return bytes[0] == 10 ||
        bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31 ||
        bytes[0] == 192 && bytes[1] == 168 ||
        bytes[0] == 169 && bytes[1] == 254;
  }
  return bytes.length == 16 &&
      ((bytes[0] & 254) == 252 || bytes[0] == 254 && (bytes[1] & 192) == 128);
}

Uint8List accountRandom(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

String accountBase64(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
Uint8List accountDecode64(Object? value, {required int max}) {
  if (value is! String ||
      value.length > max * 2 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const FormatException('设备配对数据无效');
  }
  final bytes = base64Url.decode(base64Url.normalize(value));
  if (bytes.length > max) throw const FormatException('设备配对数据过大');
  return bytes;
}

class AccountPairingCode {
  AccountPairingCode({
    required this.id,
    required this.host,
    required this.port,
    required this.name,
    required this.expiresAt,
    required List<int> key,
  }) : _key = Uint8List.fromList(key);
  final String id, host, name;
  final int port;
  final DateTime expiresAt;
  final Uint8List _key;
  factory AccountPairingCode.parse(String raw, {bool allowLoopback = false}) {
    if (raw.length > 1600) throw const FormatException('不是糖葫芦 Haw 登录配对码');
    final uri = Uri.parse(raw);
    if (uri.scheme != 'thlhaw' ||
        uri.host != 'account-pair' ||
        uri.path.isNotEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        uri.queryParameters.keys.any(
          (k) => !{'v', 'host', 'port', 'name', 'id', 'expires'}.contains(k),
        )) {
      throw const FormatException('不是糖葫芦 Haw 登录配对码');
    }
    final q = uri.queryParameters;
    final host = q['host'] ?? '';
    final address = InternetAddress.tryParse(host.split('%').first);
    final port = int.tryParse(q['port'] ?? '');
    final expires = int.tryParse(q['expires'] ?? '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final fragment = Uri.splitQueryString(uri.fragment);
    final key = accountDecode64(fragment['key'], max: 32);
    if (q['v'] != '1' ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(q['id'] ?? '') ||
        address == null ||
        !accountPrivateAddress(address, allowLoopback: allowLoopback) ||
        host.length > 100 ||
        RegExp(r'[^0-9a-fA-F:.%a-zA-Z_-]').hasMatch(host) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        expires == null ||
        expires <= now ||
        expires > now + 180 ||
        fragment.keys.length != 1 ||
        key.length != 32 ||
        (q['name'] ?? '').length > 80) {
      throw const FormatException('设备配对码无效、已过期或不在局域网');
    }
    return AccountPairingCode(
      id: q['id']!,
      host: host,
      port: port,
      name: q['name'] ?? '糖葫芦 Haw',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expires * 1000),
      key: key,
    );
  }
  bool get expired => !expiresAt.isAfter(DateTime.now());
  String encode() => Uri(
    scheme: 'thlhaw',
    host: 'account-pair',
    queryParameters: {
      'v': '1',
      'id': id,
      'host': host,
      'port': '$port',
      'name': name,
      'expires': '${expiresAt.millisecondsSinceEpoch ~/ 1000}',
    },
    fragment: 'key=${accountBase64(_key)}',
  ).toString();
  Uri get endpoint =>
      Uri(scheme: 'http', host: host, port: port, path: '/thl/account-pair/v1');
  Future<SecretKey> _directionKey(bool response) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(_key),
        nonce: utf8.encode(id),
        info: utf8.encode(
          response ? 'THL-HAW/ACCOUNT/v1/server' : 'THL-HAW/ACCOUNT/v1/client',
        ),
      );
  Future<Map<String, dynamic>> seal(
    Map<String, dynamic> payload, {
    required bool response,
  }) async {
    if (expired) throw const FormatException('设备配对已过期');
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: await _directionKey(response),
      nonce: accountRandom(12),
      aad: utf8.encode(
        'THL-HAW/ACCOUNT/v1/$id/${response ? 'response' : 'request'}',
      ),
    );
    return {
      'v': 1,
      'id': id,
      'nonce': accountBase64(box.nonce),
      'cipher': accountBase64(box.cipherText),
      'tag': accountBase64(box.mac.bytes),
    };
  }

  Future<Map<String, dynamic>> open(
    Map<String, dynamic> envelope, {
    required bool response,
  }) async {
    if (expired ||
        envelope['v'] != 1 ||
        envelope['id'] != id ||
        envelope.keys.any(
          (k) => !{'v', 'id', 'nonce', 'cipher', 'tag'}.contains(k),
        )) {
      throw const FormatException('设备配对数据无效');
    }
    final nonce = accountDecode64(envelope['nonce'], max: 12),
        tag = accountDecode64(envelope['tag'], max: 16),
        cipher = accountDecode64(envelope['cipher'], max: 68 * 1024);
    if (nonce.length != 12 || tag.length != 16) {
      throw const FormatException('设备配对数据无效');
    }
    final bytes = await AesGcm.with256bits().decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
      secretKey: await _directionKey(response),
      aad: utf8.encode(
        'THL-HAW/ACCOUNT/v1/$id/${response ? 'response' : 'request'}',
      ),
    );
    if (bytes.length > 68 * 1024) throw const FormatException('设备配对数据过大');
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map) throw const FormatException('设备配对数据无效');
    return Map<String, dynamic>.from(data);
  }

  @override
  String toString() => 'AccountPairingCode([redacted])';
}
