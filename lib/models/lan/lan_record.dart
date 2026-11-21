import 'dart:convert';
import 'dart:math';

import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/models/lan/lan_cell.dart';
import 'package:THLRedLook/models/lan/lan_common.dart';

class LanRecord {
  LanRecord({
    required this.drama,
    required this.member,
    required this.status,
    required this.progress,
    this.known = 0,
    this.read,
  });
  final Drama drama;
  final LanCell member;
  final LanCell status;
  final LanCell progress;
  final int known;
  final int? read;
  String get id => drama.id;
  bool get followed => member.values.every((value) => value.value == true);
  int get conflicts =>
      [member, status, progress].where((cell) => cell.conflict).length;
  late final String hash = lanHash(toJson());
  Map<String, LanCell> get fields => {
    'member': member,
    'status': status,
    'progress': progress,
  };

  FollowState get following {
    final value = lanMap(status.value);
    return FollowState(
      status: FollowStatus.values.firstWhere(
        (status) => status.name == value['status'],
      ),
      manuallyWatched: value['manual'] == true,
      knownEpisodes: known,
      readEpisodes: read,
    );
  }

  WatchEntry? get watch => progress.value == null
      ? null
      : WatchEntry.fromJson({
          ...lanMap(progress.value),
          'drama': drama.toJson(),
        });

  factory LanRecord.fromJson(Object? value) {
    if (utf8.encode(jsonEncode(value)).length > 512 * 1024) {
      throw const FormatException('单条同步记录超过保存上限');
    }
    final row = lanMap(value);
    final drama = lanDrama(row['drama']);
    final member = LanCell.fromJson(row['member']);
    final status = LanCell.fromJson(row['status']);
    final progress = LanCell.fromJson(row['progress']);
    validateCell('member', member);
    validateCell('status', status);
    validateCell('progress', progress);
    final known = row['known'];
    final read = row['read'];
    if (known is! int ||
        known < 0 ||
        known > 1000000 ||
        read != null && (read is! int || read < 0 || read > known)) {
      throw const FormatException('新集已读基准无效');
    }
    return LanRecord(
      drama: drama,
      member: member,
      status: status,
      progress: progress,
      known: known,
      read: read as int?,
    );
  }

  LanRecord withField(String field, LanCell cell) => LanRecord(
    drama: drama,
    member: field == 'member' ? cell : member,
    status: field == 'status' ? cell : status,
    progress: field == 'progress' ? cell : progress,
    known: known,
    read: read,
  );

  LanRecord merge(LanRecord other) {
    if (id != other.id) throw const FormatException('不能合并不同剧目');
    final a = lanJSON(drama.toJson()), b = lanJSON(other.drama.toJson());
    final metadata = a.compareTo(b) <= 0
        ? drama.merge(other.drama)
        : other.drama.merge(drama);
    return LanRecord(
      drama: lanCompactDrama(metadata),
      member: member.merge(other.member),
      status: status.merge(other.status),
      progress: progress.merge(other.progress),
      known: max(known, other.known),
      read: read == null && other.read == null
          ? null
          : max(read ?? 0, other.read ?? 0),
    );
  }

  Map<String, dynamic> toJson() => {
    'drama': drama.toJson(),
    'member': member.toJson(),
    'status': status.toJson(),
    'progress': progress.toJson(),
    'known': known,
    'read': read,
  };
}
