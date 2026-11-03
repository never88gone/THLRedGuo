import 'dart:convert';
import 'dart:typed_data';
import 'hongguo_account_session.dart';

class AccountTransferPayload {
  AccountTransferPayload._(this.id, this.cookies, this.device);
  final String id;
  final HongguoAccountCookies cookies;
  final String device;
  factory AccountTransferPayload.decode(List<int> bytes) {
    if (bytes.length > 48 * 1024) throw const FormatException('账号会话过大');
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map ||
        value['v'] != 1 ||
        value.keys.any((k) => !{'v', 'id', 'cookies', 'device'}.contains(k)) ||
        value['id'] is! String ||
        !RegExp(r'^\d{1,30}$').hasMatch(value['id'] as String)) {
      throw const FormatException('账号会话格式无效');
    }
    final rawCookies = value['cookies'];
    final rawDevice = value['device'];
    if (rawCookies is! List ||
        rawCookies.isEmpty ||
        rawCookies.length > 16 ||
        rawDevice is! Map ||
        rawDevice.keys.any((k) => !{'iid', 'device_id', 'cdid'}.contains(k))) {
      throw const FormatException('账号会话格式无效');
    }
    for (final key in ['iid', 'device_id']) {
      if (rawDevice[key] is! String ||
          !RegExp(r'^\d{10,24}$').hasMatch(rawDevice[key] as String)) {
        throw const FormatException('账号设备上下文无效');
      }
    }
    if (rawDevice['cdid'] is! String ||
        (rawDevice['cdid'] as String).isEmpty ||
        (rawDevice['cdid'] as String).length > 80) {
      throw const FormatException('账号设备上下文无效');
    }
    final rows = <Map<String, dynamic>>[];
    final names = <String>{};
    for (final row in rawCookies) {
      if (row is! Map ||
          row.keys.any(
            (k) => !{'name', 'value', 'domain', 'path', 'expires'}.contains(k),
          ) ||
          !HongguoAccountCookies.credentialNames.contains(row['name']) ||
          row['value'] is! String ||
          (row['value'] as String).isEmpty ||
          (row['value'] as String).length > 4096 ||
          RegExp(
            r'[^\x21\x23-\x2b\x2d-\x3a\x3c-\x5b\x5d-\x7e]',
          ).hasMatch(row['value'] as String) ||
          row['domain'] != 'hongguoduanju.com' ||
          row['path'] != '/' ||
          row['expires'] != null && row['expires'] is! num ||
          !names.add(row['name'] as String)) {
        throw const FormatException('账号会话格式无效');
      }
      rows.add(Map<String, dynamic>.from(row));
    }
    final cookies = HongguoAccountCookies(rows);
    if (!cookies.hasSession) throw const FormatException('账号会话已失效');
    return AccountTransferPayload._(
      value['id'] as String,
      cookies,
      jsonEncode(rawDevice),
    );
  }
  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'id': id,
        'cookies': cookies.toJson(),
        'device': jsonDecode(device),
      }),
    ),
  );
  @override
  String toString() => 'AccountTransferPayload([redacted])';
}
