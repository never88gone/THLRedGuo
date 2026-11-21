import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

String lanID() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Object? canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonicalJson(value[key])};
  }
  if (value is List) return value.map(canonicalJson).toList();
  return value;
}

String lanJSON(Object? value) => jsonEncode(canonicalJson(value));

String lanHash(Object? value) =>
    sha256.convert(utf8.encode(lanJSON(value))).toString();

Map<String, dynamic> lanMap(Object? value) {
  if (value is! Map) throw const FormatException('设备返回的记录格式无效');
  return Map<String, dynamic>.from(value);
}

String lanText(Object? value, int limit, {bool empty = false}) {
  if (value is! String ||
      (!empty && value.trim().isEmpty) ||
      value.length > limit ||
      value.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'))) {
    throw const FormatException('设备返回的文字字段无效');
  }
  return value;
}
