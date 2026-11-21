import 'dart:math';

import 'package:THLRedLook/models/lan/lan_common.dart';

class LanVersion {
  LanVersion(Map<String, int> values) : values = Map.unmodifiable(values);
  final Map<String, int> values;

  factory LanVersion.fromJson(Object? value) {
    final map = lanMap(value);
    if (map.isEmpty || map.length > 64) {
      throw const FormatException('同步版本数量无效');
    }
    final result = <String, int>{};
    for (final entry in map.entries) {
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(entry.key) ||
          entry.value is! int ||
          (entry.value as int) <= 0 ||
          (entry.value as int) >= 9007199254740000) {
        throw const FormatException('同步版本无效');
      }
      result[entry.key] = entry.value as int;
    }
    return LanVersion(result);
  }

  bool includes(LanVersion other) => other.values.entries.every(
    (entry) => (values[entry.key] ?? 0) >= entry.value,
  );

  LanVersion join(LanVersion other) {
    final keys = {...values.keys, ...other.values.keys};
    if (keys.length > 64) throw StateError('同步设备数量已达上限');
    return LanVersion({
      for (final key in keys)
        key: max(values[key] ?? 0, other.values[key] ?? 0),
    });
  }

  Map<String, int> toJson() => values;
}
