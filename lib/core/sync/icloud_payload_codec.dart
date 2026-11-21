import 'dart:convert';

import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/models/catalog/models.dart';

/// iCloud 同步报文编码与解码纯逻辑组件
class ICloudPayloadCodec {
  const ICloudPayloadCodec._();

  static ({List<WatchEntry> history, bool skipped}) decodeHistory(
    String? raw,
    int maxCount,
  ) {
    if (raw == null || raw.isEmpty) {
      return (history: <WatchEntry>[], skipped: false);
    }
    final remoteHistory = <WatchEntry>[];
    var skipped = false;
    try {
      final list = jsonDecode(raw) as List;
      for (final item in list) {
        try {
          remoteHistory.add(
            WatchEntry.fromJson(Map<String, dynamic>.from(item as Map)),
          );
        } catch (_) {
          skipped = true;
        }
      }
      if (remoteHistory.length > maxCount) {
        remoteHistory.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        remoteHistory.removeRange(maxCount, remoteHistory.length);
      }
    } catch (_) {
      skipped = true;
    }
    return (history: remoteHistory, skipped: skipped);
  }

  static bool decodeFollows(
    String? raw, {
    required Map<String, FollowState> outFollows,
    required List<Drama> outDramas,
    required Map<String, int> outDeletedFollows,
    required Map<String, int> outDeletedHistory,
  }) {
    if (raw == null || raw.isEmpty) return false;
    var skipped = false;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['follows'] is Map) {
        final fMap = map['follows'] as Map;
        for (final entry in fMap.entries) {
          final key = entry.key.toString();
          if (entry.value is String) {
            final statusStr = (entry.value as String).toLowerCase();
            FollowStatus status;
            if (statusStr == 'watching') {
              status = FollowStatus.watching;
            } else if (statusStr == 'watched' ||
                statusStr == 'finished' ||
                statusStr == 'completed') {
              status = FollowStatus.watched;
            } else {
              status = FollowStatus.planned;
            }
            outFollows[key] = FollowState(status: status);
          } else if (entry.value is Map) {
            try {
              outFollows[key] = FollowState.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              );
            } catch (_) {
              skipped = true;
            }
          }
        }
      }
      if (map['dramas'] is List) {
        for (final d in map['dramas'] as List) {
          try {
            outDramas.add(
              Drama.fromJson(Map<String, dynamic>.from(d as Map)),
            );
          } catch (_) {
            skipped = true;
          }
        }
      }
      final rawDelFollows = map['deletedFollows'] ?? map['deleted'];
      if (rawDelFollows is Map) {
        for (final entry in rawDelFollows.entries) {
          final ts = entry.value is int
              ? entry.value as int
              : int.tryParse(entry.value.toString()) ?? 0;
          if (ts > 0) outDeletedFollows[entry.key.toString()] = ts;
        }
      } else if (rawDelFollows is List) {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final item in rawDelFollows) {
          if (item != null) outDeletedFollows[item.toString()] = now;
        }
      }
      final rawDelHistory = map['deletedHistory'];
      if (rawDelHistory is Map) {
        for (final entry in rawDelHistory.entries) {
          final ts = entry.value is int
              ? entry.value as int
              : int.tryParse(entry.value.toString()) ?? 0;
          if (ts > 0) outDeletedHistory[entry.key.toString()] = ts;
        }
      } else if (rawDelHistory is List) {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final item in rawDelHistory) {
          if (item != null) outDeletedHistory[item.toString()] = now;
        }
      }
    } catch (_) {
      skipped = true;
    }
    return skipped;
  }
}
