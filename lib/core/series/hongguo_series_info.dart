import 'package:THLRedLook/core/catalog/catalog_sort.dart';
import 'package:THLRedLook/models/catalog/models.dart';

const seriesSeasonLimit = 200;

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

/// 清洗短剧标题末尾常见的非季数杂质与标识
String stripNoiseSuffixes(String text) {
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
    return numeric >= 1 && numeric <= seriesSeasonLimit ? numeric : null;
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
      if (number > seriesSeasonLimit) return null;
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
  return number >= 1 && number <= seriesSeasonLimit ? number : null;
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
  final cleanedTitle = stripNoiseSuffixes(drama.title);

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
        season <= seriesSeasonLimit) {
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
        season <= seriesSeasonLimit) {
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
  final cleaned = stripNoiseSuffixes(title);
  final info = hongguoSeriesInfo(
    Drama(id: '', source: '', sourceId: '', title: cleaned),
  );
  return info?.baseTitle.trim().isNotEmpty == true
      ? info!.baseTitle.trim()
      : cleaned;
}
