import 'dart:math';

import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/models/lan/lan_cell.dart';
import 'package:THLRedLook/models/lan/lan_common.dart';
import 'package:THLRedLook/models/lan/lan_record.dart';
import 'package:THLRedLook/models/lan/lan_version.dart';

class LanDocument {
  LanDocument({
    required this.replica,
    this.counter = 0,
    Map<String, LanRecord> records = const {},
  }) : records = Map.of(records);

  final String replica;
  int counter;
  final Map<String, LanRecord> records;
  static const limit = 25000;
  int get conflicts =>
      records.values.fold(0, (count, record) => count + record.conflicts);

  factory LanDocument.empty() => LanDocument(replica: lanID());

  factory LanDocument.fromJson(Object? value) {
    final row = lanMap(value);
    final replica = lanText(row['replica'], 32);
    final counter = row['counter'];
    final rows = row['records'];
    if (row['schema'] != 1 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(replica) ||
        counter is! int ||
        counter < 0 ||
        counter >= 9007199254740000 ||
        rows is! List ||
        rows.length > limit) {
      throw const FormatException('局域网同步记录损坏，原记录已保留');
    }
    final document = LanDocument(replica: replica, counter: counter);
    for (final raw in rows) {
      final record = LanRecord.fromJson(raw);
      if (document.records.containsKey(record.id)) {
        throw const FormatException('同步记录重复');
      }
      document.records[record.id] = record;
      for (final cell in record.fields.values) {
        document.counter = max(
          document.counter,
          cell.version.values[replica] ?? 0,
        );
      }
    }
    return document;
  }

  LanDocument copy() =>
      LanDocument(replica: replica, counter: counter, records: records);

  LanCell cell(Object? value) => LanCell([
    LanValue(LanVersion({replica: ++counter}), value),
  ]);

  LanCell edit(LanCell current, Object? value) {
    counter = max(counter, current.version.values[replica] ?? 0) + 1;
    return current.edit(replica, counter, value);
  }

  void reconcile({
    required Map<String, Drama> previous,
    required Map<String, Drama> favorites,
    required Map<String, FollowState> states,
    required Map<String, WatchEntry> history,
    required Map<String, WatchEntry> oldHistory,
    Set<String> clearProgress = const {},
  }) {
    for (final id in {...records.keys, ...favorites.keys}) {
      final old = records[id];
      final drama = favorites[id];
      if (old == null && drama != null) {
        final state = states[id] ?? FollowState.initial(drama, history[id]);
        records[id] = LanRecord(
          drama: lanCompactDrama(drama),
          member: cell(true),
          status: cell({
            'status': state.status.name,
            'manual': state.manuallyWatched,
          }),
          progress: cell(lanProgress(history[id])),
          known: state.knownEpisodes,
          read: state.readEpisodes,
        );
        continue;
      }
      if (old == null) continue;
      if (drama == null) {
        if (previous.containsKey(id)) {
          records[id] = old
              .withField('member', edit(old.member, false))
              .withField('progress', edit(old.progress, null));
        } else if (clearProgress.contains(id)) {
          records[id] = old.withField('progress', edit(old.progress, null));
        }
        continue;
      }
      final state = states[id] ?? old.following;
      var next = LanRecord(
        drama: lanCompactDrama(drama),
        member: !previous.containsKey(id) ? edit(old.member, true) : old.member,
        status: old.status,
        progress: old.progress,
        known: max(old.known, state.knownEpisodes),
        read: state.readEpisodes == null && old.read == null
            ? null
            : max(old.read ?? 0, state.readEpisodes ?? 0),
      );
      final status = {
        'status': state.status.name,
        'manual': state.manuallyWatched,
      };
      if (lanJSON(status) != lanJSON(old.status.value)) {
        next = next.withField('status', edit(old.status, status));
      }
      if (clearProgress.contains(id)) {
        next = next.withField('progress', edit(old.progress, null));
      } else if (history[id] != null &&
          (!previous.containsKey(id) ||
              lanJSON(lanProgress(history[id])) !=
                  lanJSON(lanProgress(oldHistory[id])))) {
        next = next.withField(
          'progress',
          edit(old.progress, lanProgress(history[id])),
        );
      }
      records[id] = next;
    }
    if (records.length > limit) throw StateError('同步记录已达保存上限，请先整理设备记录');
  }

  String hashFor(Set<String> sources) {
    final entries =
        records.values
            .where((record) => sources.contains(record.drama.source))
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return lanHash([
      for (final entry in entries) [entry.id, entry.hash],
    ]);
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'replica': replica,
    'counter': counter,
    'records': records.values.map((record) => record.toJson()).toList(),
  };
}
