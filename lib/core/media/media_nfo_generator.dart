import 'package:THLRedLook/models/catalog/models.dart';

/// XML 文本特殊字符转义工具
String xmlText(String value) => value
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Emby / Jellyfin 剧集 tvshow.nfo 描述文件生成器
String embyShowNfo(Drama drama, {bool localPoster = false}) {
  final uri = Uri.tryParse(drama.cover);
  final cover = localPoster
      ? 'poster.jpg'
      : uri != null && {'https', 'http'}.contains(uri.scheme)
      ? drama.cover
      : '';
  return '<?xml version="1.0" encoding="utf-8"?>\n<tvshow>'
      '<title>${xmlText(drama.title)}</title><plot>${xmlText(drama.description)}</plot>'
      '<uniqueid type="zhenguojian" default="true">${xmlText(drama.id)}</uniqueid>'
      '${cover.isEmpty ? '' : '<thumb aspect="poster">${xmlText(cover)}</thumb>'}'
      '<season>1</season><episode>${drama.episodes}</episode></tvshow>\n';
}

/// Emby / Jellyfin 单集 NFO 描述文件生成器
String embyEpisodeNfo(DownloadJob job) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<episodedetails><title>${xmlText(job.episode.title)}</title>'
    '<showtitle>${xmlText(job.drama.title)}</showtitle><season>1</season><episode>${job.episode.number}</episode>'
    '<plot>${xmlText(job.drama.description)}</plot>'
    '<uniqueid type="zhenguojian" default="true">${xmlText(job.id)}</uniqueid></episodedetails>\n';

/// 本地媒体导出文件名安全过滤工具
String safeDramaFileName(String name) {
  var result = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (result.isEmpty) result = '短剧';
  return String.fromCharCodes(result.runes.take(60));
}


