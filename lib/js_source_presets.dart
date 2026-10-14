// 预置短剧与影视 CatPawOpen Spider 数据源插件定义。
// 适配标准 CatPawOpen / CatVodOpen JS 规范，可在端侧沙箱及第三方播放器（如猫爪等）中独立运行。

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'js_source_service.dart';

class PresetJsSource {
  final String id;
  final String fileName;
  final String name;
  final String description;
  final String script;

  const PresetJsSource({
    required this.id,
    required this.fileName,
    required this.name,
    required this.description,
    required this.script,
  });
}

const List<PresetJsSource> kPresetJsSources = [
  PresetJsSource(
    id: 'hongguo',
    fileName: 'hongguo.js',
    name: '红果免费短剧',
    description: '官方首发短剧源，包含海量都市爽文、战神回归、现代甜宠短剧',
    script: r'''/**
 * 红果免费短剧 CatPawOpen Spider (hongguo.js)
 * 适配 CatPawOpen / CatVodOpen 标准规范 v1.0.3
 */

const meta = {
  id: "hongguo",
  name: "红果免费短剧",
  version: "1.0.3",
  description: "官方首发短剧源，包含海量都市爽文、战神回归、现代甜宠等优质短剧",
  author: "社区开发者",
  type: "video",
  icon: "",
  features: ["search", "categories"]
};

const BASE_URL = "https://hongguoduanju.com";
const USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

function cleanText(text) {
  if (!text) return "";
  return text.replace(/<[^>]+>/g, "").trim();
}

function parseJsonFromHtml(body) {
  if (!body) return null;
  const marker = /(?:window\.)?_ROUTER_DATA\s*=\s*(\{)/.exec(body);
  if (marker) {
    const startIdx = marker.index + marker[0].length - 1;
    let depth = 0;
    let inString = false;
    let escape = false;
    for (let i = startIdx; i < body.length; i++) {
      const ch = body[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (ch === '\\') {
        escape = true;
        continue;
      }
      if (ch === '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (ch === '{') depth++;
        else if (ch === '}') {
          depth--;
          if (depth === 0) {
            try {
              return JSON.parse(body.slice(startIdx, i + 1));
            } catch (e) {
              break;
            }
          }
        }
      }
    }
  }
  const nextMatch = body.match(/<script[^>]*id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/);
  if (nextMatch && nextMatch[1]) {
    try { return JSON.parse(nextMatch[1]); } catch (e) {}
  }
  return null;
}

async function init(ext) {
  return true;
}

async function home(filter) {
  return {
    class: [
      { type_id: "real-drama", type_name: "真人剧" },
      { type_id: "comic-drama", type_name: "漫剧" },
      { type_id: "ai-drama", type_name: "AI剧" },
      { type_id: "comic", type_name: "动漫" }
    ],
    filters: {}
  };
}

async function category(tid, pg, filter, extend) {
  pg = pg || 1;
  const route = (!tid || tid === "short_play" || tid === "all") ? "real-drama" : tid;
  const url = BASE_URL + "/category/" + route + (pg > 1 ? ("?page=" + pg) : "");
  let items = [];

  try {
    const resp = await fetch(url, {
      headers: {
        "User-Agent": USER_AGENT,
        "Referer": BASE_URL + "/"
      }
    });

    if (resp && resp.status === 200 && resp.body) {
      const body = resp.body;
      const routerData = parseJsonFromHtml(body);
      if (routerData && routerData.loaderData) {
        for (const k of Object.keys(routerData.loaderData)) {
          const lData = routerData.loaderData[k];
          if (lData && Array.isArray(lData.recommendList) && lData.recommendList.length > 0) {
            for (let i = 0; i < lData.recommendList.length; i++) {
              const dr = lData.recommendList[i];
              const vd = dr.video_data || dr;
              const id = vd.series_id_str || vd.series_id || dr.series_id_str || dr.series_id || dr.book_id || dr.id;
              if (!id) continue;
              const name = cleanText(vd.series_title || vd.series_name || vd.title || dr.series_name || dr.series_title || dr.title || dr.book_name || dr.name);
              const pic = vd.series_cover || vd.cover || vd.thumb_url || vd.cover_url || dr.series_cover || dr.cover || "";
              const epCnt = vd.episode_cnt || dr.episode_cnt || 0;
              const remark = vd.episode_right_text || dr.episode_right_text || (epCnt ? ("全" + epCnt + "集") : "");
              const intro = cleanText(vd.series_intro || vd.video_desc || vd.intro || vd.abstract || vd.desc || dr.series_intro || dr.intro || dr.desc);
              if (name) {
                items.push({
                  vod_id: String(id),
                  vod_name: name,
                  vod_pic: pic,
                  vod_remarks: remark,
                  vod_content: intro || name,
                  vod_tag: (vd.tags || dr.tags || []).join(","),
                  vod_year: "2024"
                });
              }
            }
            if (items.length > 0) break;
          }
        }
      }

      if (items.length === 0 && typeof html !== 'undefined' && html.parse) {
        const doc = html.parse(body);
        if (doc) {
          const cards = doc.find("a[href*='detail'], .pc-card-DQXf3W, .m-card-V7QopP, .drama-card, .book-item");
          for (let i = 0; i < cards.length; i++) {
            const el = cards.eq(i);
            const href = el.attr("href") || "";
            const idMatch = href.match(/(?:series_id=|\/detail\/|id=)(\d+)/);
            if (!idMatch) continue;
            const id = idMatch[1];

            const imgEl = el.find("img");
            let title = cleanText(el.find("p[class*='title'], .title, h3, .name").text());
            if (!title && imgEl.length > 0) {
              title = cleanText(imgEl.attr("alt"));
            }

            let cover = imgEl.attr("src") || imgEl.attr("data-src") || "";
            if (!cover) {
              const srcSet = el.find("source").attr("srcSet") || "";
              if (srcSet) cover = srcSet.split(" ")[0];
            }

            const epText = el.find("p[class*='episode'], .episode").text() || "";
            const epMatch = epText.match(/(\d+)/);
            const episodes = epMatch ? parseInt(epMatch[1]) : 0;
            const desc = cleanText(el.find(".desc, .intro, p").text());

            if (id && title) {
              items.push({
                vod_id: String(id),
                vod_name: title,
                vod_pic: cover,
                vod_remarks: episodes ? ("全" + episodes + "集") : "",
                vod_content: desc || (title + (episodes ? (" · 全" + episodes + "集") : "")),
                vod_year: "2024"
              });
            }
          }
        }
      }
    }
  } catch (e) {}

  return {
    page: pg,
    pagecount: items.length > 0 ? 99 : 1,
    limit: 20,
    total: items.length,
    list: items
  };
}

async function detail(id) {
  let title = "";
  let cover = "";
  let desc = "";
  let vidList = [];

  try {
    const url = BASE_URL + "/detail?series_id=" + id;
    const resp = await fetch(url, {
      headers: {
        "User-Agent": USER_AGENT,
        "Referer": BASE_URL + "/"
      }
    });

    if (resp && resp.status === 200 && resp.body) {
      const body = resp.body;
      const routerData = parseJsonFromHtml(body);
      if (routerData && routerData.loaderData) {
        for (const k of Object.keys(routerData.loaderData)) {
          const lData = routerData.loaderData[k];
          const sDetail = lData && (lData.seriesDetail || lData.videoDetail || lData.series_info);
          if (sDetail) {
            const sTitle = cleanText(sDetail.series_name || sDetail.series_title || sDetail.title || sDetail.name);
            if (sTitle) title = sTitle;
            const sCover = sDetail.series_cover || sDetail.cover || sDetail.cover_url || "";
            if (sCover) cover = sCover;
            const sDesc = cleanText(sDetail.series_intro || sDetail.intro || sDetail.abstract || sDetail.desc);
            if (sDesc) desc = sDesc;
            if (Array.isArray(sDetail.vid_list) && sDetail.vid_list.length > 0) {
              vidList = sDetail.vid_list;
            }
            break;
          }
        }
      }

      const ldMatch = body.match(/<script[^>]*type=[\x27\x22]application\/ld\+json[\x27\x22][^>]*>([\s\S]*?)<\/script>/);
      if (ldMatch && ldMatch[1]) {
        try {
          const ld = JSON.parse(ldMatch[1]);
          if (ld && ld["@graph"] && Array.isArray(ld["@graph"])) {
            for (let i = 0; i < ld["@graph"].length; i++) {
              const node = ld["@graph"][i];
              if (node.name) title = cleanText(node.name);
              if (node.description) desc = cleanText(node.description);
            }
          }
        } catch (e) {}
      }

      if (typeof html !== 'undefined' && html.parse) {
        const doc = html.parse(body);
        if (doc) {
          const domTitle = cleanText(doc.find("h1, .detail-title, p[class*='title']").text());
          if (domTitle && !title) title = domTitle;
          const domCover = doc.find(".detail-cover img, img[class*='image']").attr("src") || "";
          if (domCover && !cover) cover = domCover;
          const domDesc = cleanText(doc.find(".detail-intro, .desc, meta[name='description']").text() || doc.find("meta[name='description']").attr("content") || "");
          if (domDesc && !desc) desc = domDesc;
        }
      }
    }
  } catch (e) {}

  const epUrls = [];
  if (vidList.length > 0) {
    for (let i = 0; i < vidList.length; i++) {
      epUrls.push("第" + (i + 1) + "集$" + BASE_URL + "/player/" + id + "/" + vidList[i]);
    }
  }

  if (!title && epUrls.length === 0) {
    return { list: [] };
  }

  return {
    list: [
      {
        vod_id: String(id),
        vod_name: title || ("短剧 " + id),
        vod_pic: cover,
        vod_content: desc,
        vod_remarks: epUrls.length > 0 ? ("全" + epUrls.length + "集") : "",
        vod_play_from: "红果直链",
        vod_play_url: epUrls.join("#")
      }
    ]
  };
}

async function play(flag, id, flags) {
  let playTarget = id || "";
  let realStreamUrl = "";

  try {
    let playPageUrl = playTarget;
    if (!playPageUrl.startsWith("http")) {
      playPageUrl = BASE_URL + (playTarget.startsWith("/") ? playTarget : ("/player/" + playTarget));
    }

    const resp = await fetch(playPageUrl, {
      headers: {
        "User-Agent": USER_AGENT,
        "Referer": BASE_URL + "/"
      }
    });

    if (resp && resp.status === 200 && resp.body) {
      const body = resp.body;
      const m = body.match(/"main_url"\s*:\s*"([^"]+)"/);
      if (m && m[1]) {
        realStreamUrl = m[1].replace(/\\u0026/g, "&").replace(/\\u002F/g, "/").replace(/\\\//g, "/");
      }
      if (!realStreamUrl) {
        const m3u8Match = body.match(/https?:\/\/[^"'\s<>\\]+\.(?:m3u8|mp4)(?:\?[^"'\s<>\\]*)?/);
        if (m3u8Match) realStreamUrl = m3u8Match[0];
      }
    }
  } catch (e) {}

  if (!realStreamUrl && playTarget.startsWith("http") && (playTarget.includes(".mp4") || playTarget.includes(".m3u8"))) {
    realStreamUrl = playTarget;
  }

  if (!realStreamUrl) {
    return {
      parse: 0,
      url: "",
      header: {}
    };
  }

  return {
    parse: 0,
    url: realStreamUrl,
    header: {
      "User-Agent": USER_AGENT,
      "Referer": BASE_URL + "/"
    }
  };
}

async function search(wd, quick, pg) {
  pg = pg || 1;
  if (!wd) return { page: pg, list: [] };
  const dramas = [];

  try {
    const url = BASE_URL + "/incent_resource/suggestion?app_id=8662&query=" + encodeURIComponent(wd) + "&count=30";
    const resp = await fetch(url, {
      headers: {
        "User-Agent": USER_AGENT,
        "Referer": BASE_URL + "/"
      }
    });

    if (resp && resp.status === 200 && resp.body) {
      const json = JSON.parse(resp.body);
      const list = json.suggest_list || (json.data && json.data.suggest_list) || [];
      for (let i = 0; i < list.length; i++) {
        const item = list[i];
        const videoData = item.video_data || {};
        const id = videoData.series_id_str || videoData.series_id;
        if (id) {
          dramas.push({
            vod_id: String(id),
            vod_name: cleanText(item.name || videoData.title || item.keyword),
            vod_pic: videoData.cover_url || videoData.cover || "",
            vod_remarks: videoData.episode_cnt ? ("全" + videoData.episode_cnt + "集") : "",
            vod_content: cleanText(videoData.intro || videoData.abstract || ""),
            vod_year: "2024"
          });
        }
      }
    }
  } catch (e) {}

  return {
    page: pg,
    pagecount: 1,
    limit: 20,
    total: dramas.length,
    list: dramas
  };
}

var spider = {
  meta: meta,
  init: init,
  home: home,
  category: category,
  detail: detail,
  play: play,
  search: search
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = spider;
}
''',
  ),
];

/// 批量一键导入预设插件（仅供当前测试包使用）
Future<int> importPresetSources(JsSourceService service) async {
  int count = 0;
  for (final preset in kPresetJsSources) {
    final ok = await service.importScript(preset.script, preset.fileName);
    if (ok) {
      count++;
    }
  }
  return count;
}

/// 根据 ID 或文件名查找特定的预设数据源
PresetJsSource? findPresetSource(String idOrFileName) {
  for (final preset in kPresetJsSources) {
    if (preset.fileName == idOrFileName ||
        preset.fileName == '$idOrFileName.js' ||
        preset.script.contains('id: "$idOrFileName"') ||
        preset.script.contains("id: '$idOrFileName'")) {
      return preset;
    }
  }
  return null;
}

/// 单独导入指定的预设数据源
Future<bool> importSinglePresetSource(JsSourceService service, String sourceId) async {
  final preset = findPresetSource(sourceId);
  if (preset == null) return false;
  return await service.importScript(preset.script, preset.fileName);
}

/// 弹出预设数据源选择与分别导入对话框，支持逐个单独导入测试或一键导入全部
Future<void> showPresetSourceSelectionDialog({
  required BuildContext context,
  required JsSourceService service,
  VoidCallback? onSourceChanged,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final sources = service.sources;
          final activeId = service.activeSourceId;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.accentSubtle12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.flash_on_rounded, color: AppColors.hongguoRed, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '预置数据源分别导入',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '可分别单独导入任意预置 JS 插件，验证多源独立沙箱与数据隔离；亦可一键全量装载：',
                      style: TextStyle(fontSize: 12, color: AppColors.grey, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    ...kPresetJsSources.map((preset) {
                      final isImported = sources.any((s) => s.id == preset.id);
                      final isActive = activeId == preset.id;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceHighest : AppColors.lightSurfaceHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isActive
                                ? AppColors.hongguoRed
                                : (isDark ? AppColors.darkBorder : AppColors.greyLight),
                            width: isActive ? 1.5 : 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive
                                    ? AppColors.hongguoRed
                                    : (isDark ? AppColors.darkSurface : AppColors.white),
                              ),
                              child: Icon(
                                Icons.javascript_rounded,
                                color: isActive ? AppColors.white : AppColors.hongguoRed,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preset.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isActive ? AppColors.hongguoRed : null,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${preset.fileName} · ${preset.description}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: AppColors.grey),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.hongguoRed,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  '已激活',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              )
                            else if (isImported)
                              FilledButton.tonal(
                                key: ValueKey('activate-preset-${preset.id}'),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                ),
                                onPressed: () async {
                                  await service.switchSource(preset.id);
                                  setDialogState(() {});
                                  onSourceChanged?.call();
                                },
                                child: const Text('激活', style: TextStyle(fontSize: 12)),
                              )
                            else
                              FilledButton(
                                key: ValueKey('import-preset-${preset.id}'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.hongguoRed,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                ),
                                onPressed: () async {
                                  final ok = await importSinglePresetSource(service, preset.id);
                                  if (ok) {
                                    if (service.activeSourceId == null || service.activeSourceId!.isEmpty) {
                                      await service.switchSource(preset.id);
                                    }
                                    setDialogState(() {});
                                    onSourceChanged?.call();
                                    if (dialogCtx.mounted) {
                                      ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                        SnackBar(
                                          content: Text('已单独导入数据源：${preset.name}'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Text('导入', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              FilledButton.tonal(
                key: const ValueKey('import-all-presets'),
                onPressed: () async {
                  final count = await importPresetSources(service);
                  if (service.activeSourceId == null || service.activeSourceId!.isEmpty) {
                    await service.switchSource('hongguo');
                  }
                  setDialogState(() {});
                  onSourceChanged?.call();
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      SnackBar(
                        content: Text('已成功批量导入全部 $count 个预置数据源'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('一键导入全部'),
              ),
            ],
          );
        },
      );
    },
  );
}

