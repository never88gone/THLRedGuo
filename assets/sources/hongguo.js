/**
 * 官方免费短剧 CatPawOpen Spider (hongguo.js)
 * 适配 CatPawOpen / CatVodOpen 标准规范 v1.0.3
 * 支持官方 App API 与 Web 路由双轨容错解析
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
  if (!seriesId || !/^\d{10,}$/.test(String(seriesId))) return null;
  try {
    var now = Date.now();
    var qs = "aid=8662&app_name=novelread&version_code=73532&version_name=7.3.5.32&manifest_version_code=73532&update_version_code=73532&channel=update_64&device_platform=android&os=android&ssmix=a&device_type=25053RT47C&device_brand=Redmi&language=zh&os_api=36&os_version=16&resolution=1280*2772&dpi=520&ac=wifi&device_id=7361909012345678901&iid=7361909012345678902&_rticket=" + now;
    var body = JSON.stringify({ series_id: String(seriesId) });
    var headers = signGorgon(qs, body, now);
    headers["Content-Type"] = "application/json; charset=utf-8";

    var url = APP_API_BASE + "/novel/player/video_detail/v1/?" + qs;
    var resp = await fetch(url, {
      method: "POST",
      headers: headers,
      body: body
    });

    if (resp && resp.status === 200) {
      var raw = typeof resp.text === "function" ? await resp.text() : resp.body;
      if (raw) {
        var parsed = safeJsonParse(raw);
        if (parsed && parsed.data && parsed.data.video_data) {
          return parsed.data.video_data;
        }
      }
    }
  } catch (_) {}
  return null;
}

// 官方 App API 获取指定视频的完整播放流模型（支持全部集数与多清晰度）
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
      if (raw) {
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
    cover = appData.series_cover || appData.cover || "";
    desc = cleanText(appData.series_intro || appData.video_desc || appData.intro || appData.desc);
    epTotalCount = Number(appData.episode_cnt || 0);

    if (Array.isArray(appData.video_list) && appData.video_list.length > 0) {
      for (let i = 0; i < appData.video_list.length; i++) {
        const item = appData.video_list[i];
        const vid = item.vid || item.video_id;
        if (vid && !String(vid).endsWith("000")) {
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
              if (sCover && !cover) cover = sCover;
              const sDesc = cleanText(sDetail.series_intro || sDetail.intro || sDetail.abstract || sDetail.desc);
              if (sDesc && !desc) desc = sDesc;
              if (Array.isArray(sDetail.vid_list) && sDetail.vid_list.length > 0) {
                for (let j = 0; j < sDetail.vid_list.length; j++) {
                  const v = String(sDetail.vid_list[j]);
                  if (!v.endsWith("000")) vidList.push(v);
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
              vidList = ids.filter(function(v) { return !v.endsWith("000"); });
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
            if (domCover && !cover) cover = domCover;
            const domDesc = cleanText(doc.find(".detail-intro, .desc, meta[name='description']").text() || doc.find("meta[name='description']").attr("content") || "");
            if (domDesc && !desc) desc = domDesc;
          }
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

  let remarks = "";
  if (epUrls.length > 0) {
    if (accessibleCount > 0 && accessibleCount < epUrls.length) {
      remarks = "全" + epUrls.length + "集 (试看前" + accessibleCount + "集)";
    } else {
      remarks = "全" + epUrls.length + "集";
    }
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
        accessible_count: accessibleCount > 0 ? accessibleCount : (epUrls.length > 3 ? 3 : epUrls.length)
      }
    ]
  };
}

async function play(flag, id, flags) {
  let playTarget = (id || "").toString().trim();
  if (playTarget.includes(":")) {
    playTarget = playTarget.split(":").pop().trim();
  }

  // 若已经是完整的 mp4 / m3u8 网络媒体直链，直接返回
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
  let playerPageUrl = "";

  const isCorruptedId = function(s) {
    return !s || /000$/.test(s);
  };

  // 1. 优先从 /player/ 路由中精确提取 seriesId 与 itemId
  const playerMatch = playTarget.match(/\/player\/([^\/\?#]+)(?:\/([^\/\?#]+))?/);
  if (playerMatch) {
    seriesId = playerMatch[1];
    itemId = playerMatch[2] || "";
    playerPageUrl = playTarget.startsWith("http") ? playTarget : (BASE_URL + (playTarget.startsWith("/") ? "" : "/") + playTarget);
  } else {
    const segments = playTarget.split(/[\/_]/).filter(Boolean);
    const longDigits = [];
    let shortDigit = 0;

    for (const seg of segments) {
      const m = seg.match(/\d+/);
      if (!m) continue;
      const numStr = m[0];
      if (numStr.length >= 10) {
        longDigits.push(numStr);
      } else if (numStr.length >= 1 && shortDigit === 0) {
        shortDigit = parseInt(numStr, 10);
      }
    }

    if (longDigits.length >= 2) {
      seriesId = longDigits[0];
      itemId = longDigits[1];
      if (isCorruptedId(itemId)) itemId = "";
    } else if (longDigits.length === 1) {
      seriesId = longDigits[0];
      if (shortDigit > 0) {
        episodeIndex = shortDigit;
      }
    }
  }

  // 2. 若未能获得有效的单集 vid（即 itemId 为空），尝试通过 App 官方 API 解析该集真实的 vid
  if (!itemId && seriesId && !isCorruptedId(seriesId)) {
    const appDetail = await fetchAppDetail(seriesId);
    if (appDetail && Array.isArray(appDetail.video_list) && appDetail.video_list.length > 0) {
      const idx = Math.max(0, Math.min(episodeIndex - 1, appDetail.video_list.length - 1));
      const targetEp = appDetail.video_list[idx];
      if (targetEp && targetEp.vid && !isCorruptedId(targetEp.vid)) {
        itemId = String(targetEp.vid);
      }
    }
  }

  let realStreamUrl = "";

  // 3. 官方 App 专有播放模型 (video_model)：最高优先级，保证全集（包括后半部分集数）全覆盖与高清流
  if (itemId && !isCorruptedId(itemId)) {
    const model = await fetchAppVideoModel(itemId);
    if (model && !model.isError) {
      const appStream = extractStreamFromVideoModel(model);
      if (appStream) {
        return {
          parse: 0,
          url: appStream,
          header: {
            "User-Agent": USER_AGENT,
            "Referer": "https://novel.snssdk.com/"
          }
        };
      }
    }
  }

  // 4. 若 App 专用接口未取到流，回退走网页播放页解析官方原生真实流（含 Base64 地址自动解码）
  if (playerPageUrl || (itemId && !isCorruptedId(itemId))) {
    const targetUrl = playerPageUrl || (BASE_URL + "/player/" + (seriesId || itemId) + "/" + itemId);
    try {
      const resp = await fetch(targetUrl, {
        headers: {
          "User-Agent": USER_AGENT,
          "Referer": BASE_URL + "/"
        }
      });
      const body = resp && (typeof resp.text === "function" ? await resp.text() : resp.body);
      if (body) {
        // A. 匹配 main_url / backup_url 并尝试 Base64 解码
        const mUrls = body.match(/"(?:main_url|backup_url|url_list)"\s*:\s*"([^"]+)"/g);
        if (mUrls) {
          for (let i = 0; i < mUrls.length; i++) {
            const valMatch = mUrls[i].match(/:\s*"([^"]+)"/);
            if (valMatch && valMatch[1]) {
              let candidate = valMatch[1].replace(/\\u0026/g, "&").replace(/\\u002F/g, "/").replace(/\\\//g, "/");
              if (!candidate.startsWith("http://") && !candidate.startsWith("https://")) {
                const decoded = safeBase64Decode(candidate);
                if (decoded && (decoded.startsWith("http://") || decoded.startsWith("https://"))) {
                  candidate = decoded;
                }
              }
              if (candidate.startsWith("http://") || candidate.startsWith("https://")) {
                realStreamUrl = candidate;
                break;
              }
            }
          }
        }

        // B. 匹配 contentUrl
        if (!realStreamUrl) {
          const mContent = body.match(/"contentUrl"\s*:\s*"([^"]+)"/);
          if (mContent && mContent[1]) {
            realStreamUrl = mContent[1].replace(/\\u0026/g, "&").replace(/\\u002F/g, "/").replace(/\\\//g, "/");
          }
        }

        // C. 匹配明文媒体地址
        if (!realStreamUrl) {
          const m3u8Match = body.match(/https?:\/\/[^"'\s<>\\]+\.(?:m3u8|mp4)(?:\?[^"'\s<>\\]*)?/);
          if (m3u8Match) realStreamUrl = m3u8Match[0];
        }
      }
    } catch (_) {}

    // D. 网页未提取到流时，回退到官方公共媒体地址（注意：必须基于真实分集 vid，绝不使用 seriesId）
    if (!realStreamUrl && itemId && !isCorruptedId(itemId) && /^\d+$/.test(itemId)) {
      realStreamUrl = BASE_URL + "/video/public/" + itemId + "/360p.mp4";
    }
  }

  // 严禁将 seriesId 当作 vid 拼接为 360p.mp4，避免生成 404 伪链接
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
      const json = safeJsonParse(rawBody);
      const list = (json && (json.suggest_list || (json.data && json.data.suggest_list))) || [];
      for (let i = 0; i < list.length; i++) {
        const item = list[i];
        const videoData = item.video_data || {};

        let rawId = videoData.series_id || videoData.series_id_str || "";
        if (!rawId && item.keyword && /^\d{10,}$/.test(String(item.keyword).trim())) {
          rawId = String(item.keyword).trim();
        }
        if (!rawId && item.series_id) {
          rawId = String(item.series_id).trim();
        }
        const id = String(rawId).trim();
        if (!id || !/^\d+$/.test(id) || id.endsWith("000")) {
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
