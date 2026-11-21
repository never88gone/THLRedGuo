import 'dart:math';

import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/models/lan/lan_common.dart';
import 'package:THLRedLook/models/lan/lan_version.dart';

class LanValue {
  const LanValue(this.version, this.value);
  final LanVersion version;
  final Object? value;
  Map<String, dynamic> toJson() => {'v': version.toJson(), 'value': value};
  factory LanValue.fromJson(Object? value) {
    final row = lanMap(value);
    return LanValue(LanVersion.fromJson(row['v']), row['value']);
  }
}

class LanCell {
  LanCell(Iterable<LanValue> values)
    : values = List.unmodifiable(
        values.toList()
          ..sort((a, b) => lanJSON(a.toJson()).compareTo(lanJSON(b.toJson()))),
      );
  final List<LanValue> values;
  bool get conflict => values.length > 1;
  Object? get value => values.first.value;
  LanVersion get version =>
      values.map((entry) => entry.version).reduce((a, b) => a.join(b));

  factory LanCell.fromJson(Object? value) {
    if (value is! List || value.isEmpty || value.length > 32) {
      throw const FormatException('同步字段无效');
    }
    final candidates = value.map(LanValue.fromJson).toList();
    for (var i = 0; i < candidates.length; i++) {
      for (var j = i + 1; j < candidates.length; j++) {
        if (candidates[i].version.includes(candidates[j].version) ||
            candidates[j].version.includes(candidates[i].version) ||
            lanJSON(candidates[i].value) == lanJSON(candidates[j].value)) {
          throw const FormatException('同步冲突候选重复或包含过期版本');
        }
      }
    }
    candidates
        .map((candidate) => candidate.version)
        .reduce((a, b) => a.join(b));
    return LanCell(candidates);
  }

  LanCell merge(LanCell other) {
    final candidates = <LanValue>[];
    for (final incoming in [...values, ...other.values]) {
      var current = incoming;
      if (candidates.any(
        (candidate) => candidate.version.includes(current.version),
      )) {
        final equalVersion = candidates.where(
          (candidate) => current.version.includes(candidate.version),
        );
        if (equalVersion.any(
          (candidate) => lanJSON(candidate.value) != lanJSON(current.value),
        )) {
          throw const FormatException('相同同步版本的内容不一致');
        }
        continue;
      }
      candidates.removeWhere(
        (candidate) => current.version.includes(candidate.version),
      );
      final identical = candidates
          .where(
            (candidate) => lanJSON(candidate.value) == lanJSON(current.value),
          )
          .toList();
      for (final candidate in identical) {
        current = LanValue(
          current.version.join(candidate.version),
          current.value,
        );
        candidates.remove(candidate);
      }
      candidates.removeWhere(
        (candidate) => current.version.includes(candidate.version),
      );
      candidates.add(current);
    }
    if (candidates.length > 32) {
      throw StateError('这条记录的冲突过多，请先处理已有冲突');
    }
    return LanCell(candidates);
  }

  LanCell edit(String replica, int counter, Object? value) {
    final next = Map.of(version.values);
    next[replica] = max(next[replica] ?? 0, counter);
    if (next.length > 64) throw StateError('同步设备数量已达上限');
    return LanCell([LanValue(LanVersion(next), value)]);
  }

  List<Map<String, dynamic>> toJson() =>
      values.map((entry) => entry.toJson()).toList();
}

Drama lanDrama(Object? input) {
  final row = lanMap(input);
  final source = lanText(row['source'], 32);
  if (!SourceSite.isKnown(source)) {
    throw const FormatException('记录站源无效');
  }
  final id = lanText(row['id'], 512);
  final sourceId = lanText(row['sourceId'], 450, empty: true);
  if (!id.startsWith('$source:') ||
      id.length <= source.length + 1 ||
      sourceId.isNotEmpty && id != '$source:$sourceId') {
    throw const FormatException('剧目身份不一致');
  }
  final count = row['episodes'];
  if (count is! int || count < 0 || count > 1000000) {
    throw const FormatException('剧目集数无效');
  }
  for (final key in [
    'description',
    'cover',
    'category',
    'heat',
    'views',
    'onlineDate',
    'releaseStatus',
  ]) {
    lanText(row[key] ?? '', key == 'description' ? 4000 : 2048, empty: true);
  }
  lanText(row['title'], 300);
  final tags = row['tags'] ?? [];
  if (tags is! List || tags.length > 32) {
    throw const FormatException('剧目标签无效');
  }
  for (final tag in tags) {
    lanText(tag, 100);
  }
  final cover = row['cover'] as String? ?? '';
  if (cover.isNotEmpty) {
    final uri = Uri.tryParse(cover);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('剧目封面地址无效');
    }
  }
  return Drama.fromJson(row);
}

Drama lanCompactDrama(Drama drama) {
  String cut(String text, int length) =>
      text.length <= length ? text : text.substring(0, length);
  final row = drama.toJson();
  row['description'] = cut(drama.description, 4000);
  row['title'] = cut(drama.title, 300);
  row['tags'] = drama.tags.take(32).map((tag) => cut(tag, 100)).toList();
  if (drama.cover.length > 2048 ||
      !{'http', 'https'}.contains(Uri.tryParse(drama.cover)?.scheme)) {
    row['cover'] = '';
  }
  return lanDrama(row);
}

Map<String, dynamic>? lanProgress(WatchEntry? entry) => entry == null
    ? null
    : {
        'episode': entry.episode,
        'position': (entry.position * 1000).round() / 1000,
        'duration': (entry.duration * 1000).round() / 1000,
        'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
      };

void validateCell(String field, LanCell cell) {
  for (final candidate in cell.values) {
    final value = candidate.value;
    if (field == 'member') {
      if (value is! bool) throw const FormatException('追剧成员字段无效');
    } else if (field == 'status') {
      final status = lanMap(value);
      if (status.length != 2 ||
          !FollowStatus.values.any((value) => value.name == status['status']) ||
          status['manual'] is! bool ||
          status['manual'] == true && status['status'] != 'watched') {
        throw const FormatException('追剧状态无效');
      }
    } else if (value != null) {
      final progress = lanMap(value);
      final episode = progress['episode'];
      final position = progress['position'];
      final duration = progress['duration'];
      if (progress.length != 4 ||
          episode is! int ||
          episode < 1 ||
          episode > 1000000 ||
          position is! num ||
          !position.isFinite ||
          position < 0 ||
          position > 604800 ||
          duration is! num ||
          !duration.isFinite ||
          duration < 0 ||
          duration > 604800 ||
          progress['updatedAt'] is! String ||
          (progress['updatedAt'] as String).length > 48 ||
          DateTime.tryParse(progress['updatedAt'] as String) == null) {
        throw const FormatException('续播进度无效');
      }
    }
  }
}
