import 'package:THLRedLook/models/lan/lan_record.dart';

enum LanSyncMode {
  merge('双向合并'),
  push('覆盖对方'),
  pull('覆盖本机');

  const LanSyncMode(this.label);
  final String label;
}

class LanChangeCount {
  const LanChangeCount({
    this.added = 0,
    this.updated = 0,
    this.removed = 0,
    this.conflicts = 0,
  });

  final int added, updated, removed, conflicts;

  factory LanChangeCount.between(
    Map<String, LanRecord> old,
    Map<String, LanRecord> next,
  ) {
    var added = 0, updated = 0, removed = 0, conflicts = 0;
    for (final record in next.values) {
      final previous = old[record.id];
      if (record.followed && previous?.followed != true) {
        added++;
      } else if (!record.followed && previous?.followed == true) {
        removed++;
      } else if (record.followed && previous?.hash != record.hash) {
        updated++;
      }
      conflicts += record.conflicts;
    }
    return LanChangeCount(
      added: added,
      updated: updated,
      removed: removed,
      conflicts: conflicts,
    );
  }

  String get label => '新增 $added · 更新 $updated · 移除 $removed · 冲突 $conflicts';
}
