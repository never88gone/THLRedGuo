import 'package:THLRedLook/core/catalog/catalog_sort.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';

const _seriesSeasonLimit = 200;

class HongguoSeriesInfo {
  const HongguoSeriesInfo({
    required this.baseTitle,
    required this.key,
    required this.season,
    required this.unit,
    required this.explicit,
  });

  final String baseTitle;
  final String key;
  final int season;
  final String unit;
  final bool explicit;
}

class HongguoSeriesEntry {
  const HongguoSeriesEntry({
    required this.drama,
    required this.season,
    required this.unit,
  });

  final Drama drama;
  final int season;
  final String unit;

  String get label => '第 $season $unit';
}

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

String _seriesIdentityKey(Drama drama) {
  final info = hongguoSeriesInfo(drama);
  return info == null
      ? normalizedSearchText(_stripNoiseSuffixes(drama.title))
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
    final title = _seriesIdentityKey(drama);
    if (title.isNotEmpty) (byTitle[title] ??= {})[drama.id] = drama;
  }
  final replacements = <String, Drama>{};
  for (final drama in stale) {
    final matches =
        (byTitle[_seriesIdentityKey(drama)]?.values ?? const <Drama>[])
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
            _seriesIdentityKey(candidate) == _seriesIdentityKey(drama),
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

/// 清洗短剧标题末尾常见的非季数杂质与标识
String _stripNoiseSuffixes(String text) {
  var s = text.trim();
  final noisePattern = RegExp(
    r'[\(（\[【]\s*(?:4K|1080P|720P|超清|高清|全集|完结|精修版|独家|热播|已完结|[0-9]+集全?|\s)+\s*[\)）\]】]$',
    caseSensitive: false,
  );
  while (true) {
    final match = noisePattern.firstMatch(s);
    if (match != null) {
      s = s.substring(0, match.start).trim();
    } else {
      break;
    }
  }
  return s;
}

int? _seasonNumber(String label) {
  final numeric = int.tryParse(label);
  if (numeric != null) {
    return numeric >= 1 && numeric <= _seriesSeasonLimit ? numeric : null;
  }
  const digits = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '兩': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (!label.contains(RegExp('[十百]'))) {
    var number = 0;
    for (final rune in label.runes) {
      final digit = digits[String.fromCharCode(rune)];
      if (digit == null) return null;
      number = number * 10 + digit;
      if (number > _seriesSeasonLimit) return null;
    }
    return number >= 1 ? number : null;
  }
  var number = 0;
  var digit = 0;
  var previous = 1000;
  for (final rune in label.runes) {
    final character = String.fromCharCode(rune);
    final value = digits[character];
    if (value != null) {
      digit = digit * 10 + value;
      continue;
    }
    final multiplier = character == '百' ? 100 : 10;
    if (multiplier >= previous || digit > 9) return null;
    number += (digit == 0 ? 1 : digit) * multiplier;
    digit = 0;
    previous = multiplier;
  }
  number += digit;
  return number >= 1 && number <= _seriesSeasonLimit ? number : null;
}

int? _romanNumber(String text) {
  switch (text.trim().toUpperCase()) {
    case 'I':
      return 1;
    case 'II':
      return 2;
    case 'III':
      return 3;
    case 'IV':
      return 4;
    case 'V':
      return 5;
    case 'VI':
      return 6;
    case 'VII':
      return 7;
    case 'VIII':
      return 8;
    case 'IX':
      return 9;
    case 'X':
      return 10;
    default:
      return null;
  }
}

/// 提取并解析剧集的系列与多季信息
HongguoSeriesInfo? hongguoSeriesInfo(Drama drama, {String? unit}) {
  if (drama.title.trim().isEmpty) return null;
  final cleanedTitle = _stripNoiseSuffixes(drama.title);

  // 1. 标准「第X季/第X部/第X篇/第X卷/第X期」，支持被括号包裹或直接置于末尾
  final standardRegex = RegExp(
    r'[\(（\[【]?\s*第\s*([0-9零〇一二两兩三四五六七八九十百]+)\s*([季部篇卷期])\s*[\)）\]】]?[\s\u3000，。！？、：；·「」『』（）【】《》“”‘’.,!?:;\-_/()\[\]{}]*$',
  );
  var match = standardRegex.firstMatch(cleanedTitle);
  if (match != null) {
    final base = cleanedTitle.substring(0, match.start).trim();
    final season = _seasonNumber(match[1]!);
    if (base.isNotEmpty && season != null) {
      return HongguoSeriesInfo(
        baseTitle: base,
        key: normalizedSearchText(base),
        season: season,
        unit: match[2]!,
        explicit: true,
      );
    }
  }

  // 2. 英文 Season/S/Part 后缀，如「Season 2」「S2」「Part 3」
  final englishRegex = RegExp(
    r'[\(（\[【\s\-_]+(?:Season|S|Part)\s*([0-9]+)\s*[\)）\]】]?[\s\-_]*$',
    caseSensitive: false,
  );
  match = englishRegex.firstMatch(cleanedTitle);
  if (match != null) {
    final base = cleanedTitle.substring(0, match.start).trim();
    final season = int.tryParse(match[1]!);
    if (base.isNotEmpty &&
        season != null &&
        season >= 1 &&
        season <= _seriesSeasonLimit) {
      return HongguoSeriesInfo(
        baseTitle: base,
        key: normalizedSearchText(base),
        season: season,
        unit: unit ?? '季',
        explicit: true,
      );
    }
  }

  // 3. 罗马数字后缀，如「 II」「 III」「 IV」
  final romanRegex = RegExp(r'[\(（\[【\s\-_]+([IVXivx]+)\s*[\)）\]】]?[\s\-_]*$');
  match = romanRegex.firstMatch(cleanedTitle);
  if (match != null) {
    final base = cleanedTitle.substring(0, match.start).trim();
    final season = _romanNumber(match[1]!);
    if (base.isNotEmpty && season != null) {
      return HongguoSeriesInfo(
        baseTitle: base,
        key: normalizedSearchText(base),
        season: season,
        unit: unit ?? '季',
        explicit: true,
      );
    }
  }

  // 4. 纯数字后缀，如「战神 2」「逆袭(2)」
  final numericSuffixRegex = RegExp(
    r'(?:[\s\-_]+|[\(（\[【])([0-9]+)\s*[\)）\]】]?[\s\-_]*$',
  );
  match = numericSuffixRegex.firstMatch(cleanedTitle);
  if (match != null) {
    final base = cleanedTitle.substring(0, match.start).trim();
    final season = int.tryParse(match[1]!);
    if (base.isNotEmpty &&
        season != null &&
        season >= 2 &&
        season <= _seriesSeasonLimit) {
      return HongguoSeriesInfo(
        baseTitle: base,
        key: normalizedSearchText(base),
        season: season,
        unit: unit ?? '季',
        explicit: true,
      );
    }
  }

  // 5. 常见续篇词缀：「续集」「大结局」「终章」
  final sequelRegex = RegExp(r'[\(（\[【\s\-_]+(续集|大结局|终章)\s*[\)）\]】]?$');
  match = sequelRegex.firstMatch(cleanedTitle);
  if (match != null) {
    final base = cleanedTitle.substring(0, match.start).trim();
    if (base.isNotEmpty) {
      final tag = match[1]!;
      final season = tag == '续集' ? 2 : (tag == '终章' || tag == '大结局' ? 99 : 2);
      return HongguoSeriesInfo(
        baseTitle: base,
        key: normalizedSearchText(base),
        season: season,
        unit: unit ?? '部',
        explicit: true,
      );
    }
  }

  // 兜底：若未显式包含季标记，但指定了 unit 或供同系列分组推导
  if (unit != null && cleanedTitle.isNotEmpty) {
    return HongguoSeriesInfo(
      baseTitle: cleanedTitle,
      key: normalizedSearchText(cleanedTitle),
      season: 1,
      unit: unit,
      explicit: false,
    );
  }

  return null;
}

/// 清洗出短剧的基础系列名称
String cleanSeriesBaseTitle(String title) {
  final cleaned = _stripNoiseSuffixes(title);
  final info = hongguoSeriesInfo(
    Drama(id: '', source: '', sourceId: '', title: cleaned),
  );
  return info?.baseTitle.trim().isNotEmpty == true
      ? info!.baseTitle.trim()
      : cleaned;
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
    ),
  );
  var anchorInfo = hongguoSeriesInfo(anchor);
  String key, unit;
  int anchorSeason;

  if (anchorInfo == null) {
    final cleaned = _stripNoiseSuffixes(anchor.title);
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
