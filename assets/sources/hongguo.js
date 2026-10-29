/**
 * 官方免费短剧 CatPawOpen Spider (hongguo.js)
 * 适配 CatPawOpen / CatVodOpen 标准规范 v1.0.4
 * 支持官方 App API 与 Web 路由双轨容错解析
 */

const meta = {
  id: "hongguo",
  name: "官方免费短剧",
  version: "1.1.0-dev.10",
  description: "官方首发短剧源，包含海量都市爽文、战神回归、现代甜宠等优质短剧",
  author: "社区开发者",
  type: "video",
  icon: "",
  features: ["search", "suggestions", "rankingBoards", "rankings", "recommendations", "categories", "danmaku", "seriesSeasons", "feed"]
};

const BASE_URL = "https://hongguoduanju.com";
const APP_API_BASE = "https://api5-normal-sinfonlineb.fqnovel.com";
const USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
const APP_USER_AGENT = "com.phoenix.read/73532 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)";

function cleanText(text) {
  if (!text) return "";
  return String(text).replace(/<[^>]+>/g, "").trim();
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

function safeBase64Decode(str) {
  if (!str || typeof str !== "string") return "";
  try {
    const trimmed = str.trim();
    if (typeof Buffer !== "undefined") {
      return Buffer.from(trimmed, "base64").toString("utf8");
    }
    if (typeof atob === "function") {
      return atob(trimmed);
    }
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const normalized = trimmed.replace(/\s/g, "").replace(/-/g, "+").replace(/_/g, "/");
    if (/[^A-Za-z0-9+/=]/.test(normalized)) return "";
    let bits = 0;
    let value = 0;
    let result = "";
    for (let i = 0; i < normalized.length && normalized[i] !== "="; i++) {
      value = (value << 6) | alphabet.indexOf(normalized[i]);
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        result += String.fromCharCode((value >>> bits) & 255);
      }
    }
    return result;
  } catch (_) {}
  return "";
}

// 纯 JS MD5 实现（自包含，零外部库依赖）
function md5(string) {
  function rotateLeft(lValue, iShiftBits) {
    return (lValue << iShiftBits) | (lValue >>> (32 - iShiftBits));
  }
  function addUnsigned(lX, lY) {
    var lX4 = lX & 0x40000000;
    var lY4 = lY & 0x40000000;
    var lX8 = lX & 0x80000000;
    var lY8 = lY & 0x80000000;
    var lResult = (lX & 0x3FFFFFFF) + (lY & 0x3FFFFFFF);
    if (lX4 & lY4) return lResult ^ 0x80000000 ^ lX8 ^ lY8;
    if (lX4 | lY4) {
      if (lResult & 0x40000000) return lResult ^ 0xC0000000 ^ lX8 ^ lY8;
      else return lResult ^ 0x40000000 ^ lX8 ^ lY8;
    } else {
      return lResult ^ lX8 ^ lY8;
    }
  }
  function F(x, y, z) { return (x & y) | ((~x) & z); }
  function G(x, y, z) { return (x & z) | (y & (~z)); }
  function H(x, y, z) { return x ^ y ^ z; }
  function I(x, y, z) { return y ^ (x | (~z)); }
  function FF(a, b, c, d, x, s, ac) {
    a = addUnsigned(a, addUnsigned(addUnsigned(F(b, c, d), x), ac));
    return addUnsigned(rotateLeft(a, s), b);
  }
  function GG(a, b, c, d, x, s, ac) {
    a = addUnsigned(a, addUnsigned(addUnsigned(G(b, c, d), x), ac));
    return addUnsigned(rotateLeft(a, s), b);
  }
  function HH(a, b, c, d, x, s, ac) {
    a = addUnsigned(a, addUnsigned(addUnsigned(H(b, c, d), x), ac));
    return addUnsigned(rotateLeft(a, s), b);
  }
  function II(a, b, c, d, x, s, ac) {
    a = addUnsigned(a, addUnsigned(addUnsigned(I(b, c, d), x), ac));
    return addUnsigned(rotateLeft(a, s), b);
  }
  function convertToWordArray(str) {
    var lWordCount;
    var lMessageLength = str.length;
    var lNumberOfWords_temp1 = lMessageLength + 8;
    var lNumberOfWords_temp2 = (lNumberOfWords_temp1 - (lNumberOfWords_temp1 % 64)) / 64;
    var lNumberOfWords = (lNumberOfWords_temp2 + 1) * 16;
    var lWordArray = Array(lNumberOfWords - 1);
    var lBytePosition = 0;
    var lByteCount = 0;
    while (lByteCount < lMessageLength) {
      lWordCount = (lByteCount - (lByteCount % 4)) / 4;
      lBytePosition = (lByteCount % 4) * 8;
      lWordArray[lWordCount] = (lWordArray[lWordCount] | (str.charCodeAt(lByteCount) << lBytePosition));
      lByteCount++;
    }
    lWordCount = (lByteCount - (lByteCount % 4)) / 4;
    lBytePosition = (lByteCount % 4) * 8;
    lWordArray[lWordCount] = lWordArray[lWordCount] | (0x80 << lBytePosition);
    lWordArray[lNumberOfWords - 2] = lMessageLength << 3;
    lWordArray[lNumberOfWords - 1] = lMessageLength >>> 29;
    return lWordArray;
  }
  function wordToHex(lValue) {
    var WordToHexValue = "", WordToHexValue_temp = "", lByte, lCount;
    for (lCount = 0; lCount <= 3; lCount++) {
      lByte = (lValue >>> (lCount * 8)) & 255;
      WordToHexValue_temp = "0" + lByte.toString(16);
      WordToHexValue = WordToHexValue + WordToHexValue_temp.substr(WordToHexValue_temp.length - 2, 2);
    }
    return WordToHexValue;
  }
  var x = Array();
  var k, AA, BB, CC, DD, a, b, c, d;
  var S11=7, S12=12, S13=17, S14=22;
  var S21=5, S22=9 , S23=14, S24=20;
  var S31=4, S32=11, S33=16, S34=23;
  var S41=6, S42=10, S43=15, S44=21;
  x = convertToWordArray(unescape(encodeURIComponent(string)));
  a = 0x67452301; b = 0xEFCDAB89; c = 0x98BADCFE; d = 0x10325476;
  for (k = 0; k < x.length; k += 16) {
    AA = a; BB = b; CC = c; DD = d;
    a = FF(a, b, c, d, x[k + 0], S11, 0xD76AA478);
    d = FF(d, a, b, c, x[k + 1], S12, 0xE8C7B756);
    c = FF(c, d, a, b, x[k + 2], S13, 0x242070DB);
    b = FF(b, c, d, a, x[k + 3], S14, 0xC1BDCEEE);
    a = FF(a, b, c, d, x[k + 4], S11, 0xF57C0FAF);
    d = FF(d, a, b, c, x[k + 5], S12, 0x4787C62A);
    c = FF(c, d, a, b, x[k + 6], S13, 0xA8304613);
    b = FF(b, c, d, a, x[k + 7], S14, 0xFD469501);
    a = FF(a, b, c, d, x[k + 8], S11, 0x698098D8);
    d = FF(d, a, b, c, x[k + 9], S12, 0x8B44F7AF);
    c = FF(c, d, a, b, x[k + 10], S13, 0xFFFF5BB1);
    b = FF(b, c, d, a, x[k + 11], S14, 0x895CD7BE);
    a = FF(a, b, c, d, x[k + 12], S11, 0x6B901122);
    d = FF(d, a, b, c, x[k + 13], S12, 0xFD987193);
    c = FF(c, d, a, b, x[k + 14], S13, 0xA679438E);
    b = FF(b, c, d, a, x[k + 15], S14, 0x49B40821);
    a = GG(a, b, c, d, x[k + 1], S21, 0xF61E2562);
    d = GG(d, a, b, c, x[k + 6], S22, 0xC040B340);
    c = GG(c, d, a, b, x[k + 11], S23, 0x265E5A51);
    b = GG(b, c, d, a, x[k + 0], S24, 0xE9B6C7AA);
    a = GG(a, b, c, d, x[k + 5], S21, 0xD62F105D);
    d = GG(d, a, b, c, x[k + 10], S22, 0x2441453);
    c = GG(c, d, a, b, x[k + 15], S23, 0xD8A1E681);
    b = GG(b, c, d, a, x[k + 4], S24, 0xE7D3FBC8);
    a = GG(a, b, c, d, x[k + 9], S21, 0x21E1CDE6);
    d = GG(d, a, b, c, x[k + 14], S22, 0xC33707D6);
    c = GG(c, d, a, b, x[k + 3], S23, 0xF4D50D87);
    b = GG(b, c, d, a, x[k + 8], S24, 0x455A14ED);
    a = GG(a, b, c, d, x[k + 13], S21, 0xA9E3E905);
    d = GG(d, a, b, c, x[k + 2], S22, 0xFCEFA3F8);
    c = GG(c, d, a, b, x[k + 7], S23, 0x676F02D9);
    b = GG(b, c, d, a, x[k + 12], S24, 0x8D2A4C8A);
    a = HH(a, b, c, d, x[k + 5], S31, 0xFFFA3942);
    d = HH(d, a, b, c, x[k + 8], S32, 0x8771F681);
    c = HH(c, d, a, b, x[k + 11], S33, 0x6D9D6122);
    b = HH(b, c, d, a, x[k + 14], S34, 0xFDE5380C);
    a = HH(a, b, c, d, x[k + 1], S31, 0xA4BEEA44);
    d = HH(d, a, b, c, x[k + 4], S32, 0x4BDECFA9);
    c = HH(c, d, a, b, x[k + 7], S33, 0xF6BB4B60);
    b = HH(b, c, d, a, x[k + 10], S34, 0xBEBFBC70);
    a = HH(a, b, c, d, x[k + 13], S31, 0x289B7EC6);
    d = HH(d, a, b, c, x[k + 0], S32, 0xEAA127FA);
    c = HH(c, d, a, b, x[k + 3], S33, 0xD4EF3085);
    b = HH(b, c, d, a, x[k + 6], S34, 0x4881D05);
    a = HH(a, b, c, d, x[k + 9], S31, 0xD9D4D039);
    d = HH(d, a, b, c, x[k + 12], S32, 0xE6DB99E5);
    c = HH(c, d, a, b, x[k + 15], S33, 0x1FA27CF8);
    b = HH(b, c, d, a, x[k + 2], S34, 0xC4AC5665);
    a = II(a, b, c, d, x[k + 0], S41, 0xF4292244);
    d = II(d, a, b, c, x[k + 7], S42, 0x432AFF97);
    c = II(c, d, a, b, x[k + 14], S43, 0xAB9423A7);
    b = II(b, c, d, a, x[k + 5], S44, 0xFC93A039);
    a = II(a, b, c, d, x[k + 12], S41, 0x655B59C3);
    d = II(d, a, b, c, x[k + 3], S42, 0x8F0CCC92);
    c = II(c, d, a, b, x[k + 10], S43, 0xFFEFF47D);
    b = II(b, c, d, a, x[k + 1], S44, 0x85845DD1);
    a = II(a, b, c, d, x[k + 8], S41, 0x6FA87E4F);
    d = II(d, a, b, c, x[k + 15], S42, 0xFE2CE6E0);
    c = II(c, d, a, b, x[k + 6], S43, 0xA3014314);
    b = II(b, c, d, a, x[k + 13], S44, 0x4E0811A1);
    a = II(a, b, c, d, x[k + 4], S41, 0xF7537E82);
    d = II(d, a, b, c, x[k + 11], S42, 0xBD3AF235);
    c = II(c, d, a, b, x[k + 2], S43, 0x2AD7D2BB);
    b = II(b, c, d, a, x[k + 9], S44, 0xEB86D391);
    a = addUnsigned(a, AA);
    b = addUnsigned(b, BB);
    c = addUnsigned(c, CC);
    d = addUnsigned(d, DD);
  }
  return (wordToHex(a) + wordToHex(b) + wordToHex(c) + wordToHex(d)).toLowerCase();
}

function hexToBytes(hex) {
  var bytes = [];
  for (var c = 0; c < hex.length; c += 2)
    bytes.push(parseInt(hex.substr(c, 2), 16));
  return bytes;
}

function bytesToHex(bytes) {
  var hex = [];
  for (var i = 0; i < bytes.length; i++) {
    var current = bytes[i] < 0 ? bytes[i] + 256 : bytes[i];
    hex.push((current >>> 4).toString(16));
    hex.push((current & 0xF).toString(16));
  }
  return hex.join("");
}

function rotl8(val, n) {
  val &= 0xFF;
  return ((val << n) | (val >>> (8 - n))) & 0xFF;
}

function reverse8(b) {
  b = ((b & 0xF0) >> 4) | ((b & 0x0F) << 4);
  b = ((b & 0xCC) >> 2) | ((b & 0x33) << 2);
  b = ((b & 0xAA) >> 1) | ((b & 0x55) << 1);
  return b & 0xFF;
}

// 字节跳动 App API Gorgon 签名生成器
function signGorgon(rawQuery, bodyStr, nowMs) {
  var timestamp = Math.floor(nowMs / 1000);
  var qHash = hexToBytes(md5(rawQuery));
  var payload = [];
  for (var i = 0; i < 20; i++) payload.push(0);
  for (var i = 0; i < 4; i++) payload[i] = qHash[i];
  var stub = "";
  if (bodyStr && bodyStr.length > 0) {
    var bHashHex = md5(bodyStr);
    var bHash = hexToBytes(bHashHex);
    for (var i = 0; i < 4; i++) payload[4 + i] = bHash[i];
    stub = bHashHex.toUpperCase();
  }
  payload[12] = 0; payload[13] = 6; payload[14] = 11; payload[15] = 28;
  payload[16] = (timestamp >>> 24) & 0xFF;
  payload[17] = (timestamp >>> 16) & 0xFF;
  payload[18] = (timestamp >>> 8) & 0xFF;
  payload[19] = timestamp & 0xFF;

  var key = [0x44, 0xb9, 0xb9, 0xd9, 0xa4, 0xae, 0xf9, 0xfc, 0xa4, 0x93, 0xaa, 0x75, 0x7c, 0xa3, 0xc2, 0xc4, 0xa4, 0x96, 0x93, 0x8f];
  for (var i = 0; i < 20; i++) {
    payload[i] ^= key[i];
  }
  for (var i = 0; i < 20; i++) {
    var mixed = rotl8(payload[i], 4) ^ payload[(i + 1) % 20];
    payload[i] = (reverse8(mixed) ^ 0xff ^ 20) & 0xFF;
  }
  var prefix = [0x84, 0x04, 0x40, 0x1c, 0, 0];
  var signature = bytesToHex(prefix.concat(payload));

  var headers = {
    "X-Khronos": String(timestamp),
    "X-Gorgon": signature,
    "X-SS-Req-Ticket": String(nowMs),
    "X-SS-From-Web": "0",
    "Sdk-Version": "2",
    "User-Agent": APP_USER_AGENT
  };
  if (stub) headers["X-SS-STUB"] = stub;
  return headers;
}

// 官方 App API 获取短剧详情及分集列表
async function fetchAppDetail(seriesId) {
  const id = String(seriesId || '');
  if (!/^\d{10,}$/.test(id)) return null;
  const detailCache = (globalThis.__hongguoDetailCache = globalThis.__hongguoDetailCache || new Map());
  const cached = detailCache.get(id) || globalThis.__hongguoFeedDetails?.get(id);
  if (cached && Date.now() - cached.updated < 15 * 60 * 1000 &&
      Array.isArray(cached.data?.video_list) && cached.data.video_list.length >= Number(cached.data.episode_cnt || 1)) return cached.data;
  const data = await HongguoApp.fetchAppDetailRaw(id);
  if (!data || !Array.isArray(data.video_list) || !data.video_list.length) {
    throw Object.assign(new Error('官方接口暂未返回可用分集，请重试'), { code: 'MISSING_EPISODE' });
  }
  detailCache.set(id, { data, updated: Date.now() });
  return data;
}

// 官方 App API 获取指定视频的完整播放流模型
async function fetchAppVideoModel(videoId) {
  if (!videoId || !/^\d{10,}$/.test(String(videoId))) return null;
  try {
    var now = Date.now();
    var qs = "aid=8662&app_name=novelread&version_code=73532&version_name=7.3.5.32&manifest_version_code=73532&update_version_code=73532&channel=update_64&device_platform=android&os=android&ssmix=a&device_type=25053RT47C&device_brand=Redmi&language=zh&os_api=36&os_version=16&resolution=1280*2772&dpi=520&ac=wifi&device_id=7361909012345678901&iid=7361909012345678902&_rticket=" + now;
    var body = JSON.stringify({
      video_id: String(videoId),
      content_type: 1,
      biz_param: {
        need_all_video_definition: true,
        video_platform: 3
      }
    });
    var headers = signGorgon(qs, body, now);
    headers["Content-Type"] = "application/json; charset=utf-8";

    var url = APP_API_BASE + "/novel/player/video_model/v1/?" + qs;
    var resp = await fetch(url, {
      method: "POST",
      headers: headers,
      body: body
    });

    if (resp) {
      var raw = typeof resp.text === "function" ? await resp.text() : resp.body;
      if (raw && typeof raw === "string" && raw.trim().length > 0) {
        var parsed = safeJsonParse(raw);
        if (parsed && parsed.data && parsed.data.video_model) {
          var model = parsed.data.video_model;
          if (typeof model === "string") {
            model = safeJsonParse(model);
          }
          return model;
        }
        return { isError: true, status: resp.status, raw: String(raw).substring(0, 300) };
      }
      return { isError: true, status: resp.status, raw: "EMPTY_BODY" };
    }
    return { isError: true, status: 0, raw: "NO_RESP" };
  } catch (err) {
    return { isError: true, status: -1, raw: String(err) };
  }
}

// 从 video_model 中智能提取最佳播放流（自动进行 Base64 解码，优选 H.264 兼容编码）
function extractStreamFromVideoModel(model) {
  if (!model) return "";
  var variants = [];
  if (Array.isArray(model.video_list)) {
    variants = model.video_list;
  } else if (model.video_list && typeof model.video_list === "object") {
    var keys = Object.keys(model.video_list);
    for (var i = 0; i < keys.length; i++) {
      variants.push(model.video_list[keys[i]]);
    }
  }

  function resolveAddress(addr) {
    if (!addr || typeof addr !== "string") return "";
    var s = addr.trim();
    if (!s.startsWith("http://") && !s.startsWith("https://")) {
      var dec = safeBase64Decode(s);
      if (dec && (dec.startsWith("http://") || dec.startsWith("https://"))) {
        s = dec.trim();
      }
    }
    if (s.startsWith("http://") || s.startsWith("https://")) {
      return s;
    }
    return "";
  }

  var candidates = [];
  for (var i = 0; i < variants.length; i++) {
    var item = variants[i];
    if (!item) continue;
    var meta = item.video_meta || {};
    var codec = String(meta.codec_type || "").toLowerCase();
    // 忽略 bytevc2 等部分系统不兼容的编码
    if (codec.includes("bytevc2")) continue;

    var keys = ["main_url", "backup_url", "backup_url_1", "backup_url_2", "url_list"];
    for (var j = 0; j < keys.length; j++) {
      var rawVal = item[keys[j]];
      if (Array.isArray(rawVal)) {
        for (var k = 0; k < rawVal.length; k++) {
          var u = resolveAddress(rawVal[k]);
          if (u) candidates.push({ url: u, codec: codec });
        }
      } else if (typeof rawVal === "string") {
        var u = resolveAddress(rawVal);
        if (u) candidates.push({ url: u, codec: codec });
      }
    }
  }

  // 优先选择 h264 / avc1 标准编码
  for (var i = 0; i < candidates.length; i++) {
    if (candidates[i].codec === "h264" || candidates[i].codec === "avc1") {
      return candidates[i].url;
    }
  }
  if (candidates.length > 0) {
    return candidates[0].url;
  }
  return "";
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

function cleanCoverUrl(url) {
  if (!url || typeof url !== "string") return "";
  const trimmed = url.trim();
  const novelPicMatch = trimmed.match(/novel-pic\/([a-zA-Z0-9_-]+)/);
  if (novelPicMatch) {
    return "https://p3-novel.byteimg.com/novel-pic/" + novelPicMatch[1] + "~tplv-shrink:640:0.image";
  }
  if (trimmed.includes(".heic")) {
    return trimmed.replace(/\.heic/g, ".image");
  }
  return trimmed;
}

async function init(ext) {
  return true;
}

async function home(filter) {
  return {
    class: [
      { type_id: "real-drama", type_name: "真人剧" },
      { type_id: "comic-drama", type_name: "漫剧" },
      { type_id: "ai-drama", type_name: "AI剧" }
    ],
    filters: {}
  };
}

async function category(tid, pg, filter, extend) {
  pg = pg || 1;
  let route = (!tid || tid === "short_play" || tid === "all") ? "real-drama" : tid;
  if (route === "comic") {
    route = "comic-drama";
  }
  const url = BASE_URL + "/category/" + route + (pg > 1 ? ("?page=" + pg) : "");
  let items = [];

  try {
    const resp = await fetch(url, {
      headers: {
        "User-Agent": USER_AGENT,
        "Referer": BASE_URL + "/"
      }
    });

    const body = resp && (typeof resp.text === "function" ? await resp.text() : resp.body);
    if (body) {
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
              const pic = cleanCoverUrl(vd.series_cover || vd.cover || vd.thumb_url || vd.cover_url || dr.series_cover || dr.cover || "");
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
                vod_pic: cleanCoverUrl(cover),
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
    limit: 40,
    total: items.length,
    list: items
  };
}

async function detail(id) {
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

  let title = "";
  let cover = "";
  let desc = "";
  let vidList = [];
  let epTotalCount = 0;
  let accessibleCount = 0;

  // 1. 优先调用官方 App API 获取权威分集数据与精准 vid
  const appData = await fetchAppDetail(cleanId);
  if (appData) {
    title = cleanText(appData.series_title || appData.series_name || appData.title);
    cover = cleanCoverUrl(appData.series_cover || appData.cover || "");
    desc = cleanText(appData.series_intro || appData.video_desc || appData.intro || appData.desc);
    epTotalCount = Number(appData.episode_cnt || 0);
    accessibleCount = Number(appData.accessible_episode_cnt || appData.accessible_count || 0);

    if (Array.isArray(appData.video_list) && appData.video_list.length > 0) {
      for (let i = 0; i < appData.video_list.length; i++) {
        const item = appData.video_list[i];
        const vid = item.vid || item.video_id;
        if (vid) {
          vidList.push(String(vid));
        }
      }
    }
  }

  // 2. 若 App 接口未返回分集，回退走网页 Web 路由解析
  if (vidList.length === 0) {
    try {
      const url = BASE_URL + "/detail?series_id=" + cleanId;
      const resp = await fetch(url, {
        headers: {
          "User-Agent": USER_AGENT,
          "Referer": BASE_URL + "/"
        }
      });

      const body = resp && (typeof resp.text === "function" ? await resp.text() : resp.body);
      if (body) {
        const routerData = parseJsonFromHtml(body);
        if (routerData && routerData.loaderData) {
          for (const k of Object.keys(routerData.loaderData)) {
            const lData = routerData.loaderData[k];
            const sDetail = lData && (lData.seriesDetail || lData.videoDetail || lData.series_info);
            if (sDetail) {
              const sTitle = cleanText(sDetail.series_name || sDetail.series_title || sDetail.title || sDetail.name);
              if (sTitle && !title) title = sTitle;
              const sCover = sDetail.series_cover || sDetail.cover || sDetail.cover_url || "";
              if (sCover && !cover) cover = cleanCoverUrl(sCover);
              const sDesc = cleanText(sDetail.series_intro || sDetail.intro || sDetail.abstract || sDetail.desc);
              if (sDesc && !desc) desc = sDesc;
              accessibleCount = Number(sDetail.accessible_episode_cnt || 0);
              if (Array.isArray(sDetail.vid_list) && sDetail.vid_list.length > 0) {
                for (let j = 0; j < sDetail.vid_list.length; j++) {
                  const v = String(sDetail.vid_list[j]);
                  if (v) vidList.push(v);
                }
                break;
              }
              if (sDetail.episode_cnt || sDetail.episode_total_cnt) {
                epTotalCount = Number(sDetail.episode_cnt || sDetail.episode_total_cnt) || 0;
              }
              if (sDetail.accessible_episode_cnt) {
                accessibleCount = Number(sDetail.accessible_episode_cnt) || 0;
              }
            }
          }
        }

        if (vidList.length === 0) {
          const vidMatch = body.match(/vid_list[^:]*:\s*\[([^\]]*)\]/);
          if (vidMatch && vidMatch[1]) {
            const ids = vidMatch[1].match(/\d{15,}/g);
            if (ids && ids.length > 0) {
              vidList = ids.filter(Boolean);
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
                if (node.name && !title) title = cleanText(node.name);
                if (node.description && !desc) desc = cleanText(node.description);
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
            if (domCover && !cover) cover = cleanCoverUrl(domCover);
            const domDesc = cleanText(doc.find(".detail-intro, .desc, meta[name='description']").text() || doc.find("meta[name='description']").attr("content") || "");
            if (domDesc && !desc) desc = domDesc;
          }
        }
      }
    } catch (e) {}
  }

  if (vidList.length > 0) {
    try {
      const detailCache = (globalThis.__hongguoDetailCache = globalThis.__hongguoDetailCache || new Map());
      const cachedEntry = detailCache.get(String(cleanId));
      const existingData = (cachedEntry && cachedEntry.data) || {};
      const videoListFromVids = vidList.map(function (v) { return { vid: String(v), video_id: String(v) }; });
      detailCache.set(String(cleanId), {
        data: {
          ...existingData,
          series_id: String(cleanId),
          series_title: title || existingData.series_title || "",
          series_cover: cover || existingData.series_cover || "",
          series_intro: desc || existingData.series_intro || "",
          episode_cnt: epTotalCount || vidList.length,
          video_list: videoListFromVids
        },
        updated: Date.now()
      });
    } catch (_) {}
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
  } else if (cleanId) {
    // 关键保底机制：只要具有有效短剧 ID，即便 Web 端网络抖动未解析出分集，至少提供第1集标准播放路由，确保 vod_play_url 恒有效
    epUrls.push("第1集$" + BASE_URL + "/player/" + cleanId + "/" + cleanId);
  }

  if (!title && epUrls.length === 0) {
    return { list: [] };
  }

  let remarks = "";
  if (epUrls.length > 0) {
    remarks = "全" + epUrls.length + "集";
  } else if (epTotalCount === 0) {
    remarks = "全0集（暂无可用分集）";
  }

  return {
    list: [
      {
        vod_id: String(cleanId),
        vod_name: title || ("短剧 " + cleanId),
        vod_pic: cover,
        vod_content: desc,
        vod_remarks: remarks,
        vod_play_from: "官方直链",
        vod_play_url: epUrls.join("#"),
        accessible_count: 0
      }
    ]
  };
}

async function play(flag, id, flags) {
  const target = String(id || '').replace(/^hongguo:/, '');
  if (/^https?:\/\/.+\.(?:mp4|m3u8)(?:[?#]|$)/i.test(target) && !/\/video\/public\//i.test(target)) {
    return { parse: 0, url: target, header: { 'User-Agent': USER_AGENT } };
  }
  return { parse: 0, url: '', header: {}, error: 'MISSING_EPISODE' };
}

var spider = {
  meta: meta,
  init: init,
  home: home,
  category: category,
  detail: detail,
  play: play
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = spider;
}

/*! THL_PORTABLE_APP_BEGIN */
/*! SPDX-License-Identifier: GPL-3.0-only
 * App signing and Spade: jackotom/hongguo-drama 84b6e88, via N3urda/hongguoTV eea73e6 and woshishiq1/drpys 22261ad.
 * THL adaptation: device fetch transport, browser crypto/Buffer, bounded episode recovery.
 * Bundled Buffer, CryptoJS and URL-Parse retain their MIT notices.
 */
var HongguoApp=(()=>{var Xt=(r=>typeof require<"u"?require:typeof Proxy<"u"?new Proxy(r,{get:(e,t)=>(typeof require<"u"?require:e)[t]}):r)(function(r){if(typeof require<"u")return require.apply(this,arguments);throw Error('Dynamic require of "'+r+'" is not supported')});var z=(r,e)=>()=>(e||r((e={exports:{}}).exports,e),e.exports);var Qt=z((bo,Zt)=>{"use strict";Zt.exports=function(e,t){if(t=t.split(":")[0],e=+e,!e)return!1;switch(t){case"http":case"ws":return e!==80;case"https":case"wss":return e!==443;case"ftp":return e!==21;case"gopher":return e!==70;case"file":return!1}return e!==0}});var rr=z(gt=>{"use strict";var On=Object.prototype.hasOwnProperty,Pn;function er(r){try{return decodeURIComponent(r.replace(/\+/g," "))}catch{return null}}function tr(r){try{return encodeURIComponent(r)}catch{return null}}function Mn(r){for(var e=/([^=?#&]+)=?([^&]*)/g,t={},n;n=e.exec(r);){var i=er(n[1]),o=er(n[2]);i===null||o===null||i in t||(t[i]=o)}return t}function zn(r,e){e=e||"";var t=[],n,i;typeof e!="string"&&(e="?");for(i in r)if(On.call(r,i)){if(n=r[i],!n&&(n===null||n===Pn||isNaN(n))&&(n=""),i=tr(i),n=tr(n),i===null||n===null)continue;t.push(i+"="+n)}return t.length?e+t.join("&"):""}gt.stringify=zn;gt.parse=Mn});var ur=z((wo,fr)=>{"use strict";var ir=Qt(),je=rr(),qn=/^[\x00-\x20\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+/,or=/[\n\r\t]/g,jn=/^[A-Za-z][A-Za-z0-9+-.]*:\/\//,ar=/:\d+$/,Vn=/^([a-z][a-z0-9.+-]*:)?(\/\/)?([\\/]+)?([\S\s]*)/i,$n=/^[a-zA-Z]:/;function bt(r){return(r||"").toString().replace(qn,"")}var mt=[["#","hash"],["?","query"],function(e,t){return ie(t.protocol)?e.replace(/\\/g,"/"):e},["/","pathname"],["@","auth",1],[NaN,"host",void 0,1,1],[/:(\d*)$/,"port",void 0,1],[NaN,"hostname",void 0,1,1]],nr={hash:1,query:1};function cr(r){var e;typeof window<"u"?e=window:typeof global<"u"?e=global:typeof self<"u"?e=self:e={};var t=e.location||{};r=r||t;var n={},i=typeof r,o;if(r.protocol==="blob:")n=new oe(unescape(r.pathname),{});else if(i==="string"){n=new oe(r,{});for(o in nr)delete n[o]}else if(i==="object"){for(o in r)o in nr||(n[o]=r[o]);n.slashes===void 0&&(n.slashes=jn.test(r.href))}return n}function ie(r){return r==="file:"||r==="ftp:"||r==="http:"||r==="https:"||r==="ws:"||r==="wss:"}function sr(r,e){r=bt(r),r=r.replace(or,""),e=e||{};var t=Vn.exec(r),n=t[1]?t[1].toLowerCase():"",i=!!t[2],o=!!t[3],a=0,c;return i?o?(c=t[2]+t[3]+t[4],a=t[2].length+t[3].length):(c=t[2]+t[4],a=t[2].length):o?(c=t[3]+t[4],a=t[3].length):c=t[4],n==="file:"?a>=2&&(c=c.slice(2)):ie(n)?c=t[4]:n?i&&(c=c.slice(2)):a>=2&&ie(e.protocol)&&(c=t[4]),{protocol:n,slashes:i||ie(n),slashesCount:a,rest:c}}function Wn(r,e){if(r==="")return e;for(var t=(e||"/").split("/").slice(0,-1).concat(r.split("/")),n=t.length,i=t[n-1],o=!1,a=0;n--;)t[n]==="."?t.splice(n,1):t[n]===".."?(t.splice(n,1),a++):a&&(n===0&&(o=!0),t.splice(n,1),a--);return o&&t.unshift(""),(i==="."||i==="..")&&t.push(""),t.join("/")}function oe(r,e,t){if(r=bt(r),r=r.replace(or,""),!(this instanceof oe))return new oe(r,e,t);var n,i,o,a,c,s,u=mt.slice(),f=typeof e,h=this,d=0;for(f!=="object"&&f!=="string"&&(t=e,e=null),t&&typeof t!="function"&&(t=je.parse),e=cr(e),i=sr(r||"",e),n=!i.protocol&&!i.slashes,h.slashes=i.slashes||n&&e.slashes,h.protocol=i.protocol||e.protocol||"",r=i.rest,(i.protocol==="file:"&&(i.slashesCount!==2||$n.test(r))||!i.slashes&&(i.protocol||i.slashesCount<2||!ie(h.protocol)))&&(u[3]=[/(.*)/,"pathname"]);d<u.length;d++){if(a=u[d],typeof a=="function"){r=a(r,h);continue}o=a[0],s=a[1],o!==o?h[s]=r:typeof o=="string"?(c=o==="@"?r.lastIndexOf(o):r.indexOf(o),~c&&(typeof a[2]=="number"?(h[s]=r.slice(0,c),r=r.slice(c+a[2])):(h[s]=r.slice(c),r=r.slice(0,c)))):(c=o.exec(r))&&(h[s]=c[1],r=r.slice(0,c.index)),h[s]=h[s]||n&&a[3]&&e[s]||"",a[4]&&(h[s]=h[s].toLowerCase())}t&&(h.query=t(h.query)),n&&e.slashes&&h.pathname.charAt(0)!=="/"&&(h.pathname!==""||e.pathname!=="")&&(h.pathname=Wn(h.pathname,e.pathname)),h.pathname.charAt(0)!=="/"&&ie(h.protocol)&&(h.pathname="/"+h.pathname),ir(h.port,h.protocol)||(h.host=h.hostname,h.port=""),h.username=h.password="",h.auth&&(c=h.auth.indexOf(":"),~c?(h.username=h.auth.slice(0,c),h.username=encodeURIComponent(decodeURIComponent(h.username)),h.password=h.auth.slice(c+1),h.password=encodeURIComponent(decodeURIComponent(h.password))):h.username=encodeURIComponent(decodeURIComponent(h.auth)),h.auth=h.password?h.username+":"+h.password:h.username),h.origin=h.protocol!=="file:"&&ie(h.protocol)&&h.host?h.protocol+"//"+h.host:"null",h.href=h.toString()}function Jn(r,e,t){var n=this;switch(r){case"query":typeof e=="string"&&e.length&&(e=(t||je.parse)(e)),n[r]=e;break;case"port":n[r]=e,ir(e,n.protocol)?e&&(n.host=n.hostname+":"+e):(n.host=n.hostname,n[r]="");break;case"hostname":n[r]=e,n.port&&(e+=":"+n.port),n.host=e;break;case"host":n[r]=e,ar.test(e)?(e=e.split(":"),n.port=e.pop(),n.hostname=e.join(":")):(n.hostname=e,n.port="");break;case"protocol":n.protocol=e.toLowerCase(),n.slashes=!t;break;case"pathname":case"hash":if(e){var i=r==="pathname"?"/":"#";n[r]=e.charAt(0)!==i?i+e:e}else n[r]=e;break;case"username":case"password":n[r]=encodeURIComponent(e);break;case"auth":var o=e.indexOf(":");~o?(n.username=e.slice(0,o),n.username=encodeURIComponent(decodeURIComponent(n.username)),n.password=e.slice(o+1),n.password=encodeURIComponent(decodeURIComponent(n.password))):n.username=encodeURIComponent(decodeURIComponent(e))}for(var a=0;a<mt.length;a++){var c=mt[a];c[4]&&(n[c[1]]=n[c[1]].toLowerCase())}return n.auth=n.password?n.username+":"+n.password:n.username,n.origin=n.protocol!=="file:"&&ie(n.protocol)&&n.host?n.protocol+"//"+n.host:"null",n.href=n.toString(),n}function Kn(r){(!r||typeof r!="function")&&(r=je.stringify);var e,t=this,n=t.host,i=t.protocol;i&&i.charAt(i.length-1)!==":"&&(i+=":");var o=i+(t.protocol&&t.slashes||ie(t.protocol)?"//":"");return t.username?(o+=t.username,t.password&&(o+=":"+t.password),o+="@"):t.password?(o+=":"+t.password,o+="@"):t.protocol!=="file:"&&ie(t.protocol)&&!n&&t.pathname!=="/"&&(o+="@"),(n[n.length-1]===":"||ar.test(t.hostname)&&!t.port)&&(n+=":"),o+=n+t.pathname,e=typeof t.query=="object"?r(t.query):t.query,e&&(o+=e.charAt(0)!=="?"?"?"+e:e),t.hash&&(o+=t.hash),o}oe.prototype={set:Jn,toString:Kn};oe.extractProtocol=sr;oe.location=cr;oe.trimLeft=bt;oe.qs=je;fr.exports=oe});var dr=z(Ve=>{"use strict";Ve.byteLength=Yn;Ve.toByteArray=Zn;Ve.fromByteArray=ti;var ae=[],Y=[],Gn=typeof Uint8Array<"u"?Uint8Array:Array,vt="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";for(xe=0,hr=vt.length;xe<hr;++xe)ae[xe]=vt[xe],Y[vt.charCodeAt(xe)]=xe;var xe,hr;Y[45]=62;Y[95]=63;function lr(r){var e=r.length;if(e%4>0)throw new Error("Invalid string. Length must be a multiple of 4");var t=r.indexOf("=");t===-1&&(t=e);var n=t===e?0:4-t%4;return[t,n]}function Yn(r){var e=lr(r),t=e[0],n=e[1];return(t+n)*3/4-n}function Xn(r,e,t){return(e+t)*3/4-t}function Zn(r){var e,t=lr(r),n=t[0],i=t[1],o=new Gn(Xn(r,n,i)),a=0,c=i>0?n-4:n,s;for(s=0;s<c;s+=4)e=Y[r.charCodeAt(s)]<<18|Y[r.charCodeAt(s+1)]<<12|Y[r.charCodeAt(s+2)]<<6|Y[r.charCodeAt(s+3)],o[a++]=e>>16&255,o[a++]=e>>8&255,o[a++]=e&255;return i===2&&(e=Y[r.charCodeAt(s)]<<2|Y[r.charCodeAt(s+1)]>>4,o[a++]=e&255),i===1&&(e=Y[r.charCodeAt(s)]<<10|Y[r.charCodeAt(s+1)]<<4|Y[r.charCodeAt(s+2)]>>2,o[a++]=e>>8&255,o[a++]=e&255),o}function Qn(r){return ae[r>>18&63]+ae[r>>12&63]+ae[r>>6&63]+ae[r&63]}function ei(r,e,t){for(var n,i=[],o=e;o<t;o+=3)n=(r[o]<<16&16711680)+(r[o+1]<<8&65280)+(r[o+2]&255),i.push(Qn(n));return i.join("")}function ti(r){for(var e,t=r.length,n=t%3,i=[],o=16383,a=0,c=t-n;a<c;a+=o)i.push(ei(r,a,a+o>c?c:a+o));return n===1?(e=r[t-1],i.push(ae[e>>2]+ae[e<<4&63]+"==")):n===2&&(e=(r[t-2]<<8)+r[t-1],i.push(ae[e>>10]+ae[e>>4&63]+ae[e<<2&63]+"=")),i.join("")}});var pr=z(wt=>{/*! ieee754. BSD-3-Clause License. Feross Aboukhadijeh <https://feross.org/opensource> */wt.read=function(r,e,t,n,i){var o,a,c=i*8-n-1,s=(1<<c)-1,u=s>>1,f=-7,h=t?i-1:0,d=t?-1:1,x=r[e+h];for(h+=d,o=x&(1<<-f)-1,x>>=-f,f+=c;f>0;o=o*256+r[e+h],h+=d,f-=8);for(a=o&(1<<-f)-1,o>>=-f,f+=n;f>0;a=a*256+r[e+h],h+=d,f-=8);if(o===0)o=1-u;else{if(o===s)return a?NaN:(x?-1:1)*(1/0);a=a+Math.pow(2,n),o=o-u}return(x?-1:1)*a*Math.pow(2,o-n)};wt.write=function(r,e,t,n,i,o){var a,c,s,u=o*8-i-1,f=(1<<u)-1,h=f>>1,d=i===23?Math.pow(2,-24)-Math.pow(2,-77):0,x=n?0:o-1,y=n?1:-1,I=e<0||e===0&&1/e<0?1:0;for(e=Math.abs(e),isNaN(e)||e===1/0?(c=isNaN(e)?1:0,a=f):(a=Math.floor(Math.log(e)/Math.LN2),e*(s=Math.pow(2,-a))<1&&(a--,s*=2),a+h>=1?e+=d/s:e+=d*Math.pow(2,1-h),e*s>=2&&(a++,s/=2),a+h>=f?(c=0,a=f):a+h>=1?(c=(e*s-1)*Math.pow(2,i),a=a+h):(c=e*Math.pow(2,h-1)*Math.pow(2,i),a=0));i>=8;r[t+x]=c&255,x+=y,c/=256,i-=8);for(a=a<<i|c,u+=i;u>0;r[t+x]=a&255,x+=y,a/=256,u-=8);r[t+x-y]|=I*128}});var Je=z(Ie=>{"use strict";/*!
 * The buffer module from node.js, for the browser.
 *
 * @author   Feross Aboukhadijeh <https://feross.org>
 * @license  MIT
 */var _t=dr(),Ee=pr(),xr=typeof Symbol=="function"&&typeof Symbol.for=="function"?Symbol.for("nodejs.util.inspect.custom"):null;Ie.Buffer=m;Ie.SlowBuffer=ci;Ie.INSPECT_MAX_BYTES=50;var $e=2147483647;Ie.kMaxLength=$e;m.TYPED_ARRAY_SUPPORT=ri();!m.TYPED_ARRAY_SUPPORT&&typeof console<"u"&&typeof console.error=="function"&&console.error("This browser lacks typed array (Uint8Array) support which is required by `buffer` v5.x. Use `buffer` v4.x if you require old browser support.");function ri(){try{let r=new Uint8Array(1),e={foo:function(){return 42}};return Object.setPrototypeOf(e,Uint8Array.prototype),Object.setPrototypeOf(r,e),r.foo()===42}catch{return!1}}Object.defineProperty(m.prototype,"parent",{enumerable:!0,get:function(){if(m.isBuffer(this))return this.buffer}});Object.defineProperty(m.prototype,"offset",{enumerable:!0,get:function(){if(m.isBuffer(this))return this.byteOffset}});function ue(r){if(r>$e)throw new RangeError('The value "'+r+'" is invalid for option "size"');let e=new Uint8Array(r);return Object.setPrototypeOf(e,m.prototype),e}function m(r,e,t){if(typeof r=="number"){if(typeof e=="string")throw new TypeError('The "string" argument must be of type string. Received type number');return At(r)}return br(r,e,t)}m.poolSize=8192;function br(r,e,t){if(typeof r=="string")return ii(r,e);if(ArrayBuffer.isView(r))return oi(r);if(r==null)throw new TypeError("The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type "+typeof r);if(ce(r,ArrayBuffer)||r&&ce(r.buffer,ArrayBuffer)||typeof SharedArrayBuffer<"u"&&(ce(r,SharedArrayBuffer)||r&&ce(r.buffer,SharedArrayBuffer)))return Bt(r,e,t);if(typeof r=="number")throw new TypeError('The "value" argument must not be of type number. Received type number');let n=r.valueOf&&r.valueOf();if(n!=null&&n!==r)return m.from(n,e,t);let i=ai(r);if(i)return i;if(typeof Symbol<"u"&&Symbol.toPrimitive!=null&&typeof r[Symbol.toPrimitive]=="function")return m.from(r[Symbol.toPrimitive]("string"),e,t);throw new TypeError("The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type "+typeof r)}m.from=function(r,e,t){return br(r,e,t)};Object.setPrototypeOf(m.prototype,Uint8Array.prototype);Object.setPrototypeOf(m,Uint8Array);function vr(r){if(typeof r!="number")throw new TypeError('"size" argument must be of type number');if(r<0)throw new RangeError('The value "'+r+'" is invalid for option "size"')}function ni(r,e,t){return vr(r),r<=0?ue(r):e!==void 0?typeof t=="string"?ue(r).fill(e,t):ue(r).fill(e):ue(r)}m.alloc=function(r,e,t){return ni(r,e,t)};function At(r){return vr(r),ue(r<0?0:Ct(r)|0)}m.allocUnsafe=function(r){return At(r)};m.allocUnsafeSlow=function(r){return At(r)};function ii(r,e){if((typeof e!="string"||e==="")&&(e="utf8"),!m.isEncoding(e))throw new TypeError("Unknown encoding: "+e);let t=wr(r,e)|0,n=ue(t),i=n.write(r,e);return i!==t&&(n=n.slice(0,i)),n}function Et(r){let e=r.length<0?0:Ct(r.length)|0,t=ue(e);for(let n=0;n<e;n+=1)t[n]=r[n]&255;return t}function oi(r){if(ce(r,Uint8Array)){let e=new Uint8Array(r);return Bt(e.buffer,e.byteOffset,e.byteLength)}return Et(r)}function Bt(r,e,t){if(e<0||r.byteLength<e)throw new RangeError('"offset" is outside of buffer bounds');if(r.byteLength<e+(t||0))throw new RangeError('"length" is outside of buffer bounds');let n;return e===void 0&&t===void 0?n=new Uint8Array(r):t===void 0?n=new Uint8Array(r,e):n=new Uint8Array(r,e,t),Object.setPrototypeOf(n,m.prototype),n}function ai(r){if(m.isBuffer(r)){let e=Ct(r.length)|0,t=ue(e);return t.length===0||r.copy(t,0,0,e),t}if(r.length!==void 0)return typeof r.length!="number"||Ut(r.length)?ue(0):Et(r);if(r.type==="Buffer"&&Array.isArray(r.data))return Et(r.data)}function Ct(r){if(r>=$e)throw new RangeError("Attempt to allocate Buffer larger than maximum size: 0x"+$e.toString(16)+" bytes");return r|0}function ci(r){return+r!=r&&(r=0),m.alloc(+r)}m.isBuffer=function(e){return e!=null&&e._isBuffer===!0&&e!==m.prototype};m.compare=function(e,t){if(ce(e,Uint8Array)&&(e=m.from(e,e.offset,e.byteLength)),ce(t,Uint8Array)&&(t=m.from(t,t.offset,t.byteLength)),!m.isBuffer(e)||!m.isBuffer(t))throw new TypeError('The "buf1", "buf2" arguments must be one of type Buffer or Uint8Array');if(e===t)return 0;let n=e.length,i=t.length;for(let o=0,a=Math.min(n,i);o<a;++o)if(e[o]!==t[o]){n=e[o],i=t[o];break}return n<i?-1:i<n?1:0};m.isEncoding=function(e){switch(String(e).toLowerCase()){case"hex":case"utf8":case"utf-8":case"ascii":case"latin1":case"binary":case"base64":case"ucs2":case"ucs-2":case"utf16le":case"utf-16le":return!0;default:return!1}};m.concat=function(e,t){if(!Array.isArray(e))throw new TypeError('"list" argument must be an Array of Buffers');if(e.length===0)return m.alloc(0);let n;if(t===void 0)for(t=0,n=0;n<e.length;++n)t+=e[n].length;let i=m.allocUnsafe(t),o=0;for(n=0;n<e.length;++n){let a=e[n];if(ce(a,Uint8Array))o+a.length>i.length?(m.isBuffer(a)||(a=m.from(a)),a.copy(i,o)):Uint8Array.prototype.set.call(i,a,o);else if(m.isBuffer(a))a.copy(i,o);else throw new TypeError('"list" argument must be an Array of Buffers');o+=a.length}return i};function wr(r,e){if(m.isBuffer(r))return r.length;if(ArrayBuffer.isView(r)||ce(r,ArrayBuffer))return r.byteLength;if(typeof r!="string")throw new TypeError('The "string" argument must be one of type string, Buffer, or ArrayBuffer. Received type '+typeof r);let t=r.length,n=arguments.length>2&&arguments[2]===!0;if(!n&&t===0)return 0;let i=!1;for(;;)switch(e){case"ascii":case"latin1":case"binary":return t;case"utf8":case"utf-8":return It(r).length;case"ucs2":case"ucs-2":case"utf16le":case"utf-16le":return t*2;case"hex":return t>>>1;case"base64":return Fr(r).length;default:if(i)return n?-1:It(r).length;e=(""+e).toLowerCase(),i=!0}}m.byteLength=wr;function si(r,e,t){let n=!1;if((e===void 0||e<0)&&(e=0),e>this.length||((t===void 0||t>this.length)&&(t=this.length),t<=0)||(t>>>=0,e>>>=0,t<=e))return"";for(r||(r="utf8");;)switch(r){case"hex":return mi(this,e,t);case"utf8":case"utf-8":return Er(this,e,t);case"ascii":return yi(this,e,t);case"latin1":case"binary":return gi(this,e,t);case"base64":return pi(this,e,t);case"ucs2":case"ucs-2":case"utf16le":case"utf-16le":return bi(this,e,t);default:if(n)throw new TypeError("Unknown encoding: "+r);r=(r+"").toLowerCase(),n=!0}}m.prototype._isBuffer=!0;function ye(r,e,t){let n=r[e];r[e]=r[t],r[t]=n}m.prototype.swap16=function(){let e=this.length;if(e%2!==0)throw new RangeError("Buffer size must be a multiple of 16-bits");for(let t=0;t<e;t+=2)ye(this,t,t+1);return this};m.prototype.swap32=function(){let e=this.length;if(e%4!==0)throw new RangeError("Buffer size must be a multiple of 32-bits");for(let t=0;t<e;t+=4)ye(this,t,t+3),ye(this,t+1,t+2);return this};m.prototype.swap64=function(){let e=this.length;if(e%8!==0)throw new RangeError("Buffer size must be a multiple of 64-bits");for(let t=0;t<e;t+=8)ye(this,t,t+7),ye(this,t+1,t+6),ye(this,t+2,t+5),ye(this,t+3,t+4);return this};m.prototype.toString=function(){let e=this.length;return e===0?"":arguments.length===0?Er(this,0,e):si.apply(this,arguments)};m.prototype.toLocaleString=m.prototype.toString;m.prototype.equals=function(e){if(!m.isBuffer(e))throw new TypeError("Argument must be a Buffer");return this===e?!0:m.compare(this,e)===0};m.prototype.inspect=function(){let e="",t=Ie.INSPECT_MAX_BYTES;return e=this.toString("hex",0,t).replace(/(.{2})/g,"$1 ").trim(),this.length>t&&(e+=" ... "),"<Buffer "+e+">"};xr&&(m.prototype[xr]=m.prototype.inspect);m.prototype.compare=function(e,t,n,i,o){if(ce(e,Uint8Array)&&(e=m.from(e,e.offset,e.byteLength)),!m.isBuffer(e))throw new TypeError('The "target" argument must be one of type Buffer or Uint8Array. Received type '+typeof e);if(t===void 0&&(t=0),n===void 0&&(n=e?e.length:0),i===void 0&&(i=0),o===void 0&&(o=this.length),t<0||n>e.length||i<0||o>this.length)throw new RangeError("out of range index");if(i>=o&&t>=n)return 0;if(i>=o)return-1;if(t>=n)return 1;if(t>>>=0,n>>>=0,i>>>=0,o>>>=0,this===e)return 0;let a=o-i,c=n-t,s=Math.min(a,c),u=this.slice(i,o),f=e.slice(t,n);for(let h=0;h<s;++h)if(u[h]!==f[h]){a=u[h],c=f[h];break}return a<c?-1:c<a?1:0};function _r(r,e,t,n,i){if(r.length===0)return-1;if(typeof t=="string"?(n=t,t=0):t>2147483647?t=2147483647:t<-2147483648&&(t=-2147483648),t=+t,Ut(t)&&(t=i?0:r.length-1),t<0&&(t=r.length+t),t>=r.length){if(i)return-1;t=r.length-1}else if(t<0)if(i)t=0;else return-1;if(typeof e=="string"&&(e=m.from(e,n)),m.isBuffer(e))return e.length===0?-1:yr(r,e,t,n,i);if(typeof e=="number")return e=e&255,typeof Uint8Array.prototype.indexOf=="function"?i?Uint8Array.prototype.indexOf.call(r,e,t):Uint8Array.prototype.lastIndexOf.call(r,e,t):yr(r,[e],t,n,i);throw new TypeError("val must be string, number or Buffer")}function yr(r,e,t,n,i){let o=1,a=r.length,c=e.length;if(n!==void 0&&(n=String(n).toLowerCase(),n==="ucs2"||n==="ucs-2"||n==="utf16le"||n==="utf-16le")){if(r.length<2||e.length<2)return-1;o=2,a/=2,c/=2,t/=2}function s(f,h){return o===1?f[h]:f.readUInt16BE(h*o)}let u;if(i){let f=-1;for(u=t;u<a;u++)if(s(r,u)===s(e,f===-1?0:u-f)){if(f===-1&&(f=u),u-f+1===c)return f*o}else f!==-1&&(u-=u-f),f=-1}else for(t+c>a&&(t=a-c),u=t;u>=0;u--){let f=!0;for(let h=0;h<c;h++)if(s(r,u+h)!==s(e,h)){f=!1;break}if(f)return u}return-1}m.prototype.includes=function(e,t,n){return this.indexOf(e,t,n)!==-1};m.prototype.indexOf=function(e,t,n){return _r(this,e,t,n,!0)};m.prototype.lastIndexOf=function(e,t,n){return _r(this,e,t,n,!1)};function fi(r,e,t,n){t=Number(t)||0;let i=r.length-t;n?(n=Number(n),n>i&&(n=i)):n=i;let o=e.length;n>o/2&&(n=o/2);let a;for(a=0;a<n;++a){let c=parseInt(e.substr(a*2,2),16);if(Ut(c))return a;r[t+a]=c}return a}function ui(r,e,t,n){return We(It(e,r.length-t),r,t,n)}function hi(r,e,t,n){return We(Ei(e),r,t,n)}function li(r,e,t,n){return We(Fr(e),r,t,n)}function di(r,e,t,n){return We(Bi(e,r.length-t),r,t,n)}m.prototype.write=function(e,t,n,i){if(t===void 0)i="utf8",n=this.length,t=0;else if(n===void 0&&typeof t=="string")i=t,n=this.length,t=0;else if(isFinite(t))t=t>>>0,isFinite(n)?(n=n>>>0,i===void 0&&(i="utf8")):(i=n,n=void 0);else throw new Error("Buffer.write(string, encoding, offset[, length]) is no longer supported");let o=this.length-t;if((n===void 0||n>o)&&(n=o),e.length>0&&(n<0||t<0)||t>this.length)throw new RangeError("Attempt to write outside buffer bounds");i||(i="utf8");let a=!1;for(;;)switch(i){case"hex":return fi(this,e,t,n);case"utf8":case"utf-8":return ui(this,e,t,n);case"ascii":case"latin1":case"binary":return hi(this,e,t,n);case"base64":return li(this,e,t,n);case"ucs2":case"ucs-2":case"utf16le":case"utf-16le":return di(this,e,t,n);default:if(a)throw new TypeError("Unknown encoding: "+i);i=(""+i).toLowerCase(),a=!0}};m.prototype.toJSON=function(){return{type:"Buffer",data:Array.prototype.slice.call(this._arr||this,0)}};function pi(r,e,t){return e===0&&t===r.length?_t.fromByteArray(r):_t.fromByteArray(r.slice(e,t))}function Er(r,e,t){t=Math.min(r.length,t);let n=[],i=e;for(;i<t;){let o=r[i],a=null,c=o>239?4:o>223?3:o>191?2:1;if(i+c<=t){let s,u,f,h;switch(c){case 1:o<128&&(a=o);break;case 2:s=r[i+1],(s&192)===128&&(h=(o&31)<<6|s&63,h>127&&(a=h));break;case 3:s=r[i+1],u=r[i+2],(s&192)===128&&(u&192)===128&&(h=(o&15)<<12|(s&63)<<6|u&63,h>2047&&(h<55296||h>57343)&&(a=h));break;case 4:s=r[i+1],u=r[i+2],f=r[i+3],(s&192)===128&&(u&192)===128&&(f&192)===128&&(h=(o&15)<<18|(s&63)<<12|(u&63)<<6|f&63,h>65535&&h<1114112&&(a=h))}}a===null?(a=65533,c=1):a>65535&&(a-=65536,n.push(a>>>10&1023|55296),a=56320|a&1023),n.push(a),i+=c}return xi(n)}var gr=4096;function xi(r){let e=r.length;if(e<=gr)return String.fromCharCode.apply(String,r);let t="",n=0;for(;n<e;)t+=String.fromCharCode.apply(String,r.slice(n,n+=gr));return t}function yi(r,e,t){let n="";t=Math.min(r.length,t);for(let i=e;i<t;++i)n+=String.fromCharCode(r[i]&127);return n}function gi(r,e,t){let n="";t=Math.min(r.length,t);for(let i=e;i<t;++i)n+=String.fromCharCode(r[i]);return n}function mi(r,e,t){let n=r.length;(!e||e<0)&&(e=0),(!t||t<0||t>n)&&(t=n);let i="";for(let o=e;o<t;++o)i+=Ii[r[o]];return i}function bi(r,e,t){let n=r.slice(e,t),i="";for(let o=0;o<n.length-1;o+=2)i+=String.fromCharCode(n[o]+n[o+1]*256);return i}m.prototype.slice=function(e,t){let n=this.length;e=~~e,t=t===void 0?n:~~t,e<0?(e+=n,e<0&&(e=0)):e>n&&(e=n),t<0?(t+=n,t<0&&(t=0)):t>n&&(t=n),t<e&&(t=e);let i=this.subarray(e,t);return Object.setPrototypeOf(i,m.prototype),i};function j(r,e,t){if(r%1!==0||r<0)throw new RangeError("offset is not uint");if(r+e>t)throw new RangeError("Trying to access beyond buffer length")}m.prototype.readUintLE=m.prototype.readUIntLE=function(e,t,n){e=e>>>0,t=t>>>0,n||j(e,t,this.length);let i=this[e],o=1,a=0;for(;++a<t&&(o*=256);)i+=this[e+a]*o;return i};m.prototype.readUintBE=m.prototype.readUIntBE=function(e,t,n){e=e>>>0,t=t>>>0,n||j(e,t,this.length);let i=this[e+--t],o=1;for(;t>0&&(o*=256);)i+=this[e+--t]*o;return i};m.prototype.readUint8=m.prototype.readUInt8=function(e,t){return e=e>>>0,t||j(e,1,this.length),this[e]};m.prototype.readUint16LE=m.prototype.readUInt16LE=function(e,t){return e=e>>>0,t||j(e,2,this.length),this[e]|this[e+1]<<8};m.prototype.readUint16BE=m.prototype.readUInt16BE=function(e,t){return e=e>>>0,t||j(e,2,this.length),this[e]<<8|this[e+1]};m.prototype.readUint32LE=m.prototype.readUInt32LE=function(e,t){return e=e>>>0,t||j(e,4,this.length),(this[e]|this[e+1]<<8|this[e+2]<<16)+this[e+3]*16777216};m.prototype.readUint32BE=m.prototype.readUInt32BE=function(e,t){return e=e>>>0,t||j(e,4,this.length),this[e]*16777216+(this[e+1]<<16|this[e+2]<<8|this[e+3])};m.prototype.readBigUInt64LE=pe(function(e){e=e>>>0,Be(e,"offset");let t=this[e],n=this[e+7];(t===void 0||n===void 0)&&Le(e,this.length-8);let i=t+this[++e]*2**8+this[++e]*2**16+this[++e]*2**24,o=this[++e]+this[++e]*2**8+this[++e]*2**16+n*2**24;return BigInt(i)+(BigInt(o)<<BigInt(32))});m.prototype.readBigUInt64BE=pe(function(e){e=e>>>0,Be(e,"offset");let t=this[e],n=this[e+7];(t===void 0||n===void 0)&&Le(e,this.length-8);let i=t*2**24+this[++e]*2**16+this[++e]*2**8+this[++e],o=this[++e]*2**24+this[++e]*2**16+this[++e]*2**8+n;return(BigInt(i)<<BigInt(32))+BigInt(o)});m.prototype.readIntLE=function(e,t,n){e=e>>>0,t=t>>>0,n||j(e,t,this.length);let i=this[e],o=1,a=0;for(;++a<t&&(o*=256);)i+=this[e+a]*o;return o*=128,i>=o&&(i-=Math.pow(2,8*t)),i};m.prototype.readIntBE=function(e,t,n){e=e>>>0,t=t>>>0,n||j(e,t,this.length);let i=t,o=1,a=this[e+--i];for(;i>0&&(o*=256);)a+=this[e+--i]*o;return o*=128,a>=o&&(a-=Math.pow(2,8*t)),a};m.prototype.readInt8=function(e,t){return e=e>>>0,t||j(e,1,this.length),this[e]&128?(255-this[e]+1)*-1:this[e]};m.prototype.readInt16LE=function(e,t){e=e>>>0,t||j(e,2,this.length);let n=this[e]|this[e+1]<<8;return n&32768?n|4294901760:n};m.prototype.readInt16BE=function(e,t){e=e>>>0,t||j(e,2,this.length);let n=this[e+1]|this[e]<<8;return n&32768?n|4294901760:n};m.prototype.readInt32LE=function(e,t){return e=e>>>0,t||j(e,4,this.length),this[e]|this[e+1]<<8|this[e+2]<<16|this[e+3]<<24};m.prototype.readInt32BE=function(e,t){return e=e>>>0,t||j(e,4,this.length),this[e]<<24|this[e+1]<<16|this[e+2]<<8|this[e+3]};m.prototype.readBigInt64LE=pe(function(e){e=e>>>0,Be(e,"offset");let t=this[e],n=this[e+7];(t===void 0||n===void 0)&&Le(e,this.length-8);let i=this[e+4]+this[e+5]*2**8+this[e+6]*2**16+(n<<24);return(BigInt(i)<<BigInt(32))+BigInt(t+this[++e]*2**8+this[++e]*2**16+this[++e]*2**24)});m.prototype.readBigInt64BE=pe(function(e){e=e>>>0,Be(e,"offset");let t=this[e],n=this[e+7];(t===void 0||n===void 0)&&Le(e,this.length-8);let i=(t<<24)+this[++e]*2**16+this[++e]*2**8+this[++e];return(BigInt(i)<<BigInt(32))+BigInt(this[++e]*2**24+this[++e]*2**16+this[++e]*2**8+n)});m.prototype.readFloatLE=function(e,t){return e=e>>>0,t||j(e,4,this.length),Ee.read(this,e,!0,23,4)};m.prototype.readFloatBE=function(e,t){return e=e>>>0,t||j(e,4,this.length),Ee.read(this,e,!1,23,4)};m.prototype.readDoubleLE=function(e,t){return e=e>>>0,t||j(e,8,this.length),Ee.read(this,e,!0,52,8)};m.prototype.readDoubleBE=function(e,t){return e=e>>>0,t||j(e,8,this.length),Ee.read(this,e,!1,52,8)};function V(r,e,t,n,i,o){if(!m.isBuffer(r))throw new TypeError('"buffer" argument must be a Buffer instance');if(e>i||e<o)throw new RangeError('"value" argument is out of bounds');if(t+n>r.length)throw new RangeError("Index out of range")}m.prototype.writeUintLE=m.prototype.writeUIntLE=function(e,t,n,i){if(e=+e,t=t>>>0,n=n>>>0,!i){let c=Math.pow(2,8*n)-1;V(this,e,t,n,c,0)}let o=1,a=0;for(this[t]=e&255;++a<n&&(o*=256);)this[t+a]=e/o&255;return t+n};m.prototype.writeUintBE=m.prototype.writeUIntBE=function(e,t,n,i){if(e=+e,t=t>>>0,n=n>>>0,!i){let c=Math.pow(2,8*n)-1;V(this,e,t,n,c,0)}let o=n-1,a=1;for(this[t+o]=e&255;--o>=0&&(a*=256);)this[t+o]=e/a&255;return t+n};m.prototype.writeUint8=m.prototype.writeUInt8=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,1,255,0),this[t]=e&255,t+1};m.prototype.writeUint16LE=m.prototype.writeUInt16LE=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,2,65535,0),this[t]=e&255,this[t+1]=e>>>8,t+2};m.prototype.writeUint16BE=m.prototype.writeUInt16BE=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,2,65535,0),this[t]=e>>>8,this[t+1]=e&255,t+2};m.prototype.writeUint32LE=m.prototype.writeUInt32LE=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,4,4294967295,0),this[t+3]=e>>>24,this[t+2]=e>>>16,this[t+1]=e>>>8,this[t]=e&255,t+4};m.prototype.writeUint32BE=m.prototype.writeUInt32BE=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,4,4294967295,0),this[t]=e>>>24,this[t+1]=e>>>16,this[t+2]=e>>>8,this[t+3]=e&255,t+4};function Br(r,e,t,n,i){Ur(e,n,i,r,t,7);let o=Number(e&BigInt(4294967295));r[t++]=o,o=o>>8,r[t++]=o,o=o>>8,r[t++]=o,o=o>>8,r[t++]=o;let a=Number(e>>BigInt(32)&BigInt(4294967295));return r[t++]=a,a=a>>8,r[t++]=a,a=a>>8,r[t++]=a,a=a>>8,r[t++]=a,t}function Ir(r,e,t,n,i){Ur(e,n,i,r,t,7);let o=Number(e&BigInt(4294967295));r[t+7]=o,o=o>>8,r[t+6]=o,o=o>>8,r[t+5]=o,o=o>>8,r[t+4]=o;let a=Number(e>>BigInt(32)&BigInt(4294967295));return r[t+3]=a,a=a>>8,r[t+2]=a,a=a>>8,r[t+1]=a,a=a>>8,r[t]=a,t+8}m.prototype.writeBigUInt64LE=pe(function(e,t=0){return Br(this,e,t,BigInt(0),BigInt("0xffffffffffffffff"))});m.prototype.writeBigUInt64BE=pe(function(e,t=0){return Ir(this,e,t,BigInt(0),BigInt("0xffffffffffffffff"))});m.prototype.writeIntLE=function(e,t,n,i){if(e=+e,t=t>>>0,!i){let s=Math.pow(2,8*n-1);V(this,e,t,n,s-1,-s)}let o=0,a=1,c=0;for(this[t]=e&255;++o<n&&(a*=256);)e<0&&c===0&&this[t+o-1]!==0&&(c=1),this[t+o]=(e/a>>0)-c&255;return t+n};m.prototype.writeIntBE=function(e,t,n,i){if(e=+e,t=t>>>0,!i){let s=Math.pow(2,8*n-1);V(this,e,t,n,s-1,-s)}let o=n-1,a=1,c=0;for(this[t+o]=e&255;--o>=0&&(a*=256);)e<0&&c===0&&this[t+o+1]!==0&&(c=1),this[t+o]=(e/a>>0)-c&255;return t+n};m.prototype.writeInt8=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,1,127,-128),e<0&&(e=255+e+1),this[t]=e&255,t+1};m.prototype.writeInt16LE=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,2,32767,-32768),this[t]=e&255,this[t+1]=e>>>8,t+2};m.prototype.writeInt16BE=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,2,32767,-32768),this[t]=e>>>8,this[t+1]=e&255,t+2};m.prototype.writeInt32LE=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,4,2147483647,-2147483648),this[t]=e&255,this[t+1]=e>>>8,this[t+2]=e>>>16,this[t+3]=e>>>24,t+4};m.prototype.writeInt32BE=function(e,t,n){return e=+e,t=t>>>0,n||V(this,e,t,4,2147483647,-2147483648),e<0&&(e=4294967295+e+1),this[t]=e>>>24,this[t+1]=e>>>16,this[t+2]=e>>>8,this[t+3]=e&255,t+4};m.prototype.writeBigInt64LE=pe(function(e,t=0){return Br(this,e,t,-BigInt("0x8000000000000000"),BigInt("0x7fffffffffffffff"))});m.prototype.writeBigInt64BE=pe(function(e,t=0){return Ir(this,e,t,-BigInt("0x8000000000000000"),BigInt("0x7fffffffffffffff"))});function Ar(r,e,t,n,i,o){if(t+n>r.length)throw new RangeError("Index out of range");if(t<0)throw new RangeError("Index out of range")}function Cr(r,e,t,n,i){return e=+e,t=t>>>0,i||Ar(r,e,t,4,34028234663852886e22,-34028234663852886e22),Ee.write(r,e,t,n,23,4),t+4}m.prototype.writeFloatLE=function(e,t,n){return Cr(this,e,t,!0,n)};m.prototype.writeFloatBE=function(e,t,n){return Cr(this,e,t,!1,n)};function Sr(r,e,t,n,i){return e=+e,t=t>>>0,i||Ar(r,e,t,8,17976931348623157e292,-17976931348623157e292),Ee.write(r,e,t,n,52,8),t+8}m.prototype.writeDoubleLE=function(e,t,n){return Sr(this,e,t,!0,n)};m.prototype.writeDoubleBE=function(e,t,n){return Sr(this,e,t,!1,n)};m.prototype.copy=function(e,t,n,i){if(!m.isBuffer(e))throw new TypeError("argument should be a Buffer");if(n||(n=0),!i&&i!==0&&(i=this.length),t>=e.length&&(t=e.length),t||(t=0),i>0&&i<n&&(i=n),i===n||e.length===0||this.length===0)return 0;if(t<0)throw new RangeError("targetStart out of bounds");if(n<0||n>=this.length)throw new RangeError("Index out of range");if(i<0)throw new RangeError("sourceEnd out of bounds");i>this.length&&(i=this.length),e.length-t<i-n&&(i=e.length-t+n);let o=i-n;return this===e&&typeof Uint8Array.prototype.copyWithin=="function"?this.copyWithin(t,n,i):Uint8Array.prototype.set.call(e,this.subarray(n,i),t),o};m.prototype.fill=function(e,t,n,i){if(typeof e=="string"){if(typeof t=="string"?(i=t,t=0,n=this.length):typeof n=="string"&&(i=n,n=this.length),i!==void 0&&typeof i!="string")throw new TypeError("encoding must be a string");if(typeof i=="string"&&!m.isEncoding(i))throw new TypeError("Unknown encoding: "+i);if(e.length===1){let a=e.charCodeAt(0);(i==="utf8"&&a<128||i==="latin1")&&(e=a)}}else typeof e=="number"?e=e&255:typeof e=="boolean"&&(e=Number(e));if(t<0||this.length<t||this.length<n)throw new RangeError("Out of range index");if(n<=t)return this;t=t>>>0,n=n===void 0?this.length:n>>>0,e||(e=0);let o;if(typeof e=="number")for(o=t;o<n;++o)this[o]=e;else{let a=m.isBuffer(e)?e:m.from(e,i),c=a.length;if(c===0)throw new TypeError('The value "'+e+'" is invalid for argument "value"');for(o=0;o<n-t;++o)this[o+t]=a[o%c]}return this};var _e={};function St(r,e,t){_e[r]=class extends t{constructor(){super(),Object.defineProperty(this,"message",{value:e.apply(this,arguments),writable:!0,configurable:!0}),this.name=`${this.name} [${r}]`,this.stack,delete this.name}get code(){return r}set code(i){Object.defineProperty(this,"code",{configurable:!0,enumerable:!0,value:i,writable:!0})}toString(){return`${this.name} [${r}]: ${this.message}`}}}St("ERR_BUFFER_OUT_OF_BOUNDS",function(r){return r?`${r} is outside of buffer bounds`:"Attempt to access memory outside buffer bounds"},RangeError);St("ERR_INVALID_ARG_TYPE",function(r,e){return`The "${r}" argument must be of type number. Received type ${typeof e}`},TypeError);St("ERR_OUT_OF_RANGE",function(r,e,t){let n=`The value of "${r}" is out of range.`,i=t;return Number.isInteger(t)&&Math.abs(t)>2**32?i=mr(String(t)):typeof t=="bigint"&&(i=String(t),(t>BigInt(2)**BigInt(32)||t<-(BigInt(2)**BigInt(32)))&&(i=mr(i)),i+="n"),n+=` It must be ${e}. Received ${i}`,n},RangeError);function mr(r){let e="",t=r.length,n=r[0]==="-"?1:0;for(;t>=n+4;t-=3)e=`_${r.slice(t-3,t)}${e}`;return`${r.slice(0,t)}${e}`}function vi(r,e,t){Be(e,"offset"),(r[e]===void 0||r[e+t]===void 0)&&Le(e,r.length-(t+1))}function Ur(r,e,t,n,i,o){if(r>t||r<e){let a=typeof e=="bigint"?"n":"",c;throw o>3?e===0||e===BigInt(0)?c=`>= 0${a} and < 2${a} ** ${(o+1)*8}${a}`:c=`>= -(2${a} ** ${(o+1)*8-1}${a}) and < 2 ** ${(o+1)*8-1}${a}`:c=`>= ${e}${a} and <= ${t}${a}`,new _e.ERR_OUT_OF_RANGE("value",c,r)}vi(n,i,o)}function Be(r,e){if(typeof r!="number")throw new _e.ERR_INVALID_ARG_TYPE(e,"number",r)}function Le(r,e,t){throw Math.floor(r)!==r?(Be(r,t),new _e.ERR_OUT_OF_RANGE(t||"offset","an integer",r)):e<0?new _e.ERR_BUFFER_OUT_OF_BOUNDS:new _e.ERR_OUT_OF_RANGE(t||"offset",`>= ${t?1:0} and <= ${e}`,r)}var wi=/[^+/0-9A-Za-z-_]/g;function _i(r){if(r=r.split("=")[0],r=r.trim().replace(wi,""),r.length<2)return"";for(;r.length%4!==0;)r=r+"=";return r}function It(r,e){e=e||1/0;let t,n=r.length,i=null,o=[];for(let a=0;a<n;++a){if(t=r.charCodeAt(a),t>55295&&t<57344){if(!i){if(t>56319){(e-=3)>-1&&o.push(239,191,189);continue}else if(a+1===n){(e-=3)>-1&&o.push(239,191,189);continue}i=t;continue}if(t<56320){(e-=3)>-1&&o.push(239,191,189),i=t;continue}t=(i-55296<<10|t-56320)+65536}else i&&(e-=3)>-1&&o.push(239,191,189);if(i=null,t<128){if((e-=1)<0)break;o.push(t)}else if(t<2048){if((e-=2)<0)break;o.push(t>>6|192,t&63|128)}else if(t<65536){if((e-=3)<0)break;o.push(t>>12|224,t>>6&63|128,t&63|128)}else if(t<1114112){if((e-=4)<0)break;o.push(t>>18|240,t>>12&63|128,t>>6&63|128,t&63|128)}else throw new Error("Invalid code point")}return o}function Ei(r){let e=[];for(let t=0;t<r.length;++t)e.push(r.charCodeAt(t)&255);return e}function Bi(r,e){let t,n,i,o=[];for(let a=0;a<r.length&&!((e-=2)<0);++a)t=r.charCodeAt(a),n=t>>8,i=t%256,o.push(i),o.push(n);return o}function Fr(r){return _t.toByteArray(_i(r))}function We(r,e,t,n){let i;for(i=0;i<n&&!(i+t>=e.length||i>=r.length);++i)e[i+t]=r[i];return i}function ce(r,e){return r instanceof e||r!=null&&r.constructor!=null&&r.constructor.name!=null&&r.constructor.name===e.name}function Ut(r){return r!==r}var Ii=(function(){let r="0123456789abcdef",e=new Array(256);for(let t=0;t<16;++t){let n=t*16;for(let i=0;i<16;++i)e[n+i]=r[t]+r[i]}return e})();function pe(r){return typeof BigInt>"u"?Ai:r}function Ai(){throw new Error("BigInt not supported")}});var kr=z(()=>{});var X=z((Ke,Rr)=>{(function(r,e){typeof Ke=="object"?Rr.exports=Ke=e():typeof define=="function"&&define.amd?define([],e):r.CryptoJS=e()})(Ke,function(){var r=r||(function(e,t){var n;if(typeof window<"u"&&window.crypto&&(n=window.crypto),typeof self<"u"&&self.crypto&&(n=self.crypto),typeof globalThis<"u"&&globalThis.crypto&&(n=globalThis.crypto),!n&&typeof window<"u"&&window.msCrypto&&(n=window.msCrypto),!n&&typeof global<"u"&&global.crypto&&(n=global.crypto),!n&&typeof Xt=="function")try{n=kr()}catch{}var i=function(){if(n){if(typeof n.getRandomValues=="function")try{return n.getRandomValues(new Uint32Array(1))[0]}catch{}if(typeof n.randomBytes=="function")try{return n.randomBytes(4).readInt32LE()}catch{}}throw new Error("Native crypto module could not be used to get secure random number.")},o=Object.create||(function(){function l(){}return function(p){var g;return l.prototype=p,g=new l,l.prototype=null,g}})(),a={},c=a.lib={},s=c.Base=(function(){return{extend:function(l){var p=o(this);return l&&p.mixIn(l),(!p.hasOwnProperty("init")||this.init===p.init)&&(p.init=function(){p.$super.init.apply(this,arguments)}),p.init.prototype=p,p.$super=this,p},create:function(){var l=this.extend();return l.init.apply(l,arguments),l},init:function(){},mixIn:function(l){for(var p in l)l.hasOwnProperty(p)&&(this[p]=l[p]);l.hasOwnProperty("toString")&&(this.toString=l.toString)},clone:function(){return this.init.prototype.extend(this)}}})(),u=c.WordArray=s.extend({init:function(l,p){l=this.words=l||[],p!=t?this.sigBytes=p:this.sigBytes=l.length*4},toString:function(l){return(l||h).stringify(this)},concat:function(l){var p=this.words,g=l.words,v=this.sigBytes,U=l.sigBytes;if(this.clamp(),v%4)for(var R=0;R<U;R++){var L=g[R>>>2]>>>24-R%4*8&255;p[v+R>>>2]|=L<<24-(v+R)%4*8}else for(var N=0;N<U;N+=4)p[v+N>>>2]=g[N>>>2];return this.sigBytes+=U,this},clamp:function(){var l=this.words,p=this.sigBytes;l[p>>>2]&=4294967295<<32-p%4*8,l.length=e.ceil(p/4)},clone:function(){var l=s.clone.call(this);return l.words=this.words.slice(0),l},random:function(l){for(var p=[],g=0;g<l;g+=4)p.push(i());return new u.init(p,l)}}),f=a.enc={},h=f.Hex={stringify:function(l){for(var p=l.words,g=l.sigBytes,v=[],U=0;U<g;U++){var R=p[U>>>2]>>>24-U%4*8&255;v.push((R>>>4).toString(16)),v.push((R&15).toString(16))}return v.join("")},parse:function(l){for(var p=l.length,g=[],v=0;v<p;v+=2)g[v>>>3]|=parseInt(l.substr(v,2),16)<<24-v%8*4;return new u.init(g,p/2)}},d=f.Latin1={stringify:function(l){for(var p=l.words,g=l.sigBytes,v=[],U=0;U<g;U++){var R=p[U>>>2]>>>24-U%4*8&255;v.push(String.fromCharCode(R))}return v.join("")},parse:function(l){for(var p=l.length,g=[],v=0;v<p;v++)g[v>>>2]|=(l.charCodeAt(v)&255)<<24-v%4*8;return new u.init(g,p)}},x=f.Utf8={stringify:function(l){try{return decodeURIComponent(escape(d.stringify(l)))}catch{throw new Error("Malformed UTF-8 data")}},parse:function(l){return d.parse(unescape(encodeURIComponent(l)))}},y=c.BufferedBlockAlgorithm=s.extend({reset:function(){this._data=new u.init,this._nDataBytes=0},_append:function(l){typeof l=="string"&&(l=x.parse(l)),this._data.concat(l),this._nDataBytes+=l.sigBytes},_process:function(l){var p,g=this._data,v=g.words,U=g.sigBytes,R=this.blockSize,L=R*4,N=U/L;l?N=e.ceil(N):N=e.max((N|0)-this._minBufferSize,0);var k=N*R,T=e.min(k*4,U);if(k){for(var b=0;b<k;b+=R)this._doProcessBlock(v,b);p=v.splice(0,k),g.sigBytes-=T}return new u.init(p,T)},clone:function(){var l=s.clone.call(this);return l._data=this._data.clone(),l},_minBufferSize:0}),I=c.Hasher=y.extend({cfg:s.extend(),init:function(l){this.cfg=this.cfg.extend(l),this.reset()},reset:function(){y.reset.call(this),this._doReset()},update:function(l){return this._append(l),this._process(),this},finalize:function(l){l&&this._append(l);var p=this._doFinalize();return p},blockSize:512/32,_createHelper:function(l){return function(p,g){return new l.init(g).finalize(p)}},_createHmacHelper:function(l){return function(p,g){return new F.HMAC.init(l,g).finalize(p)}}}),F=a.algo={};return a})(Math);return r})});var Ft=z((Ge,Dr)=>{(function(r,e){typeof Ge=="object"?Dr.exports=Ge=e(X()):typeof define=="function"&&define.amd?define(["./core"],e):e(r.CryptoJS)})(Ge,function(r){return(function(e){var t=r,n=t.lib,i=n.WordArray,o=n.Hasher,a=t.algo,c=[];(function(){for(var x=0;x<64;x++)c[x]=e.abs(e.sin(x+1))*4294967296|0})();var s=a.MD5=o.extend({_doReset:function(){this._hash=new i.init([1732584193,4023233417,2562383102,271733878])},_doProcessBlock:function(x,y){for(var I=0;I<16;I++){var F=y+I,l=x[F];x[F]=(l<<8|l>>>24)&16711935|(l<<24|l>>>8)&4278255360}var p=this._hash.words,g=x[y+0],v=x[y+1],U=x[y+2],R=x[y+3],L=x[y+4],N=x[y+5],k=x[y+6],T=x[y+7],b=x[y+8],A=x[y+9],D=x[y+10],w=x[y+11],H=x[y+12],O=x[y+13],P=x[y+14],q=x[y+15],_=p[0],E=p[1],C=p[2],B=p[3];_=u(_,E,C,B,g,7,c[0]),B=u(B,_,E,C,v,12,c[1]),C=u(C,B,_,E,U,17,c[2]),E=u(E,C,B,_,R,22,c[3]),_=u(_,E,C,B,L,7,c[4]),B=u(B,_,E,C,N,12,c[5]),C=u(C,B,_,E,k,17,c[6]),E=u(E,C,B,_,T,22,c[7]),_=u(_,E,C,B,b,7,c[8]),B=u(B,_,E,C,A,12,c[9]),C=u(C,B,_,E,D,17,c[10]),E=u(E,C,B,_,w,22,c[11]),_=u(_,E,C,B,H,7,c[12]),B=u(B,_,E,C,O,12,c[13]),C=u(C,B,_,E,P,17,c[14]),E=u(E,C,B,_,q,22,c[15]),_=f(_,E,C,B,v,5,c[16]),B=f(B,_,E,C,k,9,c[17]),C=f(C,B,_,E,w,14,c[18]),E=f(E,C,B,_,g,20,c[19]),_=f(_,E,C,B,N,5,c[20]),B=f(B,_,E,C,D,9,c[21]),C=f(C,B,_,E,q,14,c[22]),E=f(E,C,B,_,L,20,c[23]),_=f(_,E,C,B,A,5,c[24]),B=f(B,_,E,C,P,9,c[25]),C=f(C,B,_,E,R,14,c[26]),E=f(E,C,B,_,b,20,c[27]),_=f(_,E,C,B,O,5,c[28]),B=f(B,_,E,C,U,9,c[29]),C=f(C,B,_,E,T,14,c[30]),E=f(E,C,B,_,H,20,c[31]),_=h(_,E,C,B,N,4,c[32]),B=h(B,_,E,C,b,11,c[33]),C=h(C,B,_,E,w,16,c[34]),E=h(E,C,B,_,P,23,c[35]),_=h(_,E,C,B,v,4,c[36]),B=h(B,_,E,C,L,11,c[37]),C=h(C,B,_,E,T,16,c[38]),E=h(E,C,B,_,D,23,c[39]),_=h(_,E,C,B,O,4,c[40]),B=h(B,_,E,C,g,11,c[41]),C=h(C,B,_,E,R,16,c[42]),E=h(E,C,B,_,k,23,c[43]),_=h(_,E,C,B,A,4,c[44]),B=h(B,_,E,C,H,11,c[45]),C=h(C,B,_,E,q,16,c[46]),E=h(E,C,B,_,U,23,c[47]),_=d(_,E,C,B,g,6,c[48]),B=d(B,_,E,C,T,10,c[49]),C=d(C,B,_,E,P,15,c[50]),E=d(E,C,B,_,N,21,c[51]),_=d(_,E,C,B,H,6,c[52]),B=d(B,_,E,C,R,10,c[53]),C=d(C,B,_,E,D,15,c[54]),E=d(E,C,B,_,v,21,c[55]),_=d(_,E,C,B,b,6,c[56]),B=d(B,_,E,C,q,10,c[57]),C=d(C,B,_,E,k,15,c[58]),E=d(E,C,B,_,O,21,c[59]),_=d(_,E,C,B,L,6,c[60]),B=d(B,_,E,C,w,10,c[61]),C=d(C,B,_,E,U,15,c[62]),E=d(E,C,B,_,A,21,c[63]),p[0]=p[0]+_|0,p[1]=p[1]+E|0,p[2]=p[2]+C|0,p[3]=p[3]+B|0},_doFinalize:function(){var x=this._data,y=x.words,I=this._nDataBytes*8,F=x.sigBytes*8;y[F>>>5]|=128<<24-F%32;var l=e.floor(I/4294967296),p=I;y[(F+64>>>9<<4)+15]=(l<<8|l>>>24)&16711935|(l<<24|l>>>8)&4278255360,y[(F+64>>>9<<4)+14]=(p<<8|p>>>24)&16711935|(p<<24|p>>>8)&4278255360,x.sigBytes=(y.length+1)*4,this._process();for(var g=this._hash,v=g.words,U=0;U<4;U++){var R=v[U];v[U]=(R<<8|R>>>24)&16711935|(R<<24|R>>>8)&4278255360}return g},clone:function(){var x=o.clone.call(this);return x._hash=this._hash.clone(),x}});function u(x,y,I,F,l,p,g){var v=x+(y&I|~y&F)+l+g;return(v<<p|v>>>32-p)+y}function f(x,y,I,F,l,p,g){var v=x+(y&F|I&~F)+l+g;return(v<<p|v>>>32-p)+y}function h(x,y,I,F,l,p,g){var v=x+(y^I^F)+l+g;return(v<<p|v>>>32-p)+y}function d(x,y,I,F,l,p,g){var v=x+(I^(y|~F))+l+g;return(v<<p|v>>>32-p)+y}t.MD5=o._createHelper(s),t.HmacMD5=o._createHmacHelper(s)})(Math),r.MD5})});var Tr=z((Ye,Nr)=>{(function(r,e){typeof Ye=="object"?Nr.exports=Ye=e(X()):typeof define=="function"&&define.amd?define(["./core"],e):e(r.CryptoJS)})(Ye,function(r){return(function(e){var t=r,n=t.lib,i=n.Base,o=n.WordArray,a=t.x64={},c=a.Word=i.extend({init:function(u,f){this.high=u,this.low=f}}),s=a.WordArray=i.extend({init:function(u,f){u=this.words=u||[],f!=e?this.sigBytes=f:this.sigBytes=u.length*8},toX32:function(){for(var u=this.words,f=u.length,h=[],d=0;d<f;d++){var x=u[d];h.push(x.high),h.push(x.low)}return o.create(h,this.sigBytes)},clone:function(){for(var u=i.clone.call(this),f=u.words=this.words.slice(0),h=f.length,d=0;d<h;d++)f[d]=f[d].clone();return u}})})(),r})});var Hr=z((Xe,Lr)=>{(function(r,e,t){typeof Xe=="object"?Lr.exports=Xe=e(X(),Tr()):typeof define=="function"&&define.amd?define(["./core","./x64-core"],e):e(r.CryptoJS)})(Xe,function(r){return(function(){var e=r,t=e.lib,n=t.Hasher,i=e.x64,o=i.Word,a=i.WordArray,c=e.algo;function s(){return o.create.apply(o,arguments)}var u=[s(1116352408,3609767458),s(1899447441,602891725),s(3049323471,3964484399),s(3921009573,2173295548),s(961987163,4081628472),s(1508970993,3053834265),s(2453635748,2937671579),s(2870763221,3664609560),s(3624381080,2734883394),s(310598401,1164996542),s(607225278,1323610764),s(1426881987,3590304994),s(1925078388,4068182383),s(2162078206,991336113),s(2614888103,633803317),s(3248222580,3479774868),s(3835390401,2666613458),s(4022224774,944711139),s(264347078,2341262773),s(604807628,2007800933),s(770255983,1495990901),s(1249150122,1856431235),s(1555081692,3175218132),s(1996064986,2198950837),s(2554220882,3999719339),s(2821834349,766784016),s(2952996808,2566594879),s(3210313671,3203337956),s(3336571891,1034457026),s(3584528711,2466948901),s(113926993,3758326383),s(338241895,168717936),s(666307205,1188179964),s(773529912,1546045734),s(1294757372,1522805485),s(1396182291,2643833823),s(1695183700,2343527390),s(1986661051,1014477480),s(2177026350,1206759142),s(2456956037,344077627),s(2730485921,1290863460),s(2820302411,3158454273),s(3259730800,3505952657),s(3345764771,106217008),s(3516065817,3606008344),s(3600352804,1432725776),s(4094571909,1467031594),s(275423344,851169720),s(430227734,3100823752),s(506948616,1363258195),s(659060556,3750685593),s(883997877,3785050280),s(958139571,3318307427),s(1322822218,3812723403),s(1537002063,2003034995),s(1747873779,3602036899),s(1955562222,1575990012),s(2024104815,1125592928),s(2227730452,2716904306),s(2361852424,442776044),s(2428436474,593698344),s(2756734187,3733110249),s(3204031479,2999351573),s(3329325298,3815920427),s(3391569614,3928383900),s(3515267271,566280711),s(3940187606,3454069534),s(4118630271,4000239992),s(116418474,1914138554),s(174292421,2731055270),s(289380356,3203993006),s(460393269,320620315),s(685471733,587496836),s(852142971,1086792851),s(1017036298,365543100),s(1126000580,2618297676),s(1288033470,3409855158),s(1501505948,4234509866),s(1607167915,987167468),s(1816402316,1246189591)],f=[];(function(){for(var d=0;d<80;d++)f[d]=s()})();var h=c.SHA512=n.extend({_doReset:function(){this._hash=new a.init([new o.init(1779033703,4089235720),new o.init(3144134277,2227873595),new o.init(1013904242,4271175723),new o.init(2773480762,1595750129),new o.init(1359893119,2917565137),new o.init(2600822924,725511199),new o.init(528734635,4215389547),new o.init(1541459225,327033209)])},_doProcessBlock:function(d,x){for(var y=this._hash.words,I=y[0],F=y[1],l=y[2],p=y[3],g=y[4],v=y[5],U=y[6],R=y[7],L=I.high,N=I.low,k=F.high,T=F.low,b=l.high,A=l.low,D=p.high,w=p.low,H=g.high,O=g.low,P=v.high,q=v.low,_=U.high,E=U.low,C=R.high,B=R.low,Q=L,$=N,Se=k,me=T,Ue=b,be=A,xt=D,Fe=w,ee=H,W=O,Me=P,ke=q,ze=_,Re=E,yt=C,De=B,te=0;te<80;te++){var G,le,qe=f[te];if(te<16)le=qe.high=d[x+te*2]|0,G=qe.low=d[x+te*2+1]|0;else{var Pt=f[te-15],ve=Pt.high,Ne=Pt.low,In=(ve>>>1|Ne<<31)^(ve>>>8|Ne<<24)^ve>>>7,Mt=(Ne>>>1|ve<<31)^(Ne>>>8|ve<<24)^(Ne>>>7|ve<<25),zt=f[te-2],we=zt.high,Te=zt.low,An=(we>>>19|Te<<13)^(we<<3|Te>>>29)^we>>>6,qt=(Te>>>19|we<<13)^(Te<<3|we>>>29)^(Te>>>6|we<<26),jt=f[te-7],Cn=jt.high,Sn=jt.low,Vt=f[te-16],Un=Vt.high,$t=Vt.low;G=Mt+Sn,le=In+Cn+(G>>>0<Mt>>>0?1:0),G=G+qt,le=le+An+(G>>>0<qt>>>0?1:0),G=G+$t,le=le+Un+(G>>>0<$t>>>0?1:0),qe.high=le,qe.low=G}var Fn=ee&Me^~ee&ze,Wt=W&ke^~W&Re,kn=Q&Se^Q&Ue^Se&Ue,Rn=$&me^$&be^me&be,Dn=(Q>>>28|$<<4)^(Q<<30|$>>>2)^(Q<<25|$>>>7),Jt=($>>>28|Q<<4)^($<<30|Q>>>2)^($<<25|Q>>>7),Nn=(ee>>>14|W<<18)^(ee>>>18|W<<14)^(ee<<23|W>>>9),Tn=(W>>>14|ee<<18)^(W>>>18|ee<<14)^(W<<23|ee>>>9),Kt=u[te],Ln=Kt.high,Gt=Kt.low,J=De+Tn,de=yt+Nn+(J>>>0<De>>>0?1:0),J=J+Wt,de=de+Fn+(J>>>0<Wt>>>0?1:0),J=J+Gt,de=de+Ln+(J>>>0<Gt>>>0?1:0),J=J+G,de=de+le+(J>>>0<G>>>0?1:0),Yt=Jt+Rn,Hn=Dn+kn+(Yt>>>0<Jt>>>0?1:0);yt=ze,De=Re,ze=Me,Re=ke,Me=ee,ke=W,W=Fe+J|0,ee=xt+de+(W>>>0<Fe>>>0?1:0)|0,xt=Ue,Fe=be,Ue=Se,be=me,Se=Q,me=$,$=J+Yt|0,Q=de+Hn+($>>>0<J>>>0?1:0)|0}N=I.low=N+$,I.high=L+Q+(N>>>0<$>>>0?1:0),T=F.low=T+me,F.high=k+Se+(T>>>0<me>>>0?1:0),A=l.low=A+be,l.high=b+Ue+(A>>>0<be>>>0?1:0),w=p.low=w+Fe,p.high=D+xt+(w>>>0<Fe>>>0?1:0),O=g.low=O+W,g.high=H+ee+(O>>>0<W>>>0?1:0),q=v.low=q+ke,v.high=P+Me+(q>>>0<ke>>>0?1:0),E=U.low=E+Re,U.high=_+ze+(E>>>0<Re>>>0?1:0),B=R.low=B+De,R.high=C+yt+(B>>>0<De>>>0?1:0)},_doFinalize:function(){var d=this._data,x=d.words,y=this._nDataBytes*8,I=d.sigBytes*8;x[I>>>5]|=128<<24-I%32,x[(I+128>>>10<<5)+30]=Math.floor(y/4294967296),x[(I+128>>>10<<5)+31]=y,d.sigBytes=x.length*4,this._process();var F=this._hash.toX32();return F},clone:function(){var d=n.clone.call(this);return d._hash=this._hash.clone(),d},blockSize:1024/32});e.SHA512=n._createHelper(h),e.HmacSHA512=n._createHmacHelper(h)})(),r.SHA512})});var Pr=z((Ze,Or)=>{(function(r,e){typeof Ze=="object"?Or.exports=Ze=e(X()):typeof define=="function"&&define.amd?define(["./core"],e):e(r.CryptoJS)})(Ze,function(r){return(function(){var e=r,t=e.lib,n=t.WordArray,i=e.enc,o=i.Base64={stringify:function(c){var s=c.words,u=c.sigBytes,f=this._map;c.clamp();for(var h=[],d=0;d<u;d+=3)for(var x=s[d>>>2]>>>24-d%4*8&255,y=s[d+1>>>2]>>>24-(d+1)%4*8&255,I=s[d+2>>>2]>>>24-(d+2)%4*8&255,F=x<<16|y<<8|I,l=0;l<4&&d+l*.75<u;l++)h.push(f.charAt(F>>>6*(3-l)&63));var p=f.charAt(64);if(p)for(;h.length%4;)h.push(p);return h.join("")},parse:function(c){var s=c.length,u=this._map,f=this._reverseMap;if(!f){f=this._reverseMap=[];for(var h=0;h<u.length;h++)f[u.charCodeAt(h)]=h}var d=u.charAt(64);if(d){var x=c.indexOf(d);x!==-1&&(s=x)}return a(c,s,f)},_map:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="};function a(c,s,u){for(var f=[],h=0,d=0;d<s;d++)if(d%4){var x=u[c.charCodeAt(d-1)]<<d%4*2,y=u[c.charCodeAt(d)]>>>6-d%4*2,I=x|y;f[h>>>2]|=I<<24-h%4*8,h++}return n.create(f,h)}})(),r.enc.Base64})});var zr=z((Qe,Mr)=>{(function(r,e){typeof Qe=="object"?Mr.exports=Qe=e(X()):typeof define=="function"&&define.amd?define(["./core"],e):e(r.CryptoJS)})(Qe,function(r){return(function(){var e=r,t=e.lib,n=t.WordArray,i=t.Hasher,o=e.algo,a=[],c=o.SHA1=i.extend({_doReset:function(){this._hash=new n.init([1732584193,4023233417,2562383102,271733878,3285377520])},_doProcessBlock:function(s,u){for(var f=this._hash.words,h=f[0],d=f[1],x=f[2],y=f[3],I=f[4],F=0;F<80;F++){if(F<16)a[F]=s[u+F]|0;else{var l=a[F-3]^a[F-8]^a[F-14]^a[F-16];a[F]=l<<1|l>>>31}var p=(h<<5|h>>>27)+I+a[F];F<20?p+=(d&x|~d&y)+1518500249:F<40?p+=(d^x^y)+1859775393:F<60?p+=(d&x|d&y|x&y)-1894007588:p+=(d^x^y)-899497514,I=y,y=x,x=d<<30|d>>>2,d=h,h=p}f[0]=f[0]+h|0,f[1]=f[1]+d|0,f[2]=f[2]+x|0,f[3]=f[3]+y|0,f[4]=f[4]+I|0},_doFinalize:function(){var s=this._data,u=s.words,f=this._nDataBytes*8,h=s.sigBytes*8;return u[h>>>5]|=128<<24-h%32,u[(h+64>>>9<<4)+14]=Math.floor(f/4294967296),u[(h+64>>>9<<4)+15]=f,s.sigBytes=u.length*4,this._process(),this._hash},clone:function(){var s=i.clone.call(this);return s._hash=this._hash.clone(),s}});e.SHA1=i._createHelper(c),e.HmacSHA1=i._createHmacHelper(c)})(),r.SHA1})});var jr=z((et,qr)=>{(function(r,e){typeof et=="object"?qr.exports=et=e(X()):typeof define=="function"&&define.amd?define(["./core"],e):e(r.CryptoJS)})(et,function(r){(function(){var e=r,t=e.lib,n=t.Base,i=e.enc,o=i.Utf8,a=e.algo,c=a.HMAC=n.extend({init:function(s,u){s=this._hasher=new s.init,typeof u=="string"&&(u=o.parse(u));var f=s.blockSize,h=f*4;u.sigBytes>h&&(u=s.finalize(u)),u.clamp();for(var d=this._oKey=u.clone(),x=this._iKey=u.clone(),y=d.words,I=x.words,F=0;F<f;F++)y[F]^=1549556828,I[F]^=909522486;d.sigBytes=x.sigBytes=h,this.reset()},reset:function(){var s=this._hasher;s.reset(),s.update(this._iKey)},update:function(s){return this._hasher.update(s),this},finalize:function(s){var u=this._hasher,f=u.finalize(s);u.reset();var h=u.finalize(this._oKey.clone().concat(f));return h}})})()})});var kt=z((tt,Vr)=>{(function(r,e,t){typeof tt=="object"?Vr.exports=tt=e(X(),zr(),jr()):typeof define=="function"&&define.amd?define(["./core","./sha1","./hmac"],e):e(r.CryptoJS)})(tt,function(r){return(function(){var e=r,t=e.lib,n=t.Base,i=t.WordArray,o=e.algo,a=o.MD5,c=o.EvpKDF=n.extend({cfg:n.extend({keySize:128/32,hasher:a,iterations:1}),init:function(s){this.cfg=this.cfg.extend(s)},compute:function(s,u){for(var f,h=this.cfg,d=h.hasher.create(),x=i.create(),y=x.words,I=h.keySize,F=h.iterations;y.length<I;){f&&d.update(f),f=d.update(s).finalize(u),d.reset();for(var l=1;l<F;l++)f=d.finalize(f),d.reset();x.concat(f)}return x.sigBytes=I*4,x}});e.EvpKDF=function(s,u,f){return c.create(f).compute(s,u)}})(),r.EvpKDF})});var Rt=z((rt,$r)=>{(function(r,e,t){typeof rt=="object"?$r.exports=rt=e(X(),kt()):typeof define=="function"&&define.amd?define(["./core","./evpkdf"],e):e(r.CryptoJS)})(rt,function(r){r.lib.Cipher||(function(e){var t=r,n=t.lib,i=n.Base,o=n.WordArray,a=n.BufferedBlockAlgorithm,c=t.enc,s=c.Utf8,u=c.Base64,f=t.algo,h=f.EvpKDF,d=n.Cipher=a.extend({cfg:i.extend(),createEncryptor:function(b,A){return this.create(this._ENC_XFORM_MODE,b,A)},createDecryptor:function(b,A){return this.create(this._DEC_XFORM_MODE,b,A)},init:function(b,A,D){this.cfg=this.cfg.extend(D),this._xformMode=b,this._key=A,this.reset()},reset:function(){a.reset.call(this),this._doReset()},process:function(b){return this._append(b),this._process()},finalize:function(b){b&&this._append(b);var A=this._doFinalize();return A},keySize:128/32,ivSize:128/32,_ENC_XFORM_MODE:1,_DEC_XFORM_MODE:2,_createHelper:(function(){function b(A){return typeof A=="string"?T:L}return function(A){return{encrypt:function(D,w,H){return b(w).encrypt(A,D,w,H)},decrypt:function(D,w,H){return b(w).decrypt(A,D,w,H)}}}})()}),x=n.StreamCipher=d.extend({_doFinalize:function(){var b=this._process(!0);return b},blockSize:1}),y=t.mode={},I=n.BlockCipherMode=i.extend({createEncryptor:function(b,A){return this.Encryptor.create(b,A)},createDecryptor:function(b,A){return this.Decryptor.create(b,A)},init:function(b,A){this._cipher=b,this._iv=A}}),F=y.CBC=(function(){var b=I.extend();b.Encryptor=b.extend({processBlock:function(D,w){var H=this._cipher,O=H.blockSize;A.call(this,D,w,O),H.encryptBlock(D,w),this._prevBlock=D.slice(w,w+O)}}),b.Decryptor=b.extend({processBlock:function(D,w){var H=this._cipher,O=H.blockSize,P=D.slice(w,w+O);H.decryptBlock(D,w),A.call(this,D,w,O),this._prevBlock=P}});function A(D,w,H){var O,P=this._iv;P?(O=P,this._iv=e):O=this._prevBlock;for(var q=0;q<H;q++)D[w+q]^=O[q]}return b})(),l=t.pad={},p=l.Pkcs7={pad:function(b,A){for(var D=A*4,w=D-b.sigBytes%D,H=w<<24|w<<16|w<<8|w,O=[],P=0;P<w;P+=4)O.push(H);var q=o.create(O,w);b.concat(q)},unpad:function(b){var A=b.words[b.sigBytes-1>>>2]&255;b.sigBytes-=A}},g=n.BlockCipher=d.extend({cfg:d.cfg.extend({mode:F,padding:p}),reset:function(){var b;d.reset.call(this);var A=this.cfg,D=A.iv,w=A.mode;this._xformMode==this._ENC_XFORM_MODE?b=w.createEncryptor:(b=w.createDecryptor,this._minBufferSize=1),this._mode&&this._mode.__creator==b?this._mode.init(this,D&&D.words):(this._mode=b.call(w,this,D&&D.words),this._mode.__creator=b)},_doProcessBlock:function(b,A){this._mode.processBlock(b,A)},_doFinalize:function(){var b,A=this.cfg.padding;return this._xformMode==this._ENC_XFORM_MODE?(A.pad(this._data,this.blockSize),b=this._process(!0)):(b=this._process(!0),A.unpad(b)),b},blockSize:128/32}),v=n.CipherParams=i.extend({init:function(b){this.mixIn(b)},toString:function(b){return(b||this.formatter).stringify(this)}}),U=t.format={},R=U.OpenSSL={stringify:function(b){var A,D=b.ciphertext,w=b.salt;return w?A=o.create([1398893684,1701076831]).concat(w).concat(D):A=D,A.toString(u)},parse:function(b){var A,D=u.parse(b),w=D.words;return w[0]==1398893684&&w[1]==1701076831&&(A=o.create(w.slice(2,4)),w.splice(0,4),D.sigBytes-=16),v.create({ciphertext:D,salt:A})}},L=n.SerializableCipher=i.extend({cfg:i.extend({format:R}),encrypt:function(b,A,D,w){w=this.cfg.extend(w);var H=b.createEncryptor(D,w),O=H.finalize(A),P=H.cfg;return v.create({ciphertext:O,key:D,iv:P.iv,algorithm:b,mode:P.mode,padding:P.padding,blockSize:b.blockSize,formatter:w.format})},decrypt:function(b,A,D,w){w=this.cfg.extend(w),A=this._parse(A,w.format);var H=b.createDecryptor(D,w).finalize(A.ciphertext);return H},_parse:function(b,A){return typeof b=="string"?A.parse(b,this):b}}),N=t.kdf={},k=N.OpenSSL={execute:function(b,A,D,w,H){if(w||(w=o.random(64/8)),H)var O=h.create({keySize:A+D,hasher:H}).compute(b,w);else var O=h.create({keySize:A+D}).compute(b,w);var P=o.create(O.words.slice(A),D*4);return O.sigBytes=A*4,v.create({key:O,iv:P,salt:w})}},T=n.PasswordBasedCipher=L.extend({cfg:L.cfg.extend({kdf:k}),encrypt:function(b,A,D,w){w=this.cfg.extend(w);var H=w.kdf.execute(D,b.keySize,b.ivSize,w.salt,w.hasher);w.iv=H.iv;var O=L.encrypt.call(this,b,A,H.key,w);return O.mixIn(H),O},decrypt:function(b,A,D,w){w=this.cfg.extend(w),A=this._parse(A,w.format);var H=w.kdf.execute(D,b.keySize,b.ivSize,A.salt,w.hasher);w.iv=H.iv;var O=L.decrypt.call(this,b,A,H.key,w);return O}})})()})});var Jr=z((nt,Wr)=>{(function(r,e,t){typeof nt=="object"?Wr.exports=nt=e(X(),Pr(),Ft(),kt(),Rt()):typeof define=="function"&&define.amd?define(["./core","./enc-base64","./md5","./evpkdf","./cipher-core"],e):e(r.CryptoJS)})(nt,function(r){return(function(){var e=r,t=e.lib,n=t.BlockCipher,i=e.algo,o=[],a=[],c=[],s=[],u=[],f=[],h=[],d=[],x=[],y=[];(function(){for(var l=[],p=0;p<256;p++)p<128?l[p]=p<<1:l[p]=p<<1^283;for(var g=0,v=0,p=0;p<256;p++){var U=v^v<<1^v<<2^v<<3^v<<4;U=U>>>8^U&255^99,o[g]=U,a[U]=g;var R=l[g],L=l[R],N=l[L],k=l[U]*257^U*16843008;c[g]=k<<24|k>>>8,s[g]=k<<16|k>>>16,u[g]=k<<8|k>>>24,f[g]=k;var k=N*16843009^L*65537^R*257^g*16843008;h[U]=k<<24|k>>>8,d[U]=k<<16|k>>>16,x[U]=k<<8|k>>>24,y[U]=k,g?(g=R^l[l[l[N^R]]],v^=l[l[v]]):g=v=1}})();var I=[0,1,2,4,8,16,32,64,128,27,54],F=i.AES=n.extend({_doReset:function(){var l;if(!(this._nRounds&&this._keyPriorReset===this._key)){for(var p=this._keyPriorReset=this._key,g=p.words,v=p.sigBytes/4,U=this._nRounds=v+6,R=(U+1)*4,L=this._keySchedule=[],N=0;N<R;N++)N<v?L[N]=g[N]:(l=L[N-1],N%v?v>6&&N%v==4&&(l=o[l>>>24]<<24|o[l>>>16&255]<<16|o[l>>>8&255]<<8|o[l&255]):(l=l<<8|l>>>24,l=o[l>>>24]<<24|o[l>>>16&255]<<16|o[l>>>8&255]<<8|o[l&255],l^=I[N/v|0]<<24),L[N]=L[N-v]^l);for(var k=this._invKeySchedule=[],T=0;T<R;T++){var N=R-T;if(T%4)var l=L[N];else var l=L[N-4];T<4||N<=4?k[T]=l:k[T]=h[o[l>>>24]]^d[o[l>>>16&255]]^x[o[l>>>8&255]]^y[o[l&255]]}}},encryptBlock:function(l,p){this._doCryptBlock(l,p,this._keySchedule,c,s,u,f,o)},decryptBlock:function(l,p){var g=l[p+1];l[p+1]=l[p+3],l[p+3]=g,this._doCryptBlock(l,p,this._invKeySchedule,h,d,x,y,a);var g=l[p+1];l[p+1]=l[p+3],l[p+3]=g},_doCryptBlock:function(l,p,g,v,U,R,L,N){for(var k=this._nRounds,T=l[p]^g[0],b=l[p+1]^g[1],A=l[p+2]^g[2],D=l[p+3]^g[3],w=4,H=1;H<k;H++){var O=v[T>>>24]^U[b>>>16&255]^R[A>>>8&255]^L[D&255]^g[w++],P=v[b>>>24]^U[A>>>16&255]^R[D>>>8&255]^L[T&255]^g[w++],q=v[A>>>24]^U[D>>>16&255]^R[T>>>8&255]^L[b&255]^g[w++],_=v[D>>>24]^U[T>>>16&255]^R[b>>>8&255]^L[A&255]^g[w++];T=O,b=P,A=q,D=_}var O=(N[T>>>24]<<24|N[b>>>16&255]<<16|N[A>>>8&255]<<8|N[D&255])^g[w++],P=(N[b>>>24]<<24|N[A>>>16&255]<<16|N[D>>>8&255]<<8|N[T&255])^g[w++],q=(N[A>>>24]<<24|N[D>>>16&255]<<16|N[T>>>8&255]<<8|N[b&255])^g[w++],_=(N[D>>>24]<<24|N[T>>>16&255]<<16|N[b>>>8&255]<<8|N[A&255])^g[w++];l[p]=O,l[p+1]=P,l[p+2]=q,l[p+3]=_},keySize:256/32});e.AES=n._createHelper(F)})(),r.AES})});var Gr=z((it,Kr)=>{(function(r,e,t){typeof it=="object"?Kr.exports=it=e(X(),Rt()):typeof define=="function"&&define.amd?define(["./core","./cipher-core"],e):e(r.CryptoJS)})(it,function(r){return r.pad.NoPadding={pad:function(){},unpad:function(){}},r.pad.NoPadding})});var Qr=z((Uo,Zr)=>{var{Buffer:se}=Je(),ge=X();Ft();Hr();Jr();Gr();function ot(r){let e=se.from(r),t=[];for(let n=0;n<e.length;n++)t[n>>>2]=(t[n>>>2]||0)|e[n]<<24-n%4*8;return ge.lib.WordArray.create(t,e.length)}function Yr(r){let e=se.alloc(r.sigBytes);for(let t=0;t<e.length;t++)e[t]=r.words[t>>>2]>>>24-t%4*8&255;return e}function Xr(r){let e=[];return{update(t){return e.push(se.from(t)),this},digest(t){let n=Yr((r==="md5"?ge.MD5:ge.SHA512)(ot(se.concat(e))));return t?n.toString(t):n}}}function Ci(r,e,t){if(r!=="aes-128-cbc")throw new Error("Unsupported cipher");let n=[];return{setAutoPadding(i){if(i)throw new Error("Unsupported padding")},update(i){return n.push(se.from(i)),se.alloc(0)},final(){return Yr(ge.AES.decrypt(ge.lib.CipherParams.create({ciphertext:ot(se.concat(n))}),ot(e),{iv:ot(t),mode:ge.mode.CBC,padding:ge.pad.NoPadding}))}}}var Si=0;function Ui(r){if(globalThis.crypto&&typeof globalThis.crypto.getRandomValues=="function"){let t=new Uint8Array(r);return globalThis.crypto.getRandomValues(t),se.from(t)}let e=[];for(;e.length*64<r;)e.push(Xr("sha512").update(String(globalThis.__hongguoEntropy||Math.random())+":"+Date.now()+":"+Si++).digest());return se.concat(e).subarray(0,r)}Zr.exports={createHash:Xr,createDecipheriv:Ci,randomBytes:Ui}});var tn=z((Fo,en)=>{var{Buffer:at}=Je();en.exports=function(e){let t=at.isBuffer(e)?e:at.from(e),n=at.alloc(Math.ceil((t.length+9)/64)*64);t.copy(n),n[t.length]=128;let i=t.length*8;n.writeUInt32BE(Math.floor(i/4294967296),n.length-8),n.writeUInt32BE(i>>>0,n.length-4);let o=new Uint32Array([1937774191,1226093241,388252375,3666478592,2842636476,372324522,3817729613,2969243214]),a=new Uint32Array(68),c=(u,f)=>(u<<(f&31)|u>>>(32-f&31))>>>0;for(let u=0;u<n.length;u+=64){for(let g=0;g<16;g++)a[g]=n.readUInt32BE(u+g*4);for(let g=16;g<68;g++){let v=a[g-16]^a[g-9]^c(a[g-3],15);a[g]=v^c(v,15)^c(v,23)^c(a[g-13],7)^a[g-6]}let[f,h,d,x,y,I,F,l]=o;for(let g=0;g<64;g++){let v=c(f,12),U=c(v+y+c(g<16?2043430169:2055708042,g)>>>0,7),R=U^v,L=g<16?f^h^d:f&h|f&d|h&d,N=g<16?y^I^F:y&I|~y&F,k=L+x+R+(a[g]^a[g+4])>>>0,T=N+l+U+a[g]>>>0;x=d,d=c(h,9),h=f,f=k,l=F,F=c(I,19),I=y,y=(T^c(T,9)^c(T,17))>>>0}let p=[f,h,d,x,y,I,F,l];for(let g=0;g<8;g++)o[g]^=p[g]}let s=at.alloc(32);for(let u=0;u<8;u++)s.writeUInt32BE(o[u],u*4);return s}});var on=z((ko,nn)=>{var Fi=["auto","1080p","720p"];function rn(r="auto"){if(!Fi.includes(r))throw new Error("\u4E0B\u8F7D\u6E05\u6670\u5EA6\u65E0\u6548\uFF0C\u8BF7\u9009\u62E9\u81EA\u52A8\u30011080p \u6216 720p");return r}function ki({width:r,height:e}={},t="auto"){if(t=rn(t),t==="auto")return!0;let n=[Number(r),Number(e)];return n.every(i=>Number.isFinite(i)&&i>0)&&Math.min(...n)>=Number.parseInt(t,10)}nn.exports={normalizeDownloadQuality:rn,meetsDownloadQuality:ki}});var pt=z((Ro,mn)=>{var dn=ur(),{Buffer:S}=Je(),K=Qr(),ht=tn(),{normalizeDownloadQuality:Ri,meetsDownloadQuality:Di}=on(),an=()=>String(1e15+parseInt(K.randomBytes(6).toString("hex"),16)),pn=K.randomBytes(18).toString("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,""),ct=Date.now(),xn="https://api5-normal-sinfonlineb.fqnovel.com/novel/player/multi_video_model/v1/",dt="com.phoenix.read/71332 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)",yn={ac:"wifi",channel:"update_64",aid:"8662",app_name:"novelread",version_code:"71332",version_name:"7.1.3.32",device_platform:"android",os:"android",ssmix:"a",device_type:"25053RT47C",device_brand:"Redmi",language:"zh",os_api:"36",os_version:"16",manifest_version_code:"71332",resolution:"1280*2772",dpi:"520",update_version_code:"71332",host_abi:"arm64-v8a",dragon_device_type:"phone",pv_player:"71332",compliance_status:"0",need_personal_recommend:"1",player_so_load:"1",is_android_pad_screen:"0"};function fe(r,e=""){return String(r??e).trim()}function cn(r){return fe(r).replace(/\\\//g,"/").replace(/\\u0026/g,"&").replace(/&amp;/g,"&")}function Lt(r){try{return JSON.parse(String(r).replace(/(\"(?:[A-Za-z0-9_]*_id|id)\"\s*:\s*)(-?\d{16,})(?=\s*[,}\]])/g,'$1"$2"'))}catch{return null}}function Ni(r){return Object.entries(r).map(([e,t])=>{let n=i=>encodeURIComponent(String(i??"")).replace(/[!'()]/g,o=>`%${o.charCodeAt(0).toString(16).toUpperCase()}`);return`${n(e)}=${n(t)}`}).join("&")}function Ti(r){return K.createHash("md5").update(r).digest("hex").toUpperCase()}function M(r){return Number(r)>>>0}function re(r,e){let t=e&31,n=M(r);return M(n<<t|n>>>32-t)}function ne(r,e){let t=e&31,n=M(r);return M(n>>>t|n<<32-t)}function st(r,e){return[(r[0]^e[0])>>>0,(r[1]^e[1])>>>0]}function sn(r,e){let t=r[0]+e[0];return[t>>>0,r[1]+e[1]+(t>=4294967296?1:0)>>>0]}function ft(r,e){let t=r[0],n=r[1],i=e&63;if(i>=32){let o=t;t=n,n=o,i-=32}return i?[(t>>>i|n<<32-i)>>>0,(n>>>i|t<<32-i)>>>0]:[t,n]}function Dt(r,e){return[r.readUInt32LE(e),r.readUInt32LE(e+4)]}function fn(r,e,t){r.writeUInt32LE(e[0],t),r.writeUInt32LE(e[1],t+4)}function Z(r){let e=S.alloc(4);return e.writeUInt32LE(M(r)),e}function gn(r){let e=S.alloc(4);return e.writeUInt32BE(M(r)),e}function Li(r){let e=Number(r);return e<0?-e*2-1:e*2}function He(r){let e=Number(r);if(!Number.isSafeInteger(e)||e<0)throw new Error("Invalid integer");let t=[];for(;e>127;)t.push(e%128|128),e=Math.floor(e/128);return t.push(e),S.from(t)}function Hi(r,e,t="string"){if(e==null||e==="")return S.alloc(0);if(t==="bytes"||t==="string"||t==="message"){let n=t==="bytes"?S.from(e):t==="message"?e:S.from(String(e));return S.concat([He(r*8+2),He(n.length),n])}if(t==="float"){let n=S.alloc(4);return n.writeFloatLE(Number(e)),S.concat([He(r*8+5),n])}return S.concat([He(r*8),He(t==="sint"?Li(e):e)])}function Oe(r){return S.concat(r.map(([e,t,n])=>Hi(e,t,n)))}function Ce(r,e){let t=M(r);for(let n=0;n<e.length;n+=1)(n&1)===0?t=M(t>>>4^t^t<<6^e[n]):t=M(~(t>>>7^t^(e[n]|t<<12)));return t}function Nt(r){let e=539100192;for(let t=0;t<12;t+=1){let n=(t&1)===0?e>>>3^e:e>>>5^e;e=(t&1)===0?r[t]^e<<7:r[t]|e<<11,(t&1)!==0&&(e=~e),e=M(e^n)}return M((e|4)^16777216)}var Oi=[2813263392,1900671446,1206176263,3920990055,2478384350,3323252981,951050479,2998644083,3796124867,2637884571,3749394404,3635506496,4172034488,1991878923,836252654,2503986788,892704164,1175044411,915558408,2355956005,1576386935,486274347,2320476144,290235230,2173958532,2054850355,829076693,1008783305,2799191123,974671884,2039399546,2544331560,1724186518,1366385731,231930939,3043585447,3152755397,1548997124,3542485198,1920580076,4095250127,4158100443,858571921,2876681749,2615928615,413143940,1542060199,1603315540,968254400,912735363,2090005780,2642253015,3806910890,1602133673,2059224401,1453196762,1084380722,1039509925,3132325248,1161987804,1063079544,64468829,2986232567,2779457187],Pi=S.from("0f0704000908030a060b050d0e010c020f05080c0009020103070e060b0a0d04060500070c000a04080f010b0d09020e060b02050403080101070a000d0c090e0d070e0f0b0208030c0509010004060a0d0902060f0b0a040807000c0503010e0c090f07060f030e020d0405010b0a000c050a090e0802040407030f01060b000b0f0408020a0700090d06010e03050c0b060a0508020c03070f0e090d0001040906080f050800040a0b030d01020c0e090d0c0604070a03030f00080105020e01000d0f090a0b0e0402080703060c0501080a0c0f0905060b000304020e070d04080f000c0f0e0d0a01060207090503040205080d0b0a0606000e0f070c09030a08040f000b01060d0c0709030e05020a070b050f00020e0108030d0c0609040d070f08050f06040b0a0e0c090002030d0c020704010b0e0e08060f09050003","hex");function ut(r,e,t,n,i,o,a,c){let s;return r===0?s=t&n|~t&i:r===1?s=t&i|n&~i:r===2?s=t^n^i:s=n^(t|~i),M(t+re(M(e+s+o+c),a))}function Mi(r,e,t,n){let i=Oi.map(I=>ne(I,n)),o=[ne(2044785403,e),ne(3367314800,e),ne(3955423437,e),ne(2081443219,e)],a=e+6&255,c=[ne(431900774,a),ne(3898181300,a),ne(3785044590,a),ne(1909577684,a)],s=[];for(let I=0;I<16;I+=1)s.push(r.readUInt32LE(I*4));let[u,f,h,d]=o,x=(I,F,l,p)=>{for(let g=0;g<16;g+=1){let v=g&3,U=v===0?ut(I,u,f,h,d,s[t[p+g]],l[g],i[p+g]):v===1?ut(I,d,u,f,h,s[t[p+g]],l[g],i[p+g]):v===2?ut(I,h,d,u,f,s[t[p+g]],l[g],i[p+g]):ut(I,f,h,d,u,s[t[p+g]],l[g],i[p+g]);v===0?u=U:v===1?d=U:v===2?h=U:f=U}};x(0,t,[7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22],0),x(1,t,[5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20],16),x(2,t,[4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23],32),x(3,t,[6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21],48);let y=S.alloc(16);return y.writeUInt32LE(M(o[0]+u^c[0]),0),y.writeUInt32LE(M(o[1]+f^c[1]),4),y.writeUInt32LE(M(o[2]+h^c[2]),8),y.writeUInt32LE(M(o[3]+d^c[3]),12),S.concat([y,Z(Nt(y))])}function zi(r,e,t,n,i){let o=(r&13)*86,a=(o>>>15&255)+(o>>>8&255),c=[2306929307,3948190847,2961647323,3557602790,3908393444][a],s=c+i+1&255,u=M(c+i),f=u+5&7,h=[132,150,119,157,212,21,11,248],d=S.from(h.map(y=>(y|y<<8)>>f&255)),x=S.concat([e,t,n,d,S.from("a0010000","hex")]);return Mi(x,u,Pi.subarray(a<<6,a+1<<6),s)}function qi(r,e){let t=S.alloc(Math.min(r.length,e.length));for(let n=0;n<t.length;n+=1)t[n]=r[n]^e[n];return t}function ji(r,e,t,n){let i=Ce(Ce(Ce(539167016,r),e),t),o=i&15,a=o*171>>9,c=o-a*3;if(c===2)return zi(i,r,e,t,n);if(c!==0)return S.concat([r.subarray(0,16),e,Z(Nt(S.concat([r,e])))]);let u=[3299313024,3015769401,3314308742,3383376807,4121406962,2520526545][a],f=u+n+1&255,h=M(u+n),x=[3954593711,128638146,3476129727,3759225087,1829502207,1513137086,3021657656,873991864,4063488879,2980414668,3435335111,1204935505,3579204574,1890078625,1464286226,4151247496,738688778,3658336976,4223168364,4257533696,1753874957,3866543782,2362848139,440175886,3437801579,1792077067,2689738519,3698437251,579197809,3585400230,1936688720,1700802668,1635574438,3827515774,172024131,1414414386,2296380202,1902910176,1279687304,95566771,3788552294,3131301048,2922607827,3275233872,386070363,4268598120,4038381384,1309670328,1923797261,650459709,4072464630,3025499521,1243971549,2352054946,2869640070,1029569300,1326462516,3548074711,1146027798,3943314385,1822977902,2640807,137919738,1605596550].map(k=>ne(k,f)),y=h+2&7,I=[250,69,97,215],F=S.from(I.map(k=>(k|k<<8)>>y&255)),l=S.concat([r,e,t,F,S.from("00000000000001a0","hex")]),p=[];for(let k=0;k<l.length;k+=4)p.push(l.readUInt32BE(k));let g=p[0];for(let k=0;k<112;k+=1){let T=p[k+1],b=p[k+14],A=re(T,14)^re(T,25)^T>>>3,D=re(b,13)^re(b,15)^b>>>10;p.push(M(g+p[k+9]+A+D)),g=T}let v=[2059030472,1729520903,1677982208,873419055,984304912,3005047866,2874125293,2152413264].map(k=>ne(k,h&31)),U=[[101,5,7,6,3,2,1,0,5,4,3],[96,0,6,7,5,3,2,1,5,4,4],[96,7,6,2,1,4,0,5,4,3,5],[99,3,6,2,4,5,1,0,0,7,6],[96,0,5,6,7,3,1,2,5,4,4],[100,2,0,3,5,4,6,7,2,1,5]][a],R=v.slice();for(let k=0;k<U[0];k+=1){let T=u+k,b=p[T&127],A=(R[U[3]]^R[U[4]])&R[U[1]]^R[U[3]],D=re(R[U[1]],26)^re(R[U[1]],21)^re(R[U[1]],7),w=M(b+A+D+x[T&63]+R[U[5]]),H=re(R[U[2]],30)^re(R[U[2]],19)^re(R[U[2]],10),O=R[U[2]]&R[U[6]]|(R[U[2]]|R[U[6]])&R[U[7]],P=M(H+O),q=R[U[9]];R.unshift(R.pop()),R[U[10]]=M(P+w),R[U[8]]=M(q+w)}let L=S.alloc(32);for(let k=0;k<8;k+=1)L.writeUInt32BE(M(R[k]+v[k]),k*4);return qi(L.subarray(0,16),L.subarray(16)).copy(L,0),S.concat([L.subarray(0,16),Z(Nt(L.subarray(0,16)))])}function Vi(r){let e=0;for(let t=0;t<8;t+=1)e=e<<1|r>>t&1;return e}function $i(r,e){let t=Array.from({length:256},(o,a)=>a),n=0;for(let o=0;o<256;o+=1)n=n+t[o]+e[o%e.length]&255,t[o]=t[n];let i=0;return n=0,S.from(r.map(o=>{i+=1;let a=t[i];n+=a;let c=t[n&255];return t[i]=c,o^t[c+c&255]}))}function Wi(r,e,t,n){let i=S.alloc(4);i.writeUInt32LE(67503104);let o=S.concat([K.createHash("md5").update(r).digest().subarray(0,4),e?K.createHash("md5").update(e).digest().subarray(0,4):S.alloc(4),S.alloc(4),i,gn(t)]),a=[74,64,22,n>>8&255,71,108,1,n&255],c=$i([...o],a);for(let s=0;s<c.length;s+=1){let u=c[s];u=(u>>4|u<<4)&255;let f=s+1<c.length?c[s+1]:c[0];c[s]=~(Vi((f^u)&255)^20)&255}return S.concat([S.from("8404","hex"),S.from([n&255,n>>8&255,64,1]),c]).toString("hex")}function Ji(r){return Oe([[1,1,"sint"],[2,2,"sint"],[3,"8662"],[4,r],[5,pn],[6,"!noperm!"],[7,-888888,"sint"],[8,-888888,"sint"],[9,3,"sint"],[10,-888888,"sint"],[11,"!notset!"],[12,"Asia/Shanghai,8"],[13,"zh_CN"],[14,4,"sint"],[16,0,"float"],[17,0,"float"],[18,0,"float"],[19,0,"float"],[20,0,"float"],[21,0,"float"],[22,"16"],[23,41,"sint"],[24,36,"sint"],[25,ct,"sint"],[26,ct,"sint"],[27,ct,"sint"],[28,ct,"sint"],[29,-1,"sint"],[30,"25053RT47C"],[31,"Redmi"],[32,"25053RT47C"],[33,"25053RT47C"],[34,"Xiaomi"],[35,"Redmi"],[36,"Redmi"],[38,31,"sint"]])}var Ki=S.from("+n0Ia5xZs0sEXznQOEqRmQBnpiCf9U2Ccybu3xhmgzOAAxn72f6uqqmwUsYL83klTni0NqxdGieeiNu9PGPsSRXBMB/cuFbUbM3KCUPINaPvHvSW0vwOcnuUhNHqRVpiAj/TEoE0K91+5ijypUYTATsh9mE3KSoN7Yyvv51cuyR2D3XkU4nhmI2xmmVwT1RMWKtub4sjxAcRDLrPoKSO2AU9FLLadMPX577Wf95IFj6FkKFVt3dCIsmGUC4X+WQxLJvxbRxEaOPpqJOXyzJX6+Vxaq3AzMfF/WAdoi1Hp+JRaV56zgpBtpWP97mH4DoGEIq1+FvV8LyS/3wvwugbQOwb2r26mJEMsiuDQTRn+wrYdrVGBVlhI3WQhyrjUBVMrLF5667llUcEaPCGPVGLD8qO5LlO8hKCvA7V9+8oJc9bXelqVQLhM76T5/WtnT45JKji+hdX0HoNCDDWuKON/QeaxB5uImSX0h2wv0VmP2zd2yeApxHcpsVS+MC2yFwAc2B7oBkTqsk1SEvTpM2fmfMQREBUfin0Bh+iq6EvPPavhWI2IX9e3yAas7Tm/3KEj2UmlFp36kN4x0rMLBRrxuh0U/zUHM4xcAMYjJY4MonxOl/X+alpt2M3WMI7w3HLnpIBigtNiJu7T21v4P6lSd5WFgntnMEt7oF92XzRLkJbTcGmXepE/UVOG6E/0YnhfS+q26utWcuxzpooyeD2cDlK1/8w9d28VzsRjbLuALbmGlp8+d7EzS6Au7lMpZ+ECMZvQmzwJ+eLOpxR+2chdUExp8ogQyq3v9l68rX4jCwjg0+PYKAEEzcU4wHFY2ZcdIHfWL1okD3SszT0GZMyKdZJrg1L2AeerB4tC0C4crp2EHGo5FYdSP7lwkeR2ocmnR+Ia8CYviUJlzOjhRZef9xuVOn3qcjow3fQgivsAmKKkg4+sA8F8/GWeDiGNhg8JM8KtFPMYWWkx5TVFX5t73kiNRJqjlIGVXtGZFCV4gzt0xcDopuZ6xz8r9Rzafpf9ywev8jh8592gHFIqpStZPuJxmDDMrNN0uBE3V+oscdoIzTJbRJ/t+sVvqnReJOgDJKk10fjisJwqyZBmnmn2BSFj8BvVtCMEbkuPOKdzw7eA11GPs04Qw8zWtkaZWwiO/wwpojqN6K0jY5RnNZA7vn4hPSul+nKCkVnVwQvg1zVxcSCtqORmB9KrJaBbssbCQivGJVJfVTt+hYxOtq4ZvWl8f4QAQZ0zGPffCgl9s6yT4vlvIdpu4YhBwA25wtQWZsc6GJYGWHyvSdeuh3mmUI9DSq13Fsp8C1MU3tqc04/df9LoTUXVXI5INOw/e8C7Hd+5CvbkMEFnnrUUmskEw==","base64");function un(r,e){let t=S.from(r);for(let n=0;n<t.length;n+=1)t[n]^=e[n%e.length];return t}function Gi(r){return Array.from({length:4},(e,t)=>Array.from(r.subarray(t*4,t*4+4)))}function hn(r){return S.from(r.flat())}function Yi(r){for(let e=0;e<4;e+=1){let t=r[0][e]^r[1][e]^r[2][e]^r[3][e],n=r[0][e],i=o=>(o<<1^(o&128?27:0))&255;r[0][e]^=t^i(r[0][e]^r[1][e]),r[1][e]^=t^i(r[1][e]^r[2][e]),r[2][e]^=t^i(r[2][e]^r[3][e]),r[3][e]^=t^i(r[3][e]^n)}}var Tt=class{constructor(e,t){this.wordSize=t&3,this.box=Ki.subarray(this.wordSize*256,(this.wordSize+1)*256),this.con=[[1,0,2,3],[1,3,0,2],[0,1,3,2],[1,0,2,3]][this.wordSize],this.con2=[[1,0,2,3],[2,0,3,1],[0,1,3,2],[1,0,2,3]][this.wordSize],this.order=[[0,9,14,11,4,13,2,7,8,1,6,15,12,5,10,3],[0,9,14,15,4,13,2,7,8,1,6,3,12,5,10,11],[0,9,14,7,4,13,2,11,8,1,6,3,12,5,10,15],[0,9,14,11,4,13,2,7,8,1,6,15,12,5,10,3]][this.wordSize];let n=[3389152732,2185086278,3376547203,3264750175][this.wordSize],i=S.alloc(16);for(let s=0;s<4;s+=1)i.writeUInt32LE(n,s*4);let o=un(i,e),a=S.concat([o,S.alloc(32)]),c=8;for(let s=4;s<12;s+=1){let u=4*(s-1),f=a[u],h=a[u+1],d=a[u+2],x=a[u+3];if((s&3)===0){let y=(M(n>>(c&24))^this.box[h])&255;h=this.box[d],d=this.box[x],x=this.box[f],f=y}c+=2,a[u+4]=f^a[u-12],a[u+5]=h^a[u-11],a[u+6]=d^a[u-10],a[u+7]=x^a[u-9]}this.keys=Array.from({length:12},(s,u)=>Array.from(a.subarray(u*4,u*4+4)))}add(e,t){for(let n=0;n<4;n+=1)for(let i=0;i<4;i+=1)e[n][i]^=t[n][i]}addCon(e,t){for(let n=0;n<4;n+=1)for(let i=0;i<4;i+=1)e[n][i]^=t[n][this.con2[i]]}sub(e){for(let n=0;n<4;n+=1)for(let i=0;i<4;i+=1)e[n][i]=this.box[e[n][i]];let t=e.map(n=>n.slice());for(let n=0;n<4;n+=1)e[n]=t[this.con2[n]]}shift(e){let t=hn(e);for(let n=0;n<16;n+=1)e[Math.floor(n/4)][n%4]=t[this.order[n]]}shiftCon(e){let t=e.map(n=>n.slice());for(let n=0;n<4;n+=1)e[n]=this.con2.map(i=>t[n][i])}block(e){let t=Gi(e);this.addCon(t,this.keys.slice(0,4));for(let n=1;n<3;n+=1)this.sub(t),this.shift(t),n===1&&(this.shiftCon(t),Yi(t)),this.addCon(t,this.keys.slice(n*4));return this.add(t,this.keys.slice(4)),hn(t)}encrypt(e,t){let n=S.from(e),i=S.alloc(32);for(let u=0;u<31;u+=1){let f=u*8,l=n[f]>>4&2|n[f+1]&64|n[f+2]>>2&1|n[f+3]<<3&128|n[f+4]>>1&4|n[f+5]<<3&16|n[f+6]<<5&32;i[u]=l|n[f+7]>>4&8}i[31]=1;let o=[],a=S.from(t);for(let u=0;u<i.length;u+=16){let f=this.block(un(i.subarray(u,u+16),a));o.push(f),a=f}let c=S.concat(o),s=S.from(n);for(let u=0;u<31;u+=1){let f=u*8,h=c[u];s[f]&=223,s[f]|=h<<4&32,s[f+1]&=191,s[f+1]|=h&64,s[f+2]&=251,s[f+2]|=h<<2&4,s[f+3]&=239,s[f+3]|=h>>3&16,s[f+4]&=247,s[f+4]|=h+h&8,s[f+5]&=253,s[f+5]|=h>>3&2,s[f+6]&=254,s[f+6]|=h>>5&1,s[f+7]&=127,s[f+7]|=h<<4&128}return S.concat([c.subarray(-1),s])}};function Xi(r,e){let t=S.alloc(r.length);for(let a=0;a<r.length;a+=1){let c=a*4&28,s=e[c],u=e[c+1],f=((r[a]<<4|r[a]>>>4)&255)+s;f=~f^u,f=((f&255)<<3|(f&255)>>>5)&255,f=f+u&255,f=(f^s)&255,t[r.length-a-1]=~f&255}let n=t[t.length-1]^t[t.length-2],i=t[0];t[0]=~n+i&255,t[1]=(t[0]^t[t.length-1]^254)+t[1]&255,t[2]=t[2]+(n-i^(t[1]<<3|t[1]>>>5)&255^2)&255;for(let a=0;a<t.length-4;a+=1){let c=(t[a+2]<<3|t[a+2]>>>5)&255^t[a+1]^a+3;t[a+3]=~c+t[a+3]&255}t[t.length-1]^=t[t.length-2];let o=0;for(let a=0;a<t.length-1;a+=1)o+=t[a+1];return t[0]=(t[0]^t[1])+o&255,t}function Zi(r,e){let t=S.concat([r,Z(e),r]),n=ht(t),i=e>>16&255,o=(i<<11|e>>>24)^i>>5^i;return o=~o>>>0,[n,Z(o)]}function Qi(r,e,t,n){let i=e?K.createHash("md5").update(e).digest():S.alloc(16),o=ht(r.split("?")[1]),a=Z(t),c=ji(o,i,a,t),s=Oe([[1,111,"sint"],[2,10,"sint"],[3,694367,"sint"],[5,586952199,"sint"]]),u=Math.floor(Math.random()*4294967296),f=Math.floor(Math.random()*21)+100,h=Math.floor(Math.random()*2e3)+10001,d=Oe([[1,f,"sint"],[2,146331399,"sint"],[3,146331396,"sint"],[5,7,"sint"],[6,"v04.06.04.03-bugfix"],[7,h,"sint"],[12,Ji(n.device_id),"message"],[13,Oe([[1,Math.floor(Date.now()/1e3),"sint"],[2,-2,"sint"],[4,200,"sint"]]),"message"],[14,n.version_name]]),x=ht(S.concat([S.from(r.split("?")[1]),i,S.from("none")])),y=Oe([[1,S.from("f7e85ffad7d7dc3bd62ac87057cf6118","hex"),"bytes"],[2,3,"sint"],[3,u,"sint"],[4,"8662"],[5,n.device_id],[6,"1588093228"],[7,n.version_name],[8,"v04.06.04-ml-android"],[9,67503104,"sint"],[10,S.from("4001000000000000","hex"),"bytes"],[12,t,"sint"],[13,c,"bytes"],[14,o.subarray(0,6),"bytes"],[15,s,"message"],[16,pn],[17,t,"sint"],[19,x,"bytes"],[20,"none"],[21,312,"sint"],[23,d,"message"],[24,'{"cmr":16777216,"cmr2":16777216,"un_h":1879194040,"vpn":0,"kd":0,"fkd":3672518972,"pd":-1872573247,"dyn":"","do":0,"tk":true}']]),I=Math.floor(Math.random()*4294967296),[F,l]=Zi(S.from("8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eae f71cb691f7aa8aa2f5".replace(/ /g,""),"hex"),I),p=Xi(y,F);p=S.concat([S.from("4001000000000000","hex"),p]).reverse();for(let k=0;k<p.length;k+=1)p[k]^=l[~k&3];let g=(o[0]&63)<<14|402653185|(c[0]&63)<<8,v=Math.floor(Math.random()*4294967296),U=S.concat([S.from([53]),Z(v),Z(g),p,S.from([I>>16,I>>24])]),R=new Tt(S.from("f1593376766ea98d34f31b057a9d5be4","hex"),t).encrypt(U,S.from("1fe109a4125283f418de9e051a969e12","hex")),L=S.from("03000000f7e85ffad7d7dc3bd62ac87057cf6118","hex"),N=S.alloc(20);for(let k=0;k<20;k+=4)N.writeUInt32LE(M(L.readUInt32LE(k)^t),k);return S.concat([N,S.from([I&255,I>>8&255,0,1]),R]).toString("base64")}function eo(r){let e=Math.floor(Math.random()*4294967296),t=S.concat([Z(e),S.from("8662")]),n=K.createHash("md5").update(t).digest(),i=S.from(n.toString("hex"),"ascii"),o=[];for(let d=0;d<4;d+=1)o.push(Dt(i,d*8));let a=[o[0]],c=o[0],s=o[1];o.splice(0,2);for(let d=0;d<34;d+=1){let x=sn(ft(s,8),c);x=st(x,[d,0]),o.push(x),x=st(x,ft(c,61)),a.push(x),c=x,s=o.shift()}let u=S.from(`${r}-1588093228-8662`),f=S.alloc(Math.ceil((u.length+1)/16)*16,16-u.length%16);u.copy(f);let h=[];for(let d=0;d<f.length;d+=16){let x=Dt(f,d),y=Dt(f,d+8);for(let F=0;F<34;F+=1)y=st(a[F],sn(x,ft(y,8))),x=st(y,ft(x,61));let I=S.alloc(16);fn(I,x,0),fn(I,y,8),h.push(I)}return S.concat([Z(e),...h]).toString("base64")}function to(r,e,t){let n=e?K.createHash("md5").update(e).digest():S.alloc(16),i=ht(r.split("?")[1]),a=Ce(Ce(Ce(539167016,i),n),Z(t))&15;return a-(a*171>>9)*3}function Ht(r,e=xn,t={},n){let i={...yn,...n||{iid:an(),device_id:an()}},o=Math.floor(Date.now()/1e3),a=r==null?null:S.from(r),c=Date.now(),s=c,u="",f="";for(let x=0;x<32;x+=1){s=c+x;let y={...i,...t,ts:String(o),_rticket:String(s)};if(u=Ni(y),f=`${e}?${u}`,to(f,a,o)!==1)break}let h=Math.floor(Math.random()*65536),d={"User-Agent":dt,Accept:"application/json; charset=utf-8,application/x-protobuf","Content-Type":"application/json; charset=UTF-8","x-xs-from-web":"0","x-ss-req-ticket":String(s),"x-tt-request-tag":"t=0;n=0","sdk-version":"2","passport-sdk-version":"50561","x-vc-bdturing-sdk-version":"3.7.2.cn","x-ss-stub":Ti(a||""),"x-gorgon":Wi(u,a,o,h),"x-khronos":String(o),"x-ladon":gn(o).toString("base64"),"x-argus":Z(o).toString("base64"),"x-helios":eo(o),"x-medusa":Qi(f,a,o,i),"x-tt-dt":""};return a||delete d["x-ss-stub"],{url:f,headers:d,body:a}}function ro(r){return typeof r=="string"?Lt(r)?.fallback_api||r:Array.isArray(r)?fe(r[0]):fe(r?.fallback_api)}function no(r){let e=S.from(fe(r).replace(/-/g,"+").replace(/_/g,"/"),"base64");if(e.length<3)throw new Error("spade_a too short");let t=e.length-(e[0]^e[1]^e[2])+47;if(t=Math.min(t,e.length-1),t<33)throw new Error("spade_a key length invalid");let n=S.from(e.subarray(1,1+t)),i=85,o=246;for(let c=0;c<t;c+=1){let s=n[c],u=c&1?i:o;c&1?i=s:o=s;let f=c.toString(2).split("1").length-1;n[c]=-21-f+(u^s)&255}let a=n.subarray(1,33).toString("ascii");if(!/^[0-9a-f]{32}$/i.test(a))throw new Error("App \u89C6\u9891\u5BC6\u94A5\u683C\u5F0F\u65E0\u6548");return S.from(a,"hex")}function io(r,e){let t=fe(r);if(!t)return"";let n=S.from(t,"base64");if(n.length<5)throw new Error("spade URL ciphertext too short");if(n[0]!==168||n[2]!==1||n[3]!==0)throw new Error("spade URL header format error");let i=Math.floor((n.length-4)/16)*16;if(!i)throw new Error("spade URL ciphertext has no complete block");let o=S.from("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58","hex"),a=K.createHash("sha512").update(e).digest(),c=K.createHash("sha512").update(S.concat([a,o])).digest(),s=K.createDecipheriv("aes-128-cbc",c.subarray(0,16),c.subarray(16,32));s.setAutoPadding(!1);let u=S.concat([s.update(n.subarray(4,4+i)),s.final()]);if(u.length){let f=u[u.length-1];f>=1&&f<=16&&f<=u.length&&(u=u.subarray(0,u.length-f))}for(;u.length&&u[u.length-1]===0;)u=u.subarray(0,u.length-1);return u.toString("utf8")}function lt(r,e){let t;try{t=new dn(r)}catch{throw Object.assign(new Error("App \u7247\u6E90\u5730\u5740\u683C\u5F0F\u65E0\u6548"),{code:"INVALID_RESPONSE"})}if(t.protocol!=="https:"||t.username||t.password||t.port&&t.port!=="443"||!e.some(n=>t.hostname===n||t.hostname.endsWith(`.${n}`)))throw Object.assign(new Error("App \u7247\u6E90\u8FD4\u56DE\u4E86\u4E0D\u53D7\u652F\u6301\u7684\u670D\u52A1\u5730\u5740"),{code:"SECURITY_BLOCKED"});return t.href}async function Pe(r,e,t){let n=lt(r,["fqnovel.com","snssdk.com"]);for(let i=0;i<=3;i++){if(globalThis.__hongguoCancelled)throw Object.assign(new Error("\u5DF2\u53D6\u6D88\u53D6\u6D41"),{code:"CANCELLED"});let o=Math.min(12e3,t-Date.now());if(o<=0)throw Object.assign(new Error("App \u63A5\u53E3\u8D85\u65F6"),{code:"ETIMEDOUT"});let a=await fetch(n,{method:e.method||"GET",headers:e.headers,body:e.data?S.from(e.data).toString("utf8"):void 0,redirect:"manual",timeoutMs:o});if([301,302,303,307,308].includes(a.status)){let u=a.headers&&(typeof a.headers.get=="function"?a.headers.get("location"):a.headers.location);if(e.method==="POST"||!u)throw Object.assign(new Error("App \u63A5\u53E3\u8DF3\u8F6C\u5F02\u5E38"),{code:"SECURITY_BLOCKED"});n=lt(new dn(u,n).href,["fqnovel.com","snssdk.com"]);continue}if(a.status!==200)throw Object.assign(new Error("App \u63A5\u53E3\u8BF7\u6C42\u5931\u8D25"),{code:"HTTP_"+a.status});let c=await a.text();if(!c||!c.trim())throw Object.assign(new Error("App 接口返回空正文"),{code:"EMPTY_RESPONSE",category:"invalid_resp"});if(c.length>(/^https:\/\/reading\.snssdk\.com\/reading\/bookapi\/(search\/tab|bookmall\/(tab|cell\/change))\/v[?]/.test(n)||/^https:\/\/reading\.snssdk\.com\/novel\/player\/video_detail\/v1\/[?]/.test(n)?12:2)*1024*1024)throw Object.assign(new Error("App \u63A5\u53E3\u54CD\u5E94\u65E0\u6548"),{code:"INVALID_RESPONSE"});let s=Lt(c);if(!s||typeof s!="object")throw Object.assign(new Error("App \u63A5\u53E3\u54CD\u5E94\u65E0\u6548"),{code:"INVALID_RESPONSE"});return s}throw Object.assign(new Error("App \u63A5\u53E3\u8DF3\u8F6C\u8FC7\u591A"),{code:"SECURITY_BLOCKED"})}const appVideoModels = new Map();
let preferredAppModelRoute = null;
let preferredAppModelUntil = 0;
const appModelRoutes = [
  { url: xn, single: false },
  { url: 'https://reading.snssdk.com/novel/player/multi_video_model/v1/', single: false },
  { url: 'https://reading.snssdk.com/novel/player/video_model/v1/', single: true },
  { url: 'https://api5-normal.fqnovel.com/novel/player/multi_video_model/v1/', single: false }
];
function appModelExpiry(model, entry = {}) {
  const times = [entry.expire_time, model.__hongguoExpiresAt, model.url_expire].map(value => {
    const number = Number(value);
    if (!Number.isSafeInteger(number) || number < 1000000000) return 0;
    return number < 1000000000000 ? number * 1000 : number;
  }).filter(value => value > 0 && value <= 8640000000000000);
  return times.length ? Math.min(...times) : 0;
}
async function requestAppVideoModel(videoId, device, deadline) {
  const preferred = preferredAppModelUntil > Date.now() ? preferredAppModelRoute : null;
  const routes = preferred ? [preferred, ...appModelRoutes.filter(route => route !== preferred)] : appModelRoutes;
  let lastError;
  const biz = { detail_page_version: 0, device_level: 3, disable_digg_stat: false, need_all_video_definition: true, need_mp4_align: false, use_os_player: false, use_server_dns: false, video_platform: 1024 };
  for (const route of routes) {
    if (globalThis.__hongguoCancelled) throw Object.assign(new Error('播放请求已取消'), { code: 'CANCELLED' });
    if (Date.now() >= deadline) break;
    try {
      const body = route.single ? { video_id: videoId, content_type: 1, biz_param: biz } : { biz_param: biz, mixed_video_id_map: { 1004: [videoId] } };
      const signed = Ht(JSON.stringify(body), route.url, {}, device);
      const response = await Pe(signed.url, { method: 'POST', headers: signed.headers, data: signed.body }, Math.min(deadline, Date.now() + 3500));
      if (Number(response.Code || response.code || 0) !== 0) throw Object.assign(new Error('官方接口暂未提供本集播放信息'), { code: 'BUSINESS_REJECTED' });
      if (!response.data || typeof response.data !== 'object') throw Object.assign(new Error('官方播放响应缺少数据'), { code: 'INVALID_RESPONSE' });
      const entry = route.single ? response.data : response.data[videoId];
      const model = typeof entry?.video_model === 'string' ? Lt(entry.video_model) : entry?.video_model;
      if (!model) throw Object.assign(new Error('官方接口未返回所选分集'), { code: entry?.video_model ? 'INVALID_RESPONSE' : 'MISSING_MODEL' });
      model.__hongguoExpiresAt = appModelExpiry(model, entry);
      preferredAppModelRoute = route;
      preferredAppModelUntil = Date.now() + 5 * 60 * 1000;
      return model;
    } catch (error) {
      lastError = error;
      const recoverable = ['MISSING_MODEL', 'EMPTY_RESPONSE', 'RESPONSE_NOT_UTF8', 'INVALID_RESPONSE', 'HTTP_0', 'HTTP_404', 'HTTP_405', 'HTTP_408', 'HTTP_500', 'HTTP_502', 'HTTP_503', 'HTTP_504', 'ETIMEDOUT', 'DNS', 'TIMEOUT', 'CONNECTION'].includes(error.code)
        || ['dns_error', 'network_timeout', 'conn_refused'].includes(error.category);
      if (!recoverable || globalThis.__hongguoCancelled) throw error;
      if (route === preferredAppModelRoute) { preferredAppModelRoute = null; preferredAppModelUntil = 0; }
    }
  }
  throw Object.assign(lastError || new Error('官方播放接口请求超时'), { code: lastError?.code || 'ETIMEDOUT', routesExhausted: true });
}
async function oo(r, e = {}) {
  const t = Ri(e.quality);
  r = String(r || '');
  if (!/^\d{1,30}$/.test(r)) throw new Error('分集编号无效');
  const n = Math.min(Date.now() + 12000, e.deadline || Infinity);
  const device = await Ot(n);
  const cacheKey = JSON.stringify([device.iid, device.device_id, device.cdid, r]);
  if (e.refreshModel) appVideoModels.delete(cacheKey);
  const cached = appVideoModels.get(cacheKey);
  const reusable = cached && cached.expiresAt > Date.now() + 5000;
  const u = reusable ? cached.model : await requestAppVideoModel(r, device, n);
  let f = [], h;
  try {
    f = ln(u, r, t);
    if (f.length && !reusable) {
      const expiresAt = Math.min(appModelExpiry(u) || Date.now() + 30000, Date.now() + 300000);
      if (expiresAt > Date.now() + 5000) {
        if (!appModelExpiry(u)) u.__hongguoExpiresAt = expiresAt;
        appVideoModels.delete(cacheKey);
        appVideoModels.set(cacheKey, { model: u, expiresAt });
        while (appVideoModels.size > 8) appVideoModels.delete(appVideoModels.keys().next().value);
        f = ln(u, r, t);
      }
    }
  } catch (error) { h = error; }
if(f.length&&!e.includeFallback)return{...f[0],variants:f};let d=ro(u.fallback_api);if(d&&u.dynamic_video&&!Object.keys(u.video_list||{}).length&&(d=lt(d,["fqnovel.com","snssdk.com"]),d=d.replace(/([?&])force_fids=[^&]*(&?)/,(y,I,F)=>F?I:""),d=/[?&]format_type=/.test(d)?d.replace(/([?&]format_type=)[^&]*/,"$1mp4"):d+(d.includes("?")?"&":"?")+"format_type=mp4"),d)try{let y=await Pe(d,{headers:{"User-Agent":dt}},n);if([y,y.video_info].some(F=>Number(F?.Code||F?.code||0)!==0))throw Object.assign(new Error("App \u63A5\u53E3\u6682\u672A\u63D0\u4F9B\u672C\u96C6\u64AD\u653E\u4FE1\u606F"),{code:"BUSINESS_REJECTED"});let I=y?.video_info?.data;if(!I)throw Object.assign(new Error("App \u63A5\u53E3\u672A\u8FD4\u56DE\u672C\u96C6\u7247\u6E90\u6A21\u578B"),{code:"MISSING_MODEL"});f.push(...ln(I,r,t))}catch(y){h=y}let x=new Set;if(f=f.filter(y=>{let I=y.url+":"+(y.contentKey||"");return x.has(I)?!1:(x.add(I),!0)}),f.length)return{...f[0],variants:f};throw h||Object.assign(new Error("App \u63A5\u53E3\u672A\u8FD4\u56DE\u672C\u96C6\u7247\u6E90\u5730\u5740"),{code:"MISSING_MODEL"})}
function ln(model, videoId, downloadQuality) {
  const entries = Object.values(model?.video_list || {}).filter(item => item && (item.main_url || item.backup_url || Array.isArray(item.backup_url_list))).map(item => {
    const meta = item.video_meta || {};
    const codec = fe(item.codec_type || meta.codec_type).toLowerCase();
    const codecRank = ['h264', 'avc', 'avc1'].includes(codec) ? 0 : ['hevc', 'h265', 'hvc1', 'hev1', 'bytevc1'].includes(codec) ? 1 : !codec && ['mp4', 'mpeg'].includes(fe(item.vtype).toLowerCase()) ? 2 : 3;
    const [width, height] = [[item.vwidth, item.vheight], [item.width, item.height], [meta.vwidth, meta.vheight], [meta.width, meta.height]].map(pair => pair.map(Number)).find(pair => pair.every(value => Number.isFinite(value) && value > 0)) || [0, 0];
    const label = fe(item.quality_desc || item.definition || meta.definition);
    const pixels = width > 0 && height > 0 ? Math.min(width, height) : Number(label.match(/\d+/)?.[0] || 0);
    return { item, codec, codecRank, pixels, quality: pixels > 0 ? pixels + 'p' : '', width, height };
  }).filter(value => value.codecRank < 3 && Di(value, downloadQuality)).sort((left, right) => downloadQuality === 'auto' ? right.pixels - left.pixels || left.codecRank - right.codecRank : Math.min(left.width, left.height) - Math.min(right.width, right.height) || left.codecRank - right.codecRank);
  if (!entries.length) throw new Error(downloadQuality === 'auto' ? '本集暂未提供兼容的 H.264/HEVC 片源' : '本集暂未提供满足下载清晰度的片源');
  const r = model, e = videoId, t = downloadQuality, n = entries;
let i,o=[],a=new Set;for(let c of n)try{let s=c.item.spade_a||c.item.encrypt_info?.spade_a,u=s?no(s):null;for(let f of[c.item.main_url,c.item.backup_url,c.item.backup_url_1,c.item.backup_url_2,c.item.backup_url_3,...Array.isArray(c.item.backup_url_list)?c.item.backup_url_list:[]])if(!(typeof f!="string"||!f))try{let h=r.key_seed?io(f,S.from(r.key_seed,"base64")):/^https:\/\//i.test(cn(f))?cn(f):S.from(f,"base64").toString("utf8"),d=lt(h,["qznovelvod.com","fqnovelvod.com","douyinvod.com"]),x=u?u.toString("hex"):null,y=`${d}:${x||""}`;if(a.has(y))continue;a.add(y),o.push({url:d,contentKey:x,codec:c.codec==="bytevc1"?"hevc":c.codec||"auto",source:"app",vid:e,expiresAt:appModelExpiry(r),userAgent:dt,referer:"https://novelquickapp.com/",mediaBytes:Math.max(0,Number(c.item.size||c.item.video_meta?.size||0)),quality:c.quality,width:c.width,height:c.height})}catch(h){i=h}}catch(s){i=s}if(o.length)return o;throw i?.code==="SECURITY_BLOCKED"?i:Object.assign(new Error("\u672C\u96C6\u7247\u6E90\u5730\u5740\u6216\u5BC6\u94A5\u65E0\u6CD5\u89E3\u6790"),{code:"INVALID_RESPONSE"})}
var he={...yn,version_code:"73932",version_name:"7.3.9.32",manifest_version_code:"73932",update_version_code:"73932",pv_player:"73932"},Ae;function ao(){let r=K.randomBytes(16);r[6]=r[6]&15|64,r[8]=r[8]&63|128;let e=r.toString("hex");return[e.slice(0,8),e.slice(8,12),e.slice(12,16),e.slice(16,20),e.slice(20)].join("-")}async function Ot(r=1/0){if(globalThis.__hongguoCachedDevice&&/^\d{10,24}$/.test(fe(globalThis.__hongguoCachedDevice.iid))&&/^\d{10,24}$/.test(fe(globalThis.__hongguoCachedDevice.device_id))){globalThis.__hongguoCachedDevice={...globalThis.__hongguoCachedDevice,...he,iid:fe(globalThis.__hongguoCachedDevice.iid),device_id:fe(globalThis.__hongguoCachedDevice.device_id),cdid:fe(globalThis.__hongguoCachedDevice.cdid)||ao()};return globalThis.__hongguoCachedDevice;}return Ae||(Ae=(async()=>{let e=ao(),t={aid:8662,app_name:"novelread",package:"com.phoenix.read",app_version:he.version_name,version_code:73932,update_version_code:73932,manifest_version_code:73932,sdk_version:"6.18.0",device_platform:"android",os:"Android",os_version:he.os_version,os_api:Number(he.os_api),device_model:he.device_type,device_brand:he.device_brand,device_manufacturer:"Xiaomi",density_dpi:Number(he.dpi),display_density:"mdpi",resolution:he.resolution.replace("*","x"),language:"zh",timezone:8,access:"wifi",channel:he.channel,cdid:e,openudid:K.randomBytes(8).toString("hex")},n=await Pe("https://log.snssdk.com/service/2/device_register/?aid=8662&app_name=novelread",{method:"POST",headers:{"Content-Type":"application/json; charset=utf-8","User-Agent":dt},data:JSON.stringify({magic_tag:"ss_app_log",header:t,_gen_time:Date.now()})},Math.min(Date.now()+12e3,r)),i=fe(n.install_id_str),o=fe(n.device_id_str);if(!/^\d{10,24}$/.test(i)||!/^\d{10,24}$/.test(o))throw Object.assign(new Error("\u65E0\u6CD5\u521D\u59CB\u5316\u5B98\u65B9\u4F1A\u8BDD"),{code:"GUEST_REGISTRATION_FAILED"});let dev={...he,iid:i,device_id:o,cdid:e};globalThis.__hongguoCachedDevice=dev;if(typeof __native_save_device==="function"){try{__native_save_device(JSON.stringify(dev));}catch(_){}}return dev;})().catch(e=>{throw Ae=null,e})),Ae}async function co(r,e={},t=!1){t&&(Ae=null,delete globalThis.__hongguoCachedDevice);let deadline=Math.min(Date.now()+12e3,e.deadline||1/0),n=await Ot(deadline),i={query:r,count:0,offset:e.offset||0,tab_type:e.fallbackToGeneral?11:29,tab_name:e.fallbackToGeneral?"":"feed",search_source:1,use_correct:!1,use_lynx:!1,user_is_login:0,bookshelf_search_plan:4,bookstore_tab:16,is_first_enter_search:!e.offset};e.passback&&(i.passback=e.passback),e.searchId&&(i.search_id=e.searchId);let o=Ht(null,"https://reading.snssdk.com/reading/bookapi/search/tab/v",i,n),a=await Pe(o.url,{headers:{...o.headers,lc:"101"}},deadline);if(Number(a.code)!==0||!Array.isArray(a.search_tabs))throw Object.assign(new Error("\u5B98\u65B9\u641C\u7D22\u672A\u8FD4\u56DE\u6709\u6548\u7ED3\u679C"),{code:"SEARCH_REJECTED",category:"business_reject"});return a}async function so({seriesId:r,videoId:e,startMs:t=0,durationMs:n,cursor:i=""}){if(!/^\d{10,30}$/.test(String(r))||!/^\d{10,30}$/.test(String(e)))throw new Error("\u5F39\u5E55\u5206\u96C6\u7F16\u53F7\u65E0\u6548");let o={comment_source:601,server_channel:1e3,group_id:String(e),group_type:30,comment_type:20,sort:1,business_param:{book_id:String(r),start_offset_time:t,playlet_item_duration:n},count:90,cursor:String(i),aid:8662,compliance_status:0},a=await Ot(),c=Ht(JSON.stringify(o),"https://reading.snssdk.com/novel/commentapi/comment/list/"+e+"/v1/",{},a);return Pe(c.url,{method:"POST",headers:{...c.headers,lc:"101"},data:c.body},Date.now()+5e3)}mn.exports={resetGuestSession:function(){Ae=null;appVideoModels.clear();delete globalThis.__hongguoCachedDevice;},fetchAppDetailRaw:async function(id){const dev=await Ot();const signed=Ht(JSON.stringify({series_id:String(id)}),"https://reading.snssdk.com/novel/player/video_detail/v1/",{},dev);const result=await Pe(signed.url,{method:"POST",headers:{...signed.headers,lc:"101"},data:signed.body},Date.now()+12000);if(Number(result.code||0)!==0)throw Object.assign(new Error("官方详情接口暂不可用，请重试"),{code:"DETAIL_REJECTED"});return result.data?.video_data},fetchAppPlayUrl:oo,fetchAppSearchRaw:co,fetchAppDanmakuRaw:so,fetchAppDiscoveryRaw:async function(path,params){if(!["/reading/bookapi/search/cue/v","/reading/bookapi/search/suggest/v","/reading/bookapi/plan/v","/reading/bookapi/bookmall/tab/v","/reading/bookapi/bookmall/cell/change/v"].includes(path))throw Object.assign(new Error("不支持的官方接口"),{code:"SECURITY_BLOCKED"});const device=await Ot();const signed=Ht(null,"https://reading.snssdk.com"+path,params,device);const result=await Pe(signed.url,{headers:{...signed.headers,lc:"101"}},Date.now()+12000);if(!result||String(result.code??result.status_code)!=="0")throw Object.assign(new Error("官方发现接口暂不可用，请重试"),{code:"DISCOVERY_REJECTED"});return result}}});var wn=z((Do,vn)=>{var{fetchAppSearchRaw:bn}=pt();function fo(r){let e=[],t=new Set;let tabs=Array.isArray(r)?r:(r?[r]:[]);for(let m of tabs){for(let n of m.data||[]){let i=Array.isArray(n.video_data)?n.video_data:[];for(let o of i){let a=o.video_detail||{},c=String(a.series_id_str||o.series_id||a.series_id||"");if(!/^\d{10,30}$/.test(c)||t.has(c))continue;let s=String(a.series_title||o.title||"").trim();if(!s)continue;t.add(c);let u=Number(a.episode_cnt||o.episode_cnt||0);e.push({vod_id:c,vod_name:s,vod_pic:cleanCoverUrl(String(a.series_cover||o.cover||"")),vod_remarks:u>0?"全"+u+"集":"",vod_content:String(a.series_intro||""),vod_total:u,content_type:Number(a.content_type||o.content_type||0)})}}}return e}function pickTab(response, general) {
  const tabs = response.search_tabs || [];
  const type = general ? 11 : 29;
  return tabs.find(tab => Number(tab.tab_type) === type)
    || tabs.find(tab => general ? tab.title === '综合' : ['剧集', '短剧'].includes(tab.title))
    || (general ? tabs.find(tab => fo(tab).length > 0) : undefined);
}
function toPage(response, tab, offset, general) {
  const list = fo(tab);
  const next = Number(tab?.next_offset || 0);
  const more = tab?.has_more === true;
  if (more && (!Number.isSafeInteger(next) || next <= offset)) {
    throw Object.assign(new Error('官方搜索游标未推进，请重新搜索'), { code: 'INVALID_SEARCH_CURSOR' });
  }
  return { list, hasMore: more, cursor: {
    offset: next, passback: String(tab?.passback || ''), searchId: String(tab?.search_id || ''), fallbackToGeneral: general
  } };
}
async function uo(query, cursor = {}) {
  const deadline = Date.now() + 45000;
  async function request(value) {
    value = { ...value, deadline };
    try { return await bn(query, value); }
    catch (error) {
      if (globalThis.__hongguoCancelled) throw error;
      const renew = ['INVALID_RESPONSE', 'SEARCH_REJECTED'].includes(error.code);
      const transient = ['HTTP_0', 'HTTP_408', 'HTTP_500', 'HTTP_502', 'HTTP_503', 'HTTP_504', 'ETIMEDOUT', 'EMPTY_RESPONSE'].includes(error.code)
        || ['dns_error', 'network_timeout', 'conn_refused'].includes(error.category);
      if (!renew && !transient) throw error;
      return await bn(query, value, renew);
    }
  }
  const response = await request(cursor);
  const offset = Number(cursor.offset || 0);
  const general = cursor.fallbackToGeneral === true;
  const tab = pickTab(response, general);
  const result = toPage(response, tab, offset, general);
  if (general || offset || result.list.length || globalThis.__hongguoCancelled) {
    if (!tab) throw Object.assign(new Error('官方搜索未返回短剧数据分类，请导出诊断报告'), { code: 'SEARCH_TAB_MISSING' });
    return result;
  }
  const fallback = await request({ fallbackToGeneral: true });
  const fallbackTab = pickTab(fallback, true);
  const fallbackResult = toPage(fallback, fallbackTab, 0, true);
  if (fallbackResult.list.length) return fallbackResult;
  if (!tab) throw Object.assign(new Error('官方搜索未返回短剧数据分类，请导出诊断报告'), { code: 'SEARCH_TAB_MISSING' });
  return result;
}
vn.exports={fetchAppSearchPage:uo}});var En=z((No,_n)=>{var{fetchAppDanmakuRaw:ho}=pt();async function lo(r,e,t){let n=/^hongguo:(\d{10,30}):(\d{10,30})$/.exec(String(r));if(!n||!Number.isSafeInteger(e)||!Number.isSafeInteger(t)||e<0||e>=t||t>864e5)throw new Error("\u5F39\u5E55\u5206\u96C6\u6216\u65F6\u95F4\u8303\u56F4\u65E0\u6548");let i=Math.min(e+3e4,t),o=await ho({seriesId:n[1],videoId:n[2],startMs:e,durationMs:t});if(Number(o.code)!==0||!Array.isArray(o.data?.data_list))throw new Error("\u5B98\u65B9\u5F39\u5E55\u6682\u4E0D\u53EF\u7528");let a=String(o.data.common_list_info?.cursor||"");if(a){let u;try{u=JSON.parse(a)}catch{}if(u&&Number(u.start_offset_time)!==e)throw new Error("\u5B98\u65B9\u5F39\u5E55\u65F6\u95F4\u8303\u56F4\u4E0D\u7B26")}let c=new Set,s=[];for(let u of o.data.data_list){let f=u?.comment;if(String(f?.common?.group_id||"")!==n[2])continue;let h=String(f.comment_id||""),d=Number(f.expand?.offset_time),x=f.common.content?.text;if(!h||h.length>120||c.has(h)||!Number.isSafeInteger(d)||d<e||d>=i||typeof x!="string")continue;let y=Array.from(x.replace(/[\x00-\x1f\x7f-\x9f\u2028\u2029]/g," ").trim()).slice(0,180).join("");if(y&&(c.add(h),s.push({id:h,timeMs:d,text:y,color:"#FFFFFF"}),s.length>=90))break}return s.sort((u,f)=>u.timeMs-f.timeMs),{episodeId:r,startMs:e,nextMs:i,items:s}}_n.exports={fetchAppDanmakuPage:lo}});var go=z((To,Bn)=>{var{fetchAppPlayUrl:po}=pt(),{fetchAppSearchPage:xo}=wn(),{fetchAppDanmakuPage:yo}=En();Bn.exports={resetGuestSession:pt().resetGuestSession,fetchAppDetailRaw:pt().fetchAppDetailRaw,fetchAppPlayUrl:po,fetchAppSearchPage:xo,fetchAppDanmakuPage:yo,fetchAppDiscoveryRaw:pt().fetchAppDiscoveryRaw}});return go();})();

/*! buffer
The MIT License (MIT)

Copyright (c) Feross Aboukhadijeh, and other contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/
/*! base64-js
The MIT License (MIT)

Copyright (c) 2014 Jameson Little

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/
/*! ieee754
Copyright 2008 Fair Oaks Labs, Inc.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/
/*! crypto-js
# License

[The MIT License (MIT)](http://opensource.org/licenses/MIT)

Copyright (c) 2009-2013 Jeff Mott
Copyright (c) 2013-2016 Evan Vosberg

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/
/*! url-parse
The MIT License (MIT)

Copyright (c) 2015 Unshift.io, Arnout Kazemier,  the Contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


*/
/*! querystringify
The MIT License (MIT)

Copyright (c) 2015 Unshift.io, Arnout Kazemier,  the Contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


*/
/*! requires-port
The MIT License (MIT)

Copyright (c) 2015 Unshift.io, Arnout Kazemier,  the Contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


*/
/*! GPL-3.0-only license text
                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU General Public License is a free, copyleft license for
software and other kinds of works.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
the GNU General Public License is intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.  We, the Free Software Foundation, use the
GNU General Public License for most of our software; it applies also to
any other work released this way by its authors.  You can apply it to
your programs, too.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  To protect your rights, we need to prevent others from denying you
these rights or asking you to surrender the rights.  Therefore, you have
certain responsibilities if you distribute copies of the software, or if
you modify it: responsibilities to respect the freedom of others.

  For example, if you distribute copies of such a program, whether
gratis or for a fee, you must pass on to the recipients the same
freedoms that you received.  You must make sure that they, too, receive
or can get the source code.  And you must show them these terms so they
know their rights.

  Developers that use the GNU GPL protect your rights with two steps:
(1) assert copyright on the software, and (2) offer you this License
giving you legal permission to copy, distribute and/or modify it.

  For the developers' and authors' protection, the GPL clearly explains
that there is no warranty for this free software.  For both users' and
authors' sake, the GPL requires that modified versions be marked as
changed, so that their problems will not be attributed erroneously to
authors of previous versions.

  Some devices are designed to deny users access to install or run
modified versions of the software inside them, although the manufacturer
can do so.  This is fundamentally incompatible with the aim of
protecting users' freedom to change the software.  The systematic
pattern of such abuse occurs in the area of products for individuals to
use, which is precisely where it is most unacceptable.  Therefore, we
have designed this version of the GPL to prohibit the practice for those
products.  If such problems arise substantially in other domains, we
stand ready to extend this provision to those domains in future versions
of the GPL, as needed to protect the freedom of users.

  Finally, every program is threatened constantly by software patents.
States should not allow patents to restrict development and use of
software on general-purpose computers, but in those that do, we wish to
avoid the special danger that patents applied to a free program could
make it effectively proprietary.  To prevent this, the GPL assures that
patents cannot be used to render the program non-free.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Use with the GNU Affero General Public License.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU Affero General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the special requirements of the GNU Affero General Public License,
section 13, concerning interaction through a network will apply to the
combination as such.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU General Public License from time to time.  Such new versions will
be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If the program does terminal interaction, make it output a short
notice like this when it starts in an interactive mode:

    <program>  Copyright (C) <year>  <name of author>
    This program comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
    This is free software, and you are welcome to redistribute it
    under certain conditions; type `show c' for details.

The hypothetical commands `show w' and `show c' should show the appropriate
parts of the General Public License.  Of course, your program's commands
might be different; for a GUI interface, you would use an "about box".

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU GPL, see
<https://www.gnu.org/licenses/>.

  The GNU General Public License does not permit incorporating your program
into proprietary programs.  If your program is a subroutine library, you
may consider it more useful to permit linking proprietary applications with
the library.  If this is what you want to do, use the GNU Lesser General
Public License instead of this License.  But first, please read
<https://www.gnu.org/licenses/why-not-lgpl.html>.

*/
(function () {
  const existingPlay = spider.play;
  spider.play = async function (flag, id, flags) {
    const target = String(id || '').replace(/^hongguo:/, '');
    const flagValues = Array.isArray(flags) ? flags : [];
    const seriesId = String(flagValues.find(value => value && typeof value === 'object' && value.seriesId)?.seriesId || '');
    const publicMatch = /\/video\/public\/(\d{10,})\//.exec(target);
    const match = /\/player\/([^/?#]+)\/(\d+)(?:[/?#]|$)/.exec(target) || /^(\d+)_(\d{10,})$/.exec(target)
      || (publicMatch ? ['', /^\d{10,}$/.test(seriesId) ? seriesId : '', publicMatch[1]] : null);
    if (!match) {
      const indexed = /^(\d+)[/_](\d{1,5})$/.exec(target);
      if (!indexed) return existingPlay(flag, id, flags);
      let detail = await fetchAppDetail(indexed[1]);
      let episode = detail && detail.video_list && detail.video_list[Number(indexed[2]) - 1];
      let exactId = episode && String(episode.vid || episode.video_id || "");
      if (!/^\d+$/.test(exactId || "")) {
        try {
          const fullDetail = await spider.detail(indexed[1]);
          const vod = fullDetail && Array.isArray(fullDetail.list) && fullDetail.list[0];
          const playUrl = (vod && vod.vod_play_url) || "";
          if (playUrl) {
            const epNum = Number(indexed[2]);
            const entries = playUrl.split("#");
            let resolvedUrl = "";
            for (let i = 0; i < entries.length; i++) {
              const item = entries[i];
              const parts = item.split("$");
              if (parts.length >= 2) {
                const numMatch = parts[0].match(/(\d+)/);
                if (numMatch && Number(numMatch[1]) === epNum) {
                  resolvedUrl = parts[1];
                  break;
                }
              }
            }
            if (!resolvedUrl && epNum > 0 && epNum <= entries.length) {
              const parts = entries[epNum - 1].split("$");
              if (parts.length >= 2) resolvedUrl = parts[1];
            }
            if (resolvedUrl && resolvedUrl !== target && !/^\d+[/_]\d{1,5}$/.test(resolvedUrl)) {
              return spider.play(flag, resolvedUrl, flags);
            }
            const exactVidMatch = /\/player\/[^/?#]+\/(\d+)/.exec(resolvedUrl || "") || /^(\d{10,})$/.exec(resolvedUrl || "");
            if (exactVidMatch) {
              exactId = exactVidMatch[1];
            }
          }
        } catch (_) {}
        if (!/^\d+$/.test(exactId || "")) {
          detail = await fetchAppDetail(indexed[1]);
          episode = detail && detail.video_list && detail.video_list[Number(indexed[2]) - 1];
          exactId = episode && String(episode.vid || episode.video_id || "");
        }
      }
      if (!/^\d+$/.test(exactId || "")) return { parse: 0, url: "", header: {}, error: "MISSING_EPISODE" };
      return spider.play(flag, BASE_URL + "/player/" + indexed[1] + "/" + exactId, flags);
    }
    const vid = match[2];
    const danmakuId = match[1] ? 'hongguo:' + match[1] + ':' + vid : '';
    const avoidedUrl = Array.isArray(flags) ? String(flags.find(value => value && typeof value === 'object' && value.avoidUrl)?.avoidUrl || '') : '';
    const qualityValue = Array.isArray(flags) ? Number(flags.find(value => value && typeof value === 'object' && 'quality' in value)?.quality || 0) : 0;
    const requestedQuality = Number.isFinite(qualityValue) && qualityValue > 0 ? Math.round(qualityValue) : 0;
    const preferredQuality = requestedQuality || 1080;
    function streamQuality(value) {
      const width = Number(value.width), height = Number(value.height);
      return width > 0 && height > 0 ? Math.round(Math.min(width, height)) : Number(String(value.quality || '').match(/\d+/)?.[0] || 0);
    }
    function qualityRank(value) {
      const q = streamQuality(value);
      if (!q) return [3, 0];
      if (q === preferredQuality) return [0, 0];
      const preferLower = requestedQuality > 0 && requestedQuality < 1080;
      const preferredSide = preferLower ? q < preferredQuality : q > preferredQuality;
      return [preferredSide ? 1 : 2, Math.abs(q - preferredQuality)];
    }
    let deadline = Date.now() + 30000;
    function mediaHeaders(value) {
      const headers = { ...(value.header || { 'User-Agent': value.userAgent }) };
      for (const key of Object.keys(headers)) if (key.toLowerCase() === 'referer') delete headers[key];
      return headers;
    }
    async function readable(value) {
      if (globalThis.__hongguoCancelled || !value || !value.url || Date.now() >= deadline) return false;
      const expiresAt = Number(value.expiresAt);
      if (Number.isSafeInteger(expiresAt) && expiresAt > 0 && expiresAt <= Date.now() + 5000) { mediaFailure = 'MEDIA_URL_EXPIRED'; return false; }
      try {
        const response = await fetch(value.url, { method: 'HEAD', headers: mediaHeaders(value), timeoutMs: Math.min(5000, deadline - Date.now()) });
        const contentType = response.headers && (typeof response.headers.get === 'function' ? response.headers.get('content-type') : response.headers['content-type']);
        if (![200, 206].includes(response.status)) { mediaFailure = 'MEDIA_HTTP_' + response.status; return false; }
        if (!/^video\//i.test(contentType || '')) { mediaFailure = 'MEDIA_TYPE_INVALID'; return false; }
        return true;
      } catch (error) { mediaFailure = error.code || 'MEDIA_NETWORK'; return false; }
    }
    let lastCode = 'NO_STREAM';
    let mediaFailure = 'MEDIA_REJECTED';
    for (let attempt = 0; attempt < 2 && !globalThis.__hongguoCancelled && Date.now() < deadline; attempt++) {
      try {
        const model = await HongguoApp.fetchAppPlayUrl(vid, { deadline, refreshModel: attempt > 0 || Boolean(avoidedUrl), includeFallback: lastCode === 'MEDIA_REJECTED' });
        const variants = model.variants || [model];
        const qualities = [...new Set(variants.map(streamQuality).filter(value => value > 0))].sort((a, b) => b - a);
        const ordered = [...variants].sort((a, b) => {
          const left = qualityRank(a), right = qualityRank(b);
          return left[0] - right[0] || left[1] - right[1] || Number(a.url === avoidedUrl) - Number(b.url === avoidedUrl);
        });
        for (const candidates of [ordered]) {
          for (let index = 0; index < candidates.length;) {
            const group = [candidates[index++]];
            if (index < candidates.length && String(candidates[index].quality) === String(group[0].quality) && (candidates[index].url === avoidedUrl) === (group[0].url === avoidedUrl)) group.push(candidates[index++]);
            const candidate = await new Promise(resolve => {
              let remaining = group.length;
              for (const value of group) {
                Promise.resolve(String(value.vid) === vid && readable(value)).then(ok => {
                  if (ok) resolve(value);
                  if (--remaining === 0) resolve(null);
                }, () => { if (--remaining === 0) resolve(null); });
              }
            });
            if (!candidate) continue;
            const quality = streamQuality(candidate);
            return { parse: 0, url: candidate.url, header: mediaHeaders(candidate), decryptionKey: candidate.contentKey || '', mediaBytes: candidate.mediaBytes || 0, quality, qualities, expiresAt: Number.isSafeInteger(candidate.expiresAt) && candidate.expiresAt > 0 ? Math.min(candidate.expiresAt, Date.now() + 300000) : Date.now() + 30000, episodeId: vid, danmakuId };
          }
        }
        lastCode = 'MEDIA_REJECTED';
      } catch (error) {
        lastCode = error.code || 'MODEL_FAILED';
        if (error.routesExhausted || ['BUSINESS_REJECTED', 'SECURITY_BLOCKED', 'MISSING_MODEL', 'EMPTY_RESPONSE', 'RESPONSE_NOT_UTF8', 'HTTP_403', 'HTTP_429'].includes(lastCode)) break;
      }
    }
    return { parse: 0, url: '', header: {}, error: globalThis.__hongguoCancelled ? 'CANCELLED' : lastCode === 'MEDIA_REJECTED' ? mediaFailure : lastCode, episodeId: vid, danmakuId };
  };
})();

(function () {
  const searches = new Map();
  spider.search = async function (word, quick, page) {
    const query = String(word || '').trim().slice(0, 100);
    const pg = Math.max(1, Number.parseInt(page, 10) || 1);
    if (!query) return { page: pg, pagecount: pg, limit: 10, total: 0, list: [] };
    let state = searches.get(query);
    if (pg === 1 || !state || Date.now() - state.updated > 15 * 60 * 1000) {
      state = { pages: new Map(), cursors: new Map([[1, {}]]), updated: Date.now(), end: null };
      searches.delete(query);
      searches.set(query, state);
      while (searches.size > 8) searches.delete(searches.keys().next().value);
    }
    if (state.end !== null && pg > state.end) return { page: pg, pagecount: state.end, limit: 10, total: 0, list: [] };
    if (!state.cursors.has(pg) && !state.pages.has(pg)) {
      if (pg !== 2) throw new Error('搜索游标已过期，请从第一页重新搜索');
      await spider.search(query, quick, 1);
      state = searches.get(query);
    }
    if (!state.pages.has(pg)) {
      if (!state.cursors.has(pg)) return { page: pg, pagecount: pg, limit: 10, total: 0, list: [] };
      const result = await HongguoApp.fetchAppSearchPage(query, state.cursors.get(pg));
      const seen = new Set();
      for (const [number, previous] of state.pages) if (number < pg) for (const item of previous.list) seen.add(item.vod_id);
      const list = result.list.filter(item => !seen.has(item.vod_id));
      state.pages.set(pg, { page: pg, pagecount: result.hasMore ? pg + 1 : pg, limit: 10, total: 0, list });
      if (result.hasMore) state.cursors.set(pg + 1, result.cursor);
      if (!result.hasMore) state.end = pg;
    }
    state.updated = Date.now();
    return state.pages.get(pg);
  };
})();

spider.danmaku = function (id, startMs, durationMs) {
  return HongguoApp.fetchAppDanmakuPage(id, startMs, durationMs);
};

(function () {
  const states = new Map();
  const ttl = 2 * 60 * 60 * 1000;
  const api = HongguoApp.fetchAppDiscoveryRaw;
  const text = value => value == null ? '' : String(value).trim();
  const number = value => Math.max(0, Number.parseInt(value, 10) || 0);
  const failure = (message, code) => Object.assign(new Error(message), { code });
  const rankParams = (selected, sub) => ({
    scene: 10, from: 'video_ranklist', bookstore_tab_type: 26,
    selected_items: selected, sub_selected_items: sub,
    panel_selected_items: '', background_selected_items: ''
  });

  function videos(cells) {
    const found = [];
    const seen = new Set();
    function visit(cell) {
      if (!cell || typeof cell !== 'object') return;
      for (const video of cell.video_data || []) {
        const id = text(video.series_id_str || video.series_id);
        if (!/^\d{10,}$/.test(id) || !text(video.title) || video.disable_play === true || seen.has(id)) continue;
        seen.add(id);
        const metric = (video.secondary_info_list || []).map(item => text(item.content)).find(Boolean) || '';
        let rank = 0;
        try { rank = number(JSON.parse(video.recommend_info || '{}').rank); } catch (_) {}
        found.push({
          vod_id: id, vod_name: text(video.title), vod_pic: cleanCoverUrl(text(video.cover)),
          vod_content: text(video.video_desc), vod_remarks: number(video.episode_cnt) ? number(video.episode_cnt) + '集' : '',
          vod_episodes: number(video.episode_cnt), vod_metric: metric, vod_heat: metric,
          vod_views: (typeof video.show_play_cnt === 'boolean' ? '' : text(video.show_play_cnt)) || (number(video.play_cnt) ? text(video.play_cnt) : ''),
          vod_score: text(video.score), vod_rank: rank,
          vod_tag: text(video.sub_title)
        });
      }
      for (const child of cell.cell_data || []) visit(child);
    }
    for (const cell of cells || []) visit(cell);
    return found;
  }

  function container(cells) {
    return (cells || []).find(cell => cell && cell.cell_id_str && Array.isArray(cell.cell_data));
  }

  function selectedSubtitle(cell) {
    const outer = cell?.cell_selector?.outer_row?.items || [];
    const selected = outer.find(item => item.is_selected);
    const sub = selected?.sub_cell_selector?.outer_row?.items || [];
    return text(sub.find(item => item.is_selected)?.sub_title);
  }

  async function savePage(state, page, cell, data, params, minimum = 1) {
    if (!cell) throw failure('官方接口未返回剧集列表，请重试', 'INVALID_RESPONSE');
    const seen = new Set();
    let previousCount = 0;
    for (const [previous, value] of state.pages) {
      if (previous < page) {
        for (const row of value.list) seen.add(row.vod_id);
        previousCount += value.list.length;
      }
    }
    const previous = state.cursors.get(page);
    const list = [];
    let offset = number(data.next_offset ?? cell.next_offset);
    let hasMore = data.has_more !== false && cell.has_more !== false && offset > number(previous?.offset);
    let currentCell = cell;
    let currentData = data;

    function appendCell(c) {
      for (const row of videos([c])) {
        if (!seen.has(row.vod_id)) {
          seen.add(row.vod_id);
          const computedRank = state.isRanking
            ? (previousCount + list.length + 1)
            : (row.vod_rank || (number(previous?.offset) + list.length + 1));
          list.push({
            ...row, ...(state.category ? { vod_category: state.category } : {}),
            vod_rank: computedRank
          });
        }
      }
    }
    appendCell(cell);

    let rounds = 0;
    while (list.length < minimum && hasMore && rounds < 5) {
      rounds++;
      const nextParams = {
        ...params,
        cell_id: text(currentCell.cell_id_str || previous?.cell_id),
        offset: offset,
        session_id: text(currentData.session_id || currentCell.session_id),
        rank_version: text(currentData.rank_version || currentCell.rank_version),
        limit: 40,
        change_type: 1
      };
      let nextRes;
      try {
        nextRes = await api('/reading/bookapi/bookmall/cell/change/v', nextParams);
        if (!nextRes.data?.cell_view) throw failure('官方接口未返回剧集列表，请重试', 'INVALID_RESPONSE');
      } catch (error) {
        if (list.length) break;
        throw error;
      }
      const nextCell = nextRes.data.cell_view;
      const nextData = nextRes.data;
      const prevOff = offset;
      offset = number(nextData.next_offset ?? nextCell.next_offset);
      hasMore = nextData.has_more !== false && nextCell.has_more !== false && offset > prevOff;
      currentCell = nextCell;
      currentData = nextData;
      appendCell(nextCell);
    }

    hasMore = hasMore && list.length > 0;
    const result = {
      page, pagecount: hasMore ? page + 1 : page, hasMore, list,
      updatedText: selectedSubtitle(cell) || state.updatedText || ''
    };
    state.pages.set(page, result);
    state.updatedText = result.updatedText;
    state.updated = Date.now();
    if (hasMore) state.cursors.set(page + 1, {
      ...params, cell_id: text(currentCell.cell_id_str || previous?.cell_id), offset,
      session_id: text(currentData.session_id || currentCell.session_id), rank_version: text(currentData.rank_version || currentCell.rank_version)
    });
    return result;
  }

  async function paged(key, rawPage, first) {
    const page = Math.max(1, number(rawPage));
    let state = states.get(key);
    if (page === 1) {
      state = { pages: new Map(), cursors: new Map(), updated: Date.now() };
      states.delete(key);
      states.set(key, state);
      while (states.size > 64) states.delete(states.keys().next().value);
      const initial = await first();
      state.category = initial.category;
      state.isRanking = Boolean(initial.isRanking || key.startsWith('hongguo-app:'));
      return await savePage(state, page, initial.cell, initial.data || {}, initial.params, initial.minimum);
    }
    if (state && state.pages.has(page)) return state.pages.get(page);

    // 游标自愈保护：当状态缺失、超时或缺失对应页码游标时，自动重新初始化并建立前序游标
    if (!state || Date.now() - state.updated > ttl || !state.cursors.has(page)) {
      state = { pages: new Map(), cursors: new Map(), updated: Date.now() };
      states.delete(key);
      states.set(key, state);
      while (states.size > 64) states.delete(states.keys().next().value);
      const initial = await first();
      state.category = initial.category;
      state.isRanking = Boolean(initial.isRanking || key.startsWith('hongguo-app:'));
      const firstResult = await savePage(state, 1, initial.cell, initial.data || {}, initial.params, initial.minimum);
      if (page === 1) return firstResult;
    }

    const cursor = state.cursors.get(page);
    if (!cursor) {
      return { page, pagecount: page, hasMore: false, list: [], updatedText: state.updatedText || '' };
    }

    try {
      const response = await api('/reading/bookapi/bookmall/cell/change/v', { ...cursor, limit: 40, change_type: 1 });
      return await savePage(state, page, response.data?.cell_view, response.data || {}, cursor);
    } catch (err) {
      if (state && state.pages.size > 0) {
        return { page, pagecount: page, hasMore: false, list: [], updatedText: state.updatedText || '' };
      }
      throw err;
    }
  }

  const legacyHome = spider.home;
  const legacyCategory = spider.category;
  const discoveryGenres = ['all', 'playlet', 'motion_comic', 'ai_playlet'];

  let cachedDiscoveryTab = null;
  let cachedDiscoveryTabTime = 0;
  async function discoveryTab() {
    if (cachedDiscoveryTab && Date.now() - cachedDiscoveryTabTime < 30 * 60 * 1000) {
      return cachedDiscoveryTab;
    }
    const response = await api('/reading/bookapi/bookmall/tab/v', { tab_type: 8, tab_index: 0, offset: 0 });
    const tab = response.data?.tab_item?.find(item => number(item.tab_type) === 8);
    const cell = container(tab?.cell_data);
    const choices = cell?.cell_selector?.outer_row?.items || [];
    if (!cell || !discoveryGenres.every(id => choices.some(item => item.selector_item_id === id && text(item.show_name)))) {
      throw failure('官方找剧分类暂不可用，请重试', 'INVALID_RESPONSE');
    }
    cachedDiscoveryTab = { cell, choices };
    cachedDiscoveryTabTime = Date.now();
    return cachedDiscoveryTab;
  }

  spider.home = async function (filter) {
    if (!filter) return legacyHome(false);
    const { choices } = await discoveryTab();
    return { class: choices.filter(item => discoveryGenres.includes(item.selector_item_id)).map(item => ({
      type_id: 'app:discover:' + item.selector_item_id, type_name: text(item.show_name)
    })), filters: {} };
  };

  spider.category = async function (tid, page, filter, extend) {
    const aliases = { '': 'all', all: 'all', short_play: 'all', 'real-drama': 'playlet',
      'comic-drama': 'motion_comic', comic: 'motion_comic', 'ai-drama': 'ai_playlet',
      'app:theater:8': 'all', 'app:theater:38': 'playlet', 'app:theater:32': 'motion_comic' };
    const genre = aliases[text(tid)] || text(tid).replace(/^app:discover:/, '');
    if (!discoveryGenres.includes(genre)) {
      if (typeof legacyCategory === 'function') return legacyCategory(tid, page, filter, extend);
      throw failure('分类已更新，请重新选择分类', 'INVALID_CATEGORY');
    }
    return await paged('discover:' + genre, page, async () => {
      const { cell, choices } = await discoveryTab();
      const category = genre === 'all' ? '短剧' : text(choices.find(item => item.selector_item_id === genre).show_name);
      const params = {
        cell_id: text(cell.cell_id_str), tab_type: 8, selected_items: genre,
        sub_selected_items: '', unlimited_selector_change_type: 1,
        client_template: 2, client_req_type: 2
      };
      const minimum = Math.min(24, Math.max(1, number(extend?.initialBatch)));
      if (genre === 'all' && choices.find(item => item.selector_item_id === genre).is_selected) {
        return { cell, params, category, minimum };
      }
      const response = await api('/reading/bookapi/bookmall/cell/change/v', {
        ...params, unlimited_selector_change_type: 2, change_type: 1, offset: 0, limit: 40
      });
      return { cell: response.data?.cell_view, data: response.data || {}, params, category, minimum };
    });
  };

  spider.suggestions = async function (word) {
    const query = text(word).slice(0, 100);
    const common = { bookstore_tab: 16, tab_name: 'feed', search_source: 1, user_is_login: 0 };
    const response = await api(query ? '/reading/bookapi/search/suggest/v' : '/reading/bookapi/search/cue/v',
      query ? { ...common, query, count: 10 } : { ...common, cue_type: 0, limit: 10 });
    let words;
    if (query) {
      words = response.data?.query_result;
      if (!Array.isArray(words) || !words.length) words = (response.data?.query_result_v2 || []).map(item => item.name);
    } else {
      words = (response.data_v1 || []).map(item => item.text || item.display_text);
      if (!words.length && response.data?.text) words = [response.data.text];
    }
    if (!Array.isArray(words)) throw failure('官方搜索建议数据无效', 'INVALID_RESPONSE');
    return { items: [...new Set(words.map(text).filter(value => value && value.length <= 100))].slice(0, 10) };
  };

  let cachedRankingBoards = null;
  let cachedRankingBoardsTime = 0;
  spider.rankingBoards = async function () {
    if (cachedRankingBoards && Date.now() - cachedRankingBoardsTime < 15 * 60 * 1000) {
      return cachedRankingBoards;
    }
    const response = await api('/reading/bookapi/plan/v', rankParams('all', 'ranklist_hot_sc'));
    const cell = container(response.data);
    const items = [];
    for (const group of cell?.cell_selector?.outer_row?.items || []) {
      if (!['all', 'human', 'comic_series_rank', 'ai_playlet'].includes(group.selector_item_id)) continue;
      for (const board of group.sub_cell_selector?.outer_row?.items || []) {
        if (!/^[a-z0-9_]{1,80}$/.test(board.selector_item_id || '')) continue;
        items.push({
          id: 'hongguo-app:' + group.selector_item_id + ':' + board.selector_item_id,
          name: (group.selector_item_id === 'all' ? '' : text(group.show_name) + '·') + text(board.show_name),
          description: text(board.sub_title), source: 'hongguo'
        });
      }
    }
    if (!items.length) throw failure('官方接口暂未返回短剧榜单，请重试', 'INVALID_RESPONSE');
    cachedRankingBoards = { items };
    cachedRankingBoardsTime = Date.now();
    return cachedRankingBoards;
  };

  spider.rankings = function (board, page) {
    const match = /^hongguo-app:(all|human|comic_series_rank|ai_playlet):([a-z0-9_]{1,80})$/.exec(text(board));
    if (!match) throw failure('榜单已更新，请重新打开榜单列表', 'INVALID_BOARD');
    return rankedPage(match[1], match[2], page, text(board));
  };

  function rankedPage(group, board, page, key) {
    return paged(key, page, async () => {
      const params = rankParams(group, board);
      const response = await api('/reading/bookapi/plan/v', params);
      const cell = container(response.data);
      const selected = cell?.cell_selector?.outer_row?.items?.find(item => item.is_selected);
      const sub = selected?.sub_cell_selector?.outer_row?.items?.find(item => item.is_selected);
      if (selected?.selector_item_id !== group || sub?.selector_item_id !== board) throw failure('官方榜单配置已更新，请刷新榜单', 'INVALID_BOARD');
      return { cell, params: { ...params, tab_type: 26 }, isRanking: true };
    });
  };

  spider.recommendations = function (genre, page) {
    const key = text(genre);
    if (['ai_series', 'ai-drama', 'AI 剧', 'AI剧'].includes(key)) {
      return rankedPage('ai_playlet', 'ai_playlet_hot_sc', page, 'recommendations:ai');
    }
    const comic = ['comic_series', 'comic-drama', 'comic', '漫剧'].includes(key);
    const tabType = comic ? 32 : 38;
    return paged('recommendations:' + tabType, page, async () => {
      const response = await api('/reading/bookapi/bookmall/tab/v', { tab_type: tabType, tab_index: comic ? 2 : 1, offset: 0 });
      const tab = response.data?.tab_item?.find(item => number(item.tab_type) === tabType);
      if (!tab) throw failure('官方接口未返回此推荐分类，请重试', 'INVALID_RESPONSE');
      const cell = container(tab.cell_data);
      return { cell, params: { tab_type: tabType } };
    });
  };
})();

(function () {
  const text = value => value == null ? '' : String(value).trim();
  const integer = value => Math.max(0, Number.parseInt(value, 10) || 0);
  const failure = code => Object.assign(new Error('官方系列剧列表暂不可用'), { code });
  spider.seriesSeasons = async function (rawId) {
    const id = text(rawId).replace(/^hongguo:/, '');
    if (!/^[1-9]\d{9,29}$/.test(id)) throw failure('INVALID_SERIES_ID');
    const api = HongguoApp.fetchAppDiscoveryRaw;
    const response = await api('/reading/bookapi/plan/v', {
      scene: 10, from: 'single_col_same_ip_series', book_id: id, filter_ids: id
    });
    if (Number(response.code) !== 0) throw failure('SERIES_REJECTED');
    let cell = (response.data || []).find(value => Array.isArray(value.video_data) &&
      value.video_data.some(video => integer(video.season_index) > 0));
    if (!cell) return { list: [] };
    const rows = new Map();
    const cursors = new Set();
    for (let page = 0; page < 10; page++) {
      for (const video of cell.video_data || []) {
        const raw = video.series_id_str || video.series_id;
        const vid = typeof raw === 'string' ? raw : Number.isSafeInteger(raw) ? String(raw) : '';
        const season = integer(video.season_index);
        if (!/^[1-9]\d{9,29}$/.test(vid) || !season || season > 200 || !text(video.title)) continue;
        const episodes = integer(video.episode_cnt);
        const upcoming = !episodes && !!video.subscribe_item;
        const playable = episodes > 0 && video.disable_play !== true;
        const status = upcoming ? '待上线' : playable ? '' : '暂不可播放';
        rows.set(vid, {
          vod_id: vid, vod_name: text(video.title), vod_pic: cleanCoverUrl(text(video.cover)),
          vod_content: text(video.video_desc), vod_episodes: episodes,
          vod_remarks: episodes ? episodes + '集' : status,
          vod_release_status: upcoming ? 'upcoming' : '',
          season, playable, status
        });
      }
      if (cell.has_more !== true) return { list: [...rows.values()].sort((a, b) => a.season - b.season) };
      const cursor = {
        cell_id: text(cell.cell_id_str), offset: integer(cell.next_offset),
        session_id: text(cell.session_id), filter_ids: id
      };
      const key = cursor.cell_id + ':' + cursor.offset;
      if (!cursor.cell_id || !cursor.offset || cursors.has(key) || page === 9) throw failure('INVALID_SERIES_CURSOR');
      cursors.add(key);
      const next = await api('/reading/bookapi/bookmall/cell/change/v', cursor);
      if (Number(next.code) !== 0 || !next.data?.cell_view) throw failure('INVALID_RESPONSE');
      cell = next.data.cell_view;
      if (globalThis.__hongguoCancelled) throw failure('cancelled');
    }
    return { list: [] };
  };
})();

(function () {
  const states = new Map();
  const details = new Map();
  globalThis.__hongguoFeedDetails = details;
  const text = value => value == null ? '' : String(value).trim();
  const number = value => Math.max(0, Number.parseInt(value, 10) || 0);
  const identity = value => typeof value === 'string' && /^[1-9]\d{9,29}$/.test(value) ? value : '';
  const failure = (message, code) => Object.assign(new Error(message), { code });
  function videos(cells) {
    const rows = [];
    for (const cell of cells || []) {
      rows.push(...(cell.video_data || []));
      rows.push(...videos(cell.cell_data));
    }
    return rows;
  }
  spider.feed = async function (rawPage, rawScope) {
    const page = Math.max(1, number(rawPage));
    const scope = text(rawScope).slice(0, 160);
    const initialOffset = Math.max(0, number((scope.match(/_(\d+)$/) || [])[1]));
    let state = states.get(scope);
    if (page === 1) {
      state = { pages: new Map(), seen: new Set(), updated: Date.now(), cursor: null };
      states.delete(scope);
      states.set(scope, state);
      while (states.size > 16) states.delete(states.keys().next().value);
    }
    if (state && state.pages.has(page)) return state.pages.get(page);
    if (!state || Date.now() - state.updated > 2 * 60 * 60 * 1000) {
      state = { pages: new Map(), seen: new Set(), updated: Date.now(), cursor: null };
      states.delete(scope);
      states.set(scope, state);
      while (states.size > 16) states.delete(states.keys().next().value);
    }
    if (page > 1 && (!state.cursor || page !== state.pages.size + 1)) {
      return { page, pagecount: page, limit: 10, total: 0, list: [] };
    }
    const api = HongguoApp.fetchAppDiscoveryRaw;
    let cell, tab, data, params;
    if (page === 1) {
      const response = await api('/reading/bookapi/bookmall/tab/v', {
        tab_type: 16, bottom_tab_type: 7, tab_index: 0, offset: 0, client_template: 7
      });
      tab = response.data?.tab_item?.find(item => Number(item.tab_type) === 16);
      cell = tab?.cell_data?.find(item => item.cell_id_str && videos([item]).length);
      data = tab;
      if (initialOffset > 0 && cell?.cell_id_str) {
        try {
          const changeRes = await api('/reading/bookapi/bookmall/cell/change/v', {
            tab_type: 16,
            bottom_tab_type: 7,
            client_template: 7,
            client_req_type: 2,
            change_type: 1,
            cell_id: text(cell.cell_id_str),
            offset: initialOffset,
            session_id: text(tab.session_id)
          });
          if (changeRes.data?.cell_view && videos([changeRes.data.cell_view]).length) {
            cell = changeRes.data.cell_view;
            data = changeRes.data;
            params = { offset: initialOffset };
          }
        } catch (_) {}
      }
    } else {
      params = state.cursor;
      const response = await api('/reading/bookapi/bookmall/cell/change/v', params);
      cell = response.data?.cell_view;
      data = response.data;
    }
    if (!cell || !data) throw failure('首页推荐暂不可用，请重试', 'INVALID_RESPONSE');

    let cellId = text(cell.cell_id_str || state.cellId || params?.cell_id);
    let sessionId = text(data.session_id || cell.session_id || tab?.session_id || state.sessionId);
    state.cellId = cellId;
    state.sessionId = sessionId;

    let previous = number(params?.offset);
    let offset = (page === 1 && !params) ? Math.max(number(tab.next_offset), videos([cell]).length) : number(data.next_offset);
    let hasMore = (page === 1 && !params) ? tab.bottom_unlimited === true && videos([cell]).length > 0 :
      data.has_more === true && offset > previous;

    const list = [];
    function appendVideos(targetCell) {
      const raw = videos([targetCell]);
      for (const video of raw) {
        const detail = video.video_detail || {};
        const id = identity(detail.series_id_str || detail.series_id || video.series_id);
        const title = text(detail.series_title || video.title);
        const episodes = number(detail.episode_cnt || video.episode_cnt);
        if (!id || !title || !episodes || video.disable_play === true || state.seen.has(id)) continue;
        const chapters = (detail.video_list || []).filter(item => identity(item.vid || item.video_id))
          .sort((a, b) => number(a.vid_index) - number(b.vid_index));
        if (chapters.length === episodes && chapters.every((item, index) => number(item.vid_index) === index + 1) &&
            new Set(chapters.map(item => identity(item.vid || item.video_id))).size === episodes) {
          details.delete(id);
          details.set(id, { updated: Date.now(), data: {
            series_id: id, series_title: title, series_intro: text(detail.series_intro),
            series_cover: text(detail.series_cover || video.cover), episode_cnt: episodes,
            video_list: chapters.map(item => ({ vid: identity(item.vid || item.video_id), vid_index: number(item.vid_index) }))
          } });
          while (details.size > 16) details.delete(details.keys().next().value);
        }
        const startId = identity(video.vid) || identity(video.highlight?.vid);
        const start = chapters.find(item => item.vid === startId);
        list.push({
          vod_id: id, vod_name: title, vod_content: text(detail.series_intro || video.video_desc),
          vod_pic: cleanCoverUrl(text(detail.series_cover || video.cover)), vod_episodes: episodes,
          vod_remarks: episodes + '集', vod_start_episode: number(start?.vid_index) || 1,
          vod_start_position: start && identity(video.highlight?.vid) === startId ? number(video.highlight.start_time_in_millisecond) / 1000 : 0
        });
        state.seen.add(id);
      }
    }

    appendVideos(cell);

    let rounds = 0;
    while (!list.length && hasMore && rounds < 5) {
      rounds++;
      const nextRes = await api('/reading/bookapi/bookmall/cell/change/v', {
        tab_type: 16, bottom_tab_type: 7, client_template: 7, client_req_type: 2,
        change_type: 1, cell_id: cellId,
        offset: offset, session_id: sessionId
      });
      const nextCell = nextRes.data?.cell_view;
      const nextData = nextRes.data;
      if (!nextCell || !nextData) throw failure('官方接口未返回剧集列表，请重试', 'INVALID_RESPONSE');
      const prevOff = offset;
      offset = number(nextData.next_offset);
      hasMore = nextData.has_more === true && offset > prevOff;
      cellId = text(nextCell.cell_id_str || cellId);
      sessionId = text(nextData.session_id || nextCell.session_id || sessionId);
      appendVideos(nextCell);
    }

    hasMore = hasMore && list.length > 0;
    const result = { list, page, pagecount: hasMore ? page + 1 : page, hasMore };
    state.pages.set(page, result);
    state.updated = Date.now();
    state.cellId = cellId;
    state.sessionId = sessionId;
    state.cursor = hasMore ? {
      tab_type: 16, bottom_tab_type: 7, client_template: 7, client_req_type: 2,
      change_type: 1, cell_id: cellId,
      offset, session_id: sessionId
    } : null;
    return result;
  };
})();
