import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/catalog/catalog_sort.dart';
import 'package:THLRedLook/core/series/hongguo_series_identity.dart';
import 'package:THLRedLook/core/series/hongguo_series_info.dart';
import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';

class HongguoSeriesEntry {
  const HongguoSeriesEntry({
    required this.drama,
    required this.season,
    required this.unit,
    this.playable = true,
    this.status = '',
    this.official = false,
  });

  final Drama drama;
  final int season;
  final String unit;
  final bool playable;
  final String status;
  final bool official;

  String get label => '第 $season $unit${status.isEmpty ? '' : ' · $status'}';
}

/// 聚合计算与排序同系列的多季剧集列表
List<HongguoSeriesEntry> hongguoSeriesEntries(
  Drama anchor,
  Iterable<Drama> candidates, {
  Iterable<HongguoSeriesEntry>? lockedEntries,
}) {
  if (anchor.title.trim().isEmpty) return const [];
  candidates = candidates.toList();
  final replacements = hongguoSeriesIdReplacements([
    anchor,
    ...?lockedEntries?.map((entry) => entry.drama),
    ...candidates,
  ], candidates);
  Drama current(Drama drama) => replacements[drama.id] == null
      ? drama
      : mergeHongguoSeriesIdentity(drama, replacements[drama.id]!);
  anchor = current(anchor);
  candidates = candidates.map(current).toList();
  lockedEntries = lockedEntries?.map(
    (entry) => HongguoSeriesEntry(
      drama: current(entry.drama),
      season: entry.season,
      unit: entry.unit,
      playable: entry.playable,
      status: entry.status,
      official: entry.official,
    ),
  );
  if (lockedEntries != null &&
      lockedEntries.any((entry) => entry.official) &&
      lockedEntries.any((entry) => entry.drama.id == anchor.id)) {
    return lockedEntries.toList();
  }
  var anchorInfo = hongguoSeriesInfo(anchor);
  String key, unit;
  int anchorSeason;

  if (anchorInfo == null) {
    final cleaned = stripNoiseSuffixes(anchor.title);
    final baseKey = normalizedSearchText(cleaned);
    final groups = <String, List<HongguoSeriesInfo>>{};
    for (final drama in candidates) {
      if (drama.source != anchor.source) continue;
      final info = hongguoSeriesInfo(drama);
      if (info != null && info.key == baseKey) {
        (groups[info.unit] ??= []).add(info);
      }
    }
    if (groups.isEmpty) return const [];
    final best = groups.entries.toList()
      ..sort((a, b) {
        final count = b.value.length.compareTo(a.value.length);
        if (count != 0) return count;
        final maxA = a.value.fold<int>(
          0,
          (value, info) => value > info.season ? value : info.season,
        );
        final maxB = b.value.fold<int>(
          0,
          (value, info) => value > info.season ? value : info.season,
        );
        return maxB.compareTo(maxA);
      });
    key = baseKey;
    unit = best.first.key;
    anchorSeason = 1;
    anchorInfo = hongguoSeriesInfo(anchor, unit: unit);
  } else {
    key = anchorInfo.key;
    unit = anchorInfo.unit;
    anchorSeason = anchorInfo.season;
  }

  if (anchorInfo == null) return const [];

  final bySeason = <int, HongguoSeriesEntry>{};
  final candidateInfos = <String, HongguoSeriesInfo>{};

  // 1. 若有已确立的季列表，优先锁定既有季条目，确保跨季切换时不跳变
  if (lockedEntries != null) {
    for (final entry in lockedEntries) {
      if (entry.drama.source == anchor.source) {
        bySeason[entry.season] = entry;
        final info = hongguoSeriesInfo(entry.drama, unit: unit);
        if (info != null) candidateInfos[entry.drama.id] = info;
      }
    }
  }

  // 2. 当前 anchor 必须在对应季拥有绝对优先权
  final anchorEntry = HongguoSeriesEntry(
    drama: anchor,
    season: anchorSeason,
    unit: unit,
  );
  bySeason[anchorSeason] = anchorEntry;
  candidateInfos[anchor.id] = anchorInfo;

  // 3. 遍历候选短剧，同季冲突进行择优仲裁
  for (final drama in candidates) {
    if (drama.source != anchor.source) continue;
    if (drama.id == anchor.id) continue;
    final info = hongguoSeriesInfo(drama, unit: unit);
    if (info == null || info.key != key) continue;
    candidateInfos[drama.id] = info;

    final targetSeason = info.season;
    final existing = bySeason[targetSeason];

    if (existing == null) {
      bySeason[targetSeason] = HongguoSeriesEntry(
        drama: drama,
        season: targetSeason,
        unit: unit,
      );
    } else {
      // 若当前位置是 anchor 或已被锁定的已确定条目，不得随意替换
      if (existing.drama.id == anchor.id) continue;
      if (lockedEntries != null &&
          lockedEntries.any(
            (e) => e.season == targetSeason && e.drama.id == existing.drama.id,
          )) {
        continue;
      }

      final existingInfo = candidateInfos[existing.drama.id];
      // 显式标季（explicit: true）优先于未标季的隐式推断
      if (info.explicit && (existingInfo?.explicit != true)) {
        bySeason[targetSeason] = HongguoSeriesEntry(
          drama: drama,
          season: targetSeason,
          unit: unit,
        );
      } else if (!info.explicit && (existingInfo?.explicit == true)) {
        continue;
      } else {
        // 集数较多优先
        if (drama.episodes > existing.drama.episodes) {
          bySeason[targetSeason] = HongguoSeriesEntry(
            drama: drama,
            season: targetSeason,
            unit: unit,
          );
        } else if (drama.episodes == existing.drama.episodes) {
          if (naturalTitleCompare(drama.title, existing.drama.title) < 0) {
            bySeason[targetSeason] = HongguoSeriesEntry(
              drama: drama,
              season: targetSeason,
              unit: unit,
            );
          }
        }
      }
    }
  }

  // 4. 严格按季号升序排列 (1, 2, 3...)，保证顺序恒定单调递增
  final entries = bySeason.values.toList()
    ..sort((a, b) => a.season.compareTo(b.season));

  return entries.length > 1 ? entries : const [];
}

/// 自动在网络及本地检索并发现当前剧集的全部关联季
Future<List<HongguoSeriesEntry>> discoverSeriesSeasons({
  required Drama anchor,
  required AppRepository repository,
  LocalStore? store,
  List<HongguoSeriesEntry>? existingEntries,
}) async {
  if (anchor.source == SourceSite.hongguo.id) {
    try {
      final seasons = await repository.seriesSeasons(anchor);
      if (seasons.isNotEmpty) {
        final fresh = seasons.map((entry) => entry.drama).toList();
        if (store != null) await store.refreshDramas(fresh);
        return seasons
            .map(
              (entry) => HongguoSeriesEntry(
                drama: entry.drama.id == anchor.id
                    ? anchor.merge(entry.drama)
                    : entry.drama,
                season: entry.season,
                unit: '季',
                playable: entry.playable,
                status: entry.status,
                official: true,
              ),
            )
            .toList();
      }
    } catch (_) {}
  }
  if (existingEntries?.any((entry) => entry.official) == true) {
    return existingEntries!;
  }
  final localCandidates = store != null
      ? store.seriesDramasFor(anchor)
      : <Drama>[];
  var entries = existingEntries != null && existingEntries.isNotEmpty
      ? existingEntries
      : hongguoSeriesEntries(anchor, localCandidates);

  final baseTitle = cleanSeriesBaseTitle(anchor.title);
  if (baseTitle.length < 2) return entries;

  try {
    final searchPage = await repository.catalog(
      anchor.source,
      query: baseTitle,
      page: 1,
    );
    final searchItems = searchPage.items
        .where((d) => d.source == anchor.source)
        .toList();
    if (searchItems.isNotEmpty && store != null) {
      await store.refreshDramas(searchItems);
    }
    final allCandidates = <String, Drama>{
      for (final e in entries) e.drama.id: e.drama,
      for (final d in localCandidates) d.id: d,
      for (final d in searchItems) d.id: d,
      anchor.id: anchor,
    };
    final fresh = hongguoSeriesEntries(
      anchor,
      allCandidates.values,
      lockedEntries: entries.isNotEmpty ? entries : null,
    );
    if (fresh.length >= entries.length) {
      entries = fresh;
    }
  } catch (_) {}

  return entries;
}

FollowState observeHongguoSeriesSeasons({
  required Drama anchor,
  required FollowState state,
  required Iterable<Drama> candidates,
  required Set<String> favoriteIds,
}) {
  final entries = hongguoSeriesEntries(anchor, candidates);
  if (entries.isEmpty) return state;
  final anchorSeason = entries
      .where((entry) => entry.drama.id == anchor.id)
      .firstOrNull
      ?.season;
  if (anchorSeason == null) return state;
  var seasons = state.seriesSeasons;
  for (final id in seasons.keys.toList()) {
    if (id == anchor.id || favoriteIds.contains(id)) {
      seasons = Map.of(seasons)..remove(id);
    }
  }
  for (final entry in entries) {
    if (entry.drama.id == anchor.id ||
        favoriteIds.contains(entry.drama.id) ||
        entry.season <= anchorSeason) {
      continue;
    }
    final previous = seasons[entry.drama.id];
    final notice = SeriesSeasonNotice(
      id: entry.drama.id,
      title: entry.drama.title,
      season: entry.season,
      unit: entry.unit,
      read: previous?.read ?? false,
    );
    if (previous?.title == notice.title &&
        previous?.season == notice.season &&
        previous?.unit == notice.unit &&
        previous?.read == notice.read) {
      continue;
    }
    seasons = Map.of(seasons)..[notice.id] = notice;
  }
  return identical(seasons, state.seriesSeasons)
      ? state
      : state.copyWith(seriesSeasons: seasons);
}
