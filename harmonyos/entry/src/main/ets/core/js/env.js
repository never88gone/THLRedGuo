import http from '@ohos.net.http';
import hilog from '@ohos.hilog';

// 1. Console safety
if (!globalThis.console) {
  globalThis.console = {
    log: function() {},
    warn: function() {},
    error: function() {},
    info: function() {}
  };
}

// 2. Entropy
if (!globalThis.__hongguoEntropy) {
  let entropy = '';
  for (let i = 0; i < 64; i++) {
    entropy += Math.floor(Math.random() * 256).toString(16).padStart(2, '0');
  }
  globalThis.__hongguoEntropy = entropy;
}

// 3. Base64 atob / btoa fallback
if (typeof globalThis.atob === 'undefined') {
  globalThis.atob = function(str) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let output = '';
    str = String(str).replace(/=+$/, '');
    for (let bc = 0, bs = 0, buffer, i = 0; buffer = str.charAt(i++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
      buffer = chars.indexOf(buffer);
    }
    return output;
  };
}
if (typeof globalThis.btoa === 'undefined') {
  globalThis.btoa = function(input) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let str = String(input);
    let output = '';
    for (let block = 0, charCode, i = 0, map = chars; str.charAt(i | 0) || (map = '=', i % 1); output += map.charAt(63 & block >> 8 - i % 1 * 8)) {
      charCode = str.charCodeAt(i += 3 / 4);
      block = block << 8 | charCode;
    }
    return output;
  };
}

// 4. Safe JSON.parse for large IDs (> 15 digits)
var nativeParse = JSON.parse;
JSON.parse = function(text, reviver) {
  if (typeof text === 'string' && /\d{15,}/.test(text)) {
    var output = '';
    var copied = 0;
    var quoted = false;
    var escaped = false;
    var numberCharacters = '0123456789.eE+-';
    for (var index = 0; index < text.length; index++) {
      var character = text[index];
      if (quoted) {
        if (escaped) escaped = false;
        else if (character === '\\') escaped = true;
        else if (character === '"') quoted = false;
        continue;
      }
      if (character === '"') {
        quoted = true;
        continue;
      }
      if (character !== '-' && (character < '0' || character > '9')) continue;
      var start = index;
      while (index < text.length && numberCharacters.indexOf(text[index]) >= 0) index++;
      var token = text.slice(start, index);
      if (/^-?[1-9]\d{14,}$/.test(token)) {
        output += text.slice(copied, start) + '"' + token + '"';
        copied = index;
      }
      index--;
    }
    if (copied > 0) text = output + text.slice(copied);
  }
  return nativeParse(text, reviver);
};

// 5. Native fetch using @ohos.net.http
globalThis.fetch = function(url, options) {
  options = options || {};
  var method = (options.method || 'GET').toUpperCase();
  var headers = options.headers || {};
  var body = options.body;

  var req = http.createHttp();
  var httpMethod = http.RequestMethod.GET;
  if (method === 'POST') httpMethod = http.RequestMethod.POST;
  else if (method === 'HEAD') httpMethod = http.RequestMethod.HEAD;

  return new Promise(function(resolve, reject) {
    req.request(url, {
      method: httpMethod,
      header: headers,
      extraData: body,
      readTimeout: options.timeoutMs || 25000,
      connectTimeout: 12000
    }, function(err, data) {
      if (err) {
        try { req.destroy(); } catch (_) {}
        hilog.warn(0x0000, 'HongGuoFetch', 'Request error: %{public}s %{public}s', url, JSON.stringify(err));
        if (httpMethod === http.RequestMethod.HEAD) {
          resolve({
            status: 200,
            statusText: 'OK',
            headers: {
              get: function(key) {
                if (key && key.toLowerCase() === 'content-type') return 'video/mp4';
                return '';
              },
              'content-type': 'video/mp4'
            },
            body: '',
            text: function() { return Promise.resolve(''); },
            json: function() { return Promise.resolve({}); }
          });
          return;
        }
        var errResp = {
          status: 0,
          statusText: 'Network Error: ' + JSON.stringify(err),
          headers: {
            get: function() { return ''; }
          },
          body: '',
          text: function() { return Promise.resolve(''); },
          json: function() { return Promise.reject(err); }
        };
        resolve(errResp);
        return;
      }
      var respCode = data.responseCode;
      var respHeaders = data.header || {};
      if (httpMethod === http.RequestMethod.HEAD) {
        respCode = 200;
        if (!respHeaders['content-type'] && !respHeaders['Content-Type']) {
          respHeaders['content-type'] = 'video/mp4';
        }
      }
      var resultStr = '';
      if (typeof data.result === 'string') {
        resultStr = data.result;
      } else if (data.result instanceof ArrayBuffer) {
        var u8 = new Uint8Array(data.result);
        var s = '';
        for (var i = 0; i < u8.length; i++) {
          s += String.fromCharCode(u8[i]);
        }
        try {
          resultStr = decodeURIComponent(escape(s));
        } catch (_) {
          resultStr = s;
        }
      }
      try { req.destroy(); } catch (_) {}

      var responseObj = {
        status: respCode,
        statusText: String(respCode),
        headers: {
          get: function(key) {
            if (!key) return '';
            var k = key.toLowerCase();
            for (var h in respHeaders) {
              if (h.toLowerCase() === k) return String(respHeaders[h]);
            }
            return '';
          },
          ...respHeaders
        },
        body: resultStr,
        text: function() {
          return Promise.resolve(resultStr);
        },
        json: function() {
          try {
            return Promise.resolve(JSON.parse(resultStr));
          } catch (parseErr) {
            return Promise.reject(parseErr);
          }
        }
      };
      resolve(responseObj);
    });
  });
};

globalThis.__hongguo_env_ready = true;
export const envReady = true;
