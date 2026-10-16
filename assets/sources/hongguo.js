/**
 * 官方免费短剧 CatPawOpen Spider (hongguo.js)
 * 适配 CatPawOpen / CatVodOpen 标准规范 v1.0.3
 */

const meta = {
  id: "hongguo",
  name: "官方免费短剧",
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

function safeJsonParse(text) {
  if (!text || typeof text !== "string") return null;
  try {
    let safe = text;
    if (/\d{15,}/.test(safe)) {
      let prev;
      do {
        prev = safe;
        safe = safe.replace(/([:\[,]\s*)(\d{15,})(\s*[,\]\}])/g, '$1"$2"$3');
      } while (safe !== prev);
    }
    return JSON.parse(safe);
  } catch (e) {
    try { return JSON.parse(text); } catch (_) { return null; }
  }
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
            const jsonSlice = body.slice(startIdx, i + 1);
            const parsed = safeJsonParse(jsonSlice);
            if (parsed) return parsed;
            break;
          }
        }
      }
    }
  }
  const nextMatch = body.match(/<script[^>]*id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/);
  if (nextMatch && nextMatch[1]) {
    const parsed = safeJsonParse(nextMatch[1]);
    if (parsed) return parsed;
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

  let cleanId = String(id || "").trim();
  if (cleanId.includes(":")) {
    cleanId = cleanId.split(":").pop();
  } else if (cleanId.includes("_") && !/^\d+$/.test(cleanId)) {
    cleanId = cleanId.split("_").pop();
  }
  const idDigits = cleanId.match(/\d{5,}/);
  if (idDigits) {
    cleanId = idDigits[0];
  }

  try {
    const url = BASE_URL + "/detail?series_id=" + cleanId;
    const resp = await fetch(url, {
      headers: {
        "User-Agent": USER_AGENT,
        "Referer": BASE_URL + "/"
      }
    });

    if (resp && resp.status === 200 && resp.body) {
      const body = resp.body;
      const routerData = parseJsonFromHtml(body);
      let epTotalCount = 0;
      if (routerData && routerData.loaderData) {
        for (const k of Object.keys(routerData.loaderData)) {
          const lData = routerData.loaderData[k];
          const sDetail = lData && (lData.seriesDetail || lData.videoDetail || lData.series_info);
          if (sDetail) {
            const sTitle = cleanText(sDetail.series_name || sDetail.series_title || sDetail.title || sDetail.name);
            if (sTitle && !title) title = sTitle;
            const sCover = sDetail.series_cover || sDetail.cover || sDetail.cover_url || "";
            if (sCover && !cover) cover = sCover;
            const sDesc = cleanText(sDetail.series_intro || sDetail.intro || sDetail.abstract || sDetail.desc);
            if (sDesc && !desc) desc = sDesc;
            if (Array.isArray(sDetail.vid_list) && sDetail.vid_list.length > 0) {
              vidList = sDetail.vid_list;
              break;
            }
            if (sDetail.episode_cnt || sDetail.episode_total_cnt) {
              epTotalCount = Number(sDetail.episode_cnt || sDetail.episode_total_cnt) || 0;
            }
          }
        }
      }

      if (vidList.length === 0) {
        const vidMatch = body.match(/vid_list[^:]*:\s*\[([^\]]*)\]/);
        if (vidMatch && vidMatch[1]) {
          const ids = vidMatch[1].match(/\d{15,}/g);
          if (ids && ids.length > 0) {
            vidList = ids;
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

  if (vidList.length === 0 && cleanId) {
    try {
      const pUrl = BASE_URL + "/player/" + cleanId;
      const pResp = await fetch(pUrl, {
        headers: {
          "User-Agent": USER_AGENT,
          "Referer": BASE_URL + "/"
        }
      });
      if (pResp && pResp.status === 200 && pResp.body) {
        const pBody = pResp.body;
        const vidMatch = pBody.match(/vid_list[^:]*:\s*\[([^\]]*)\]/);
        if (vidMatch && vidMatch[1]) {
          const ids = vidMatch[1].match(/\d{15,}/g);
          if (ids && ids.length > 0) {
            vidList = ids;
          }
        }
        if (!title) {
          const tMatch = pBody.match(/<title>([^<]+)<\/title>/);
          if (tMatch && tMatch[1]) title = cleanText(tMatch[1].split(/[-_|]/)[0]);
        }
      }
    } catch (e) {}
  }

  const epUrls = [];
  if (vidList.length > 0) {
    for (let i = 0; i < vidList.length; i++) {
      epUrls.push("第" + (i + 1) + "集$" + BASE_URL + "/player/" + cleanId + "/" + vidList[i]);
    }
  } else if (epTotalCount > 0) {
    for (let i = 0; i < epTotalCount; i++) {
      epUrls.push("第" + (i + 1) + "集$" + cleanId + "_" + (i + 1));
    }
  }

  if (!title && epUrls.length === 0) {
    return { list: [] };
  }

  return {
    list: [
      {
        vod_id: String(cleanId),
        vod_name: title || ("短剧 " + cleanId),
        vod_pic: cover,
        vod_content: desc,
        vod_remarks: epUrls.length > 0 ? ("全" + epUrls.length + "集") : "",
        vod_play_from: "官方直链",
        vod_play_url: epUrls.join("#")
      }
    ]
  };
}

async function play(flag, id, flags) {
  let playTarget = (id || "").toString().trim();
  if (playTarget.includes(":")) {
    playTarget = playTarget.split(":").pop().trim();
  }
  let realStreamUrl = "";

  if (playTarget.startsWith("http") && (playTarget.includes(".mp4") || playTarget.includes(".m3u8"))) {
    return {
      parse: 0,
      url: playTarget,
      header: {
        "User-Agent": USER_AGENT,
        "Referer": BASE_URL + "/"
      }
    };
  }

  let seriesId = "";
  let itemId = "";
  let episodeIndex = 1;

  const segments = playTarget.split(/[\/_]/).filter(Boolean);
  const longDigits = [];
  let shortDigit = 0;

  for (const seg of segments) {
    const m = seg.match(/\d+/);
    if (!m) continue;
    const numStr = m[0];
    if (numStr.length >= 15) {
      longDigits.push(numStr);
    } else if (numStr.length >= 1 && shortDigit === 0) {
      shortDigit = parseInt(numStr, 10);
    }
  }

  const isCorruptedId = function(s) {
    return !s || !/^\d{15,}$/.test(s) || /000$/.test(s);
  };

  if (longDigits.length >= 2) {
    seriesId = longDigits[0];
    itemId = longDigits[1];
    if (isCorruptedId(itemId)) {
      itemId = "";
    }
  } else if (longDigits.length === 1) {
    seriesId = longDigits[0];
    if (shortDigit > 0) {
      episodeIndex = shortDigit;
    }
  }

  if (itemId && itemId.length >= 15 && !isCorruptedId(itemId)) {
    const playPageUrl = BASE_URL + "/player/" + (seriesId || itemId) + "/" + itemId;
    try {
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
          const mContent = body.match(/"contentUrl"\s*:\s*"([^"]+)"/);
          if (mContent && mContent[1]) realStreamUrl = mContent[1];
        }
        if (!realStreamUrl) {
          const m3u8Match = body.match(/https?:\/\/[^"'\s<>\\]+\.(?:m3u8|mp4)(?:\?[^"'\s<>\\]*)?/);
          if (m3u8Match) realStreamUrl = m3u8Match[0];
        }
      }
    } catch (e) {}

    if (!realStreamUrl && !isCorruptedId(itemId)) {
      realStreamUrl = BASE_URL + "/video/public/" + itemId + "/360p.mp4";
    }
  }

  if (!realStreamUrl && seriesId) {
    let targetVid = "";
    try {
      const detailUrl = BASE_URL + "/detail?series_id=" + seriesId;
      const dResp = await fetch(detailUrl, {
        headers: {
          "User-Agent": USER_AGENT,
          "Referer": BASE_URL + "/"
        }
      });
      if (dResp && dResp.status === 200 && dResp.body) {
        const dBody = dResp.body;
        const vidMatch = dBody.match(/(?:vid_list|item_list|video_list|episode_list)[^:]*:\s*\[([^\]]*)\]/);
        if (vidMatch && vidMatch[1]) {
          const vids = vidMatch[1].match(/\d{15,}/g);
          if (vids && vids.length > 0) {
            const idx = Math.max(0, Math.min(episodeIndex - 1, vids.length - 1));
            targetVid = vids[idx];
          }
        }
        if (!targetVid) {
          const allVids = dBody.match(/\/player\/\d{5,}\/(\d{15,})/g);
          if (allVids && allVids.length > 0) {
            const vids = allVids.map(function(s) { return s.split("/").pop(); });
            const idx = Math.max(0, Math.min(episodeIndex - 1, vids.length - 1));
            targetVid = vids[idx];
          }
        }
      }
    } catch (e) {}

    if (targetVid) {
      const playPageUrl = BASE_URL + "/player/" + seriesId + "/" + targetVid;
      try {
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
            const mContent = body.match(/"contentUrl"\s*:\s*"([^"]+)"/);
            if (mContent && mContent[1]) realStreamUrl = mContent[1];
          }
        }
      } catch (e) {}
      if (!realStreamUrl) {
        realStreamUrl = BASE_URL + "/video/public/" + targetVid + "/360p.mp4";
      }
    } else {
      const playPageUrl = BASE_URL + "/player/" + seriesId;
      try {
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
            const mContent = body.match(/"contentUrl"\s*:\s*"([^"]+)"/);
            if (mContent && mContent[1]) realStreamUrl = mContent[1];
          }
          if (!realStreamUrl) {
            const m3u8Match = body.match(/https?:\/\/[^"'\s<>\\]+\.(?:m3u8|mp4)(?:\?[^"'\s<>\\]*)?/);
            if (m3u8Match) realStreamUrl = m3u8Match[0];
          }
          if (!realStreamUrl) {
            const vidMatch = body.match(/(?:vid_list|item_list|video_list|episode_list)[^:]*:\s*\[([^\]]*)\]/);
            if (vidMatch && vidMatch[1]) {
              const vids = vidMatch[1].match(/\d{15,}/g);
              if (vids && vids.length > 0) {
                const idx = Math.max(0, Math.min(episodeIndex - 1, vids.length - 1));
                realStreamUrl = BASE_URL + "/video/public/" + vids[idx] + "/360p.mp4";
              }
            }
          }
        }
      } catch (e) {}
      if (!realStreamUrl && seriesId.length >= 15) {
        realStreamUrl = BASE_URL + "/video/public/" + seriesId + "/360p.mp4";
      }
    }
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

    let rawBody = "";
    if (resp && resp.status === 200) {
      if (typeof resp.text === "function") {
        rawBody = await resp.text();
      } else if (resp.body) {
        rawBody = String(resp.body);
      }
    }

    if (rawBody) {
      let safeBody = rawBody.replace(/("(?:series_)?id"):\s*(\d{15,})/g, '$1:"$2"');
      safeBody = safeBody.replace(/("(?:keyword)"):\s*(\d{15,})/g, '$1:"$2"');
      const json = JSON.parse(safeBody);
      const list = json.suggest_list || (json.data && json.data.suggest_list) || [];
      for (let i = 0; i < list.length; i++) {
        const item = list[i];
        const videoData = item.video_data || {};

        let rawId = videoData.series_id || videoData.series_id_str || "";
        if (!rawId && item.keyword && /^\d{15,}$/.test(String(item.keyword).trim())) {
          rawId = String(item.keyword).trim();
        }
        if (!rawId && item.series_id) {
          rawId = String(item.series_id).trim();
        }
        const id = String(rawId).trim();
        if (!id || !/^\d+$/.test(id)) {
          continue;
        }

        const rawPic = videoData.series_cover || videoData.cover_url || videoData.cover || videoData.thumb_url || item.series_cover || item.cover_url || item.cover || item.thumb_url || "";
        let pic = String(rawPic).trim();
        if (pic.startsWith("//")) pic = "https:" + pic;

        const hasVids = Array.isArray(videoData.vid_list) && videoData.vid_list.length > 0;
        if (!pic && !hasVids) {
          continue;
        }

        const title = cleanText(videoData.series_title || videoData.series_name || videoData.title || item.name || item.keyword);
        if (!title) continue;

        const epCnt = videoData.episode_cnt || item.episode_cnt || 0;
        const remark = videoData.episode_right_text || item.episode_right_text || (epCnt ? ("全" + epCnt + "集") : "");
        const intro = cleanText(videoData.series_intro || videoData.video_desc || videoData.intro || videoData.abstract || videoData.desc || item.series_intro || item.intro || item.desc);

        dramas.push({
          vod_id: String(id),
          vod_name: title,
          vod_pic: pic,
          vod_remarks: remark,
          vod_content: intro || (title + (epCnt ? (" · 全" + epCnt + "集") : "")),
          vod_year: "2024"
        });
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
