import 'package:THLRedLook/core/catalog/catalog_sort.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/series/hongguo_series_info.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';

bool hasRoundedHongguoSeriesId(Drama drama) {
  if (drama.source != SourceSite.hongguo.id) return false;
  final id = drama.cleanSourceId;
  if (!RegExp(r'^[1-9]\d{15,29}$').hasMatch(id)) return false;
  final number = double.tryParse(id);
  if (number == null || !number.isFinite || number <= 9007199254740991) {
    return false;
  }
  return number.toString().replaceFirst(RegExp(r'\.0$'), '') == id;
}

String seriesIdentityKey(Drama drama) {
  final info = hongguoSeriesInfo(drama);
  return info == null
      ? normalizedSearchText(stripNoiseSuffixes(drama.title))
      : '${info.key}|${info.unit}|${info.season}';
}

Map<String, Drama> hongguoSeriesIdReplacements(
  Iterable<Drama> previous,
  Iterable<Drama> fresh,
) {
  final stale = previous.where(hasRoundedHongguoSeriesId).toList();
  if (stale.isEmpty) return const {};
  final byTitle = <String, Map<String, Drama>>{};
  for (final drama in fresh) {
    if (drama.source != SourceSite.hongguo.id ||
        !RegExp(r'^[1-9]\d{15,29}$').hasMatch(drama.cleanSourceId) ||
        hasRoundedHongguoSeriesId(drama)) {
      continue;
    }
    final title = seriesIdentityKey(drama);
    if (title.isNotEmpty) (byTitle[title] ??= {})[drama.id] = drama;
  }
  final replacements = <String, Drama>{};
  for (final drama in stale) {
    final matches =
        (byTitle[seriesIdentityKey(drama)]?.values ?? const <Drama>[])
            .where(
              (candidate) =>
                  candidate.cleanSourceId != drama.cleanSourceId &&
                  double.parse(candidate.cleanSourceId) ==
                      double.parse(drama.cleanSourceId),
            )
            .toList();
    if (matches.length == 1) replacements[drama.id] = matches.single;
  }
  return replacements;
}

Drama mergeHongguoSeriesIdentity(Drama previous, Drama fresh) =>
    Drama.fromJson({
      ...previous.toJson(),
      'id': fresh.id,
      'source': fresh.source,
      'sourceId': fresh.cleanSourceId,
    }).merge(fresh);

Future<Drama> resolveHongguoSeriesIdentity({
  required Drama drama,
  required AppRepository repository,
  LocalStore? store,
}) async {
  if (!hasRoundedHongguoSeriesId(drama)) return drama;
  final ownerEpoch = store?.profileEpoch;
  CatalogPage? page;
  try {
    page = await repository.catalog(
      drama.source,
      query: cleanSeriesBaseTitle(drama.title),
      force: true,
    );
  } catch (_) {}
  if (store != null && store.profileEpoch != ownerEpoch) {
    throw AppFailure('用户已变更，请重新打开剧集', code: 'profile_changed');
  }
  final items = page?.items ?? const <Drama>[];
  final same = items
      .where(
        (candidate) =>
            candidate.source == drama.source &&
            candidate.cleanSourceId == drama.cleanSourceId &&
            seriesIdentityKey(candidate) == seriesIdentityKey(drama),
      )
      .firstOrNull;
  final replacement =
      same ?? hongguoSeriesIdReplacements([drama], items)[drama.id];
  if (replacement == null) {
    try {
      final detail = await repository.detail(drama);
      final id = RegExp.escape(drama.cleanSourceId);
      final exactTarget = RegExp(
        '(?:/player/$id/|^$id[_/])(\\d{10,30})(?:[/?#]|\$)',
      );
      final verified =
          detail.drama.cleanSourceId == drama.cleanSourceId &&
          detail.episodes.isNotEmpty &&
          detail.episodes.every((episode) {
            final target =
                (episode.raw['raw'] ?? episode.raw['url'] ?? episode.id)
                    .toString();
            return exactTarget.hasMatch(target);
          });
      if (verified) return drama.merge(detail.drama);
    } catch (_) {}
    throw AppFailure('旧剧集编号需要更新，暂未查到准确结果，请重新搜索该季后重试', code: 'STALE_SERIES_ID');
  }
  if (store != null) await store.refreshDramas(items);
  return mergeHongguoSeriesIdentity(drama, replacement);
}
