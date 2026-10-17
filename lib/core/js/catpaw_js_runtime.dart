import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;

class CatPawHomeResult {
  final List<Map<String, dynamic>> classes;
  final List<Map<String, dynamic>> filters;
  const CatPawHomeResult({required this.classes, required this.filters});
}

class CatPawCategoryResult {
  final int page;
  final int pageCount;
  final int limit;
  final int total;
  final List<Map<String, dynamic>> list;
  final bool hasMore;

  const CatPawCategoryResult({
    required this.page,
    this.pageCount = 1,
    this.limit = 20,
    this.total = 0,
    required this.list,
    required this.hasMore,
  });
}

typedef CatPawCatalogResult = CatPawCategoryResult;

class CatPawDetailResult {
  final Map<String, dynamic> vod;
  const CatPawDetailResult({required this.vod});
}

class CatPawPlayResult {
  final String url;
  final Map<String, String> header;
  final int parse;
  final int quality;
  final List<int> qualities;
  const CatPawPlayResult({
    required this.url,
    required this.header,
    this.parse = 0,
    this.quality = 0,
    this.qualities = const [],
  });
}

class CatPawSearchResult {
  final List<Map<String, dynamic>> list;
  const CatPawSearchResult({required this.list});
}

class CatPawJsRuntime {
  late final JavascriptRuntime _rt;
  final http.Client _httpClient;
  final bool _isOwnedClient;
  bool _ready = false;
  bool _isDisposed = false;
  int _activeRequests = 0;
  int _activeEvals = 0;
  Completer<void>? _drainCompleter;
  Completer<void>? _evalDrainCompleter;

  CatPawJsRuntime([http.Client? client])
    : _httpClient = client ?? http.Client(),
      _isOwnedClient = client == null;

  bool get isReady => _ready;
  bool get isDisposed => _isDisposed;

  Future<void> init(String script) async {
    if (_isDisposed) throw StateError('CatPawJsRuntime 已被释放');
    _rt = getJavascriptRuntime(xhr: false);
    _injectGlobals();
    final result = _rt.evaluate(script);
    if (result.isError) {
      throw Exception('JS 脚本加载失败: ${result.rawResult}');
    }
    _ready = true;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _ready = false;

    if (_activeRequests == 0 && _activeEvals == 0) {
      _cleanup();
    } else {
      final futures = <Future<void>>[];
      if (_activeRequests > 0) {
        _drainCompleter ??= Completer<void>();
        futures.add(_drainCompleter!.future);
      }
      if (_activeEvals > 0) {
        _evalDrainCompleter ??= Completer<void>();
        futures.add(_evalDrainCompleter!.future);
      }
      Future.wait(futures).whenComplete(() {
        _cleanup();
      });
    }
  }

  void _cleanup() {
    try {
      _rt.dispose();
    } catch (_) {}
    if (_isOwnedClient) {
      _httpClient.close();
    }
  }

  void _injectGlobals() {
    _rt.evaluate(r'''
var JSON = JSON || {};
if (!JSON.stringify) JSON.stringify = function(o) { return "{}"; };
if (!JSON.parse) JSON.parse = function(s) { return {}; };
(function() {
  var nativeParse = JSON.parse;
  JSON.parse = function(text, reviver) {
    if (typeof text === 'string' && /\d{15,}/.test(text)) {
      var prev;
      do {
        prev = text;
        text = text.replace(/([:\[,]\s*)(\d{15,})(\s*[,\]\}])/g, '$1"$2"$3');
      } while (text !== prev);
    }
    return nativeParse(text, reviver);
  };
})();
if (typeof console === 'undefined') {
  globalThis.console = {
    log: function() {},
    warn: function() {},
    error: function() {},
    info: function() {}
  };
}
''');

    _rt.evaluate(_evalAsyncShim);
    _rt.evaluate(_htmlShim);
    _rt.evaluate(_fetchShim);

    _rt.onMessage('__fetch__', (dynamic args) async {
      if (_isDisposed) {
        return {'status': 0, 'headers': <String, String>{}, 'body': ''};
      }
      _activeRequests++;
      String url = '';
      try {
        Map<String, dynamic> params = {};
        if (args is Map) {
          params = Map<String, dynamic>.from(args);
        } else if (args is String) {
          try {
            final decoded = jsonDecode(args);
            if (decoded is Map) params = Map<String, dynamic>.from(decoded);
          } catch (_) {}
        }

        url = params['url']?.toString() ?? '';
        final method = (params['method']?.toString() ?? 'GET').toUpperCase();
        final rawHeaders = params['headers'];
        final headers = <String, String>{};
        if (rawHeaders is Map) {
          rawHeaders.forEach((k, v) {
            if (k != null && v != null) headers[k.toString()] = v.toString();
          });
        }
        final body = params['body']?.toString();

        final uri = Uri.parse(url);
        http.Response resp;
        if (method == 'POST') {
          resp = await _httpClient.post(uri, headers: headers, body: body);
        } else if (method == 'PUT') {
          resp = await _httpClient.put(uri, headers: headers, body: body);
        } else if (method == 'DELETE') {
          resp = await _httpClient.delete(uri, headers: headers, body: body);
        } else if (method == 'HEAD') {
          resp = await _httpClient.head(uri, headers: headers);
        } else {
          resp = await _httpClient.get(uri, headers: headers);
        }

        if (_isDisposed) {
          return {'status': 0, 'headers': <String, String>{}, 'body': ''};
        }
        return {
          'status': resp.statusCode,
          'headers': resp.headers,
          'body': resp.body,
        };
      } catch (e) {
        // ignore: avoid_print
        print('【FETCH ERROR】url=$url, err=$e');
        if (_isDisposed) {
          return {'status': 0, 'headers': <String, String>{}, 'body': ''};
        }
        return {
          'status': 0,
          'headers': <String, String>{},
          'body': '',
          'error': e.toString(),
        };
      } finally {
        _activeRequests--;
        if (_isDisposed &&
            _activeRequests == 0 &&
            _drainCompleter != null &&
            !_drainCompleter!.isCompleted) {
          _drainCompleter!.complete();
        }
      }
    });

    _rt.evaluate(_fetchShim);
  }

  Future<Map<String, dynamic>> getMeta() async {
    _assertReady();
    final res = await _evalAsync(
      'typeof spider !== "undefined" && spider.meta ? spider.meta : (typeof meta !== "undefined" ? meta : {})',
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {};
  }

  Future<CatPawHomeResult> home({bool filter = false}) async {
    _assertReady();
    final res = await _evalAsync(
      'typeof spider !== "undefined" && typeof spider.home === "function" ? spider.home($filter) : { class: [], filters: {} }',
    );
    final map = (res is Map) ? res : {};
    final classes = _toListOfMaps(map['class'] ?? map['classes'] ?? []);
    final filters = _parseFilters(map['filters'] ?? map['filter'] ?? []);
    return CatPawHomeResult(classes: classes, filters: filters);
  }

  Future<CatPawCategoryResult> category(
    String tid,
    int page, {
    bool filter = false,
    Map<String, dynamic>? extend,
  }) async {
    _assertReady();
    final extendJson = jsonEncode(extend ?? {});
    final res = await _evalAsync(
      'typeof spider !== "undefined" && typeof spider.category === "function" ? spider.category(${jsonEncode(tid)}, $page, $filter, $extendJson) : { list: [], page: $page, pagecount: 1 }',
    );
    final map = (res is Map) ? res : {};
    final list = _toListOfMaps(map['list'] ?? []);
    final pg = (map['page'] as num?)?.toInt() ?? page;
    final pageCount =
        (map['pagecount'] as num?)?.toInt() ??
        (map['pageCount'] as num?)?.toInt() ??
        1;
    final limit = (map['limit'] as num?)?.toInt() ?? 20;
    final total = (map['total'] as num?)?.toInt() ?? 0;
    return CatPawCategoryResult(
      page: pg,
      pageCount: pageCount,
      limit: limit,
      total: total,
      list: list,
      hasMore: pg < pageCount,
    );
  }

  Future<CatPawDetailResult> detail(String id) async {
    _assertReady();
    final res = await _evalAsync(
      'typeof spider !== "undefined" && typeof spider.detail === "function" ? spider.detail(${jsonEncode(id)}) : { vod_id: ${jsonEncode(id)} }',
    );
    final map = (res is Map) ? res : {};
    dynamic vod = map['vod'];
    if (vod == null &&
        map['list'] is List &&
        (map['list'] as List).isNotEmpty) {
      vod = (map['list'] as List).first;
    }
    vod ??= map;
    return CatPawDetailResult(
      vod: Map<String, dynamic>.from(vod is Map ? vod : {'vod_id': id}),
    );
  }

  Future<CatPawPlayResult> play(
    String flag,
    String id, {
    List<dynamic>? flags,
  }) async {
    _assertReady();
    final flagsJson = jsonEncode(flags ?? []);
    final res = await _evalAsync(
      'typeof spider !== "undefined" && typeof spider.play === "function" ? spider.play(${jsonEncode(flag)}, ${jsonEncode(id)}, $flagsJson) : { parse: 0, url: "" }',
    );
    final map = (res is Map) ? res : {};
    final url = map['url']?.toString() ?? '';
    final parse = (map['parse'] as num?)?.toInt() ?? 0;
    final header = <String, String>{};
    final rawHeader = map['header'] ?? map['headers'];
    if (rawHeader is Map) {
      rawHeader.forEach((k, v) {
        if (k != null && v != null) header[k.toString()] = v.toString();
      });
    }
    return CatPawPlayResult(
      url: url,
      header: header,
      parse: parse,
      quality: (map['quality'] as num?)?.toInt() ?? 0,
      qualities:
          (map['qualities'] is List ? map['qualities'] as List : const [])
              .whereType<num>()
              .map((value) => value.toInt())
              .where((value) => value > 0)
              .toList(),
    );
  }

  Future<CatPawSearchResult> search(
    String keyword, {
    bool quick = false,
    int page = 1,
  }) async {
    _assertReady();
    final res = await _evalAsync(
      'typeof spider !== "undefined" && typeof spider.search === "function" ? spider.search(${jsonEncode(keyword)}, $quick, $page) : []',
    );
    List<Map<String, dynamic>> list = [];
    if (res is List) {
      list = _toListOfMaps(res);
    } else if (res is Map) {
      list = _toListOfMaps(res['list'] ?? []);
    }
    return CatPawSearchResult(list: list);
  }

  Future<void> _evalQueue = Future.value();

  Future<dynamic> _evalAsync(
    String jsCode, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _assertReady();
    final prevQueue = _evalQueue;
    final queueCompleter = Completer<void>();
    _evalQueue = queueCompleter.future;
    try {
      await prevQueue;
    } catch (_) {}
    _assertReady();

    _activeEvals++;
    try {
      final evalResult = _rt.evaluate(
        '__evalAsync(function() { return ($jsCode); })',
      );
      if (evalResult.isError) {
        throw Exception('JS 表达式执行失败: ${evalResult.rawResult}');
      }

      final resolved = await _rt.handlePromise(evalResult, timeout: timeout);
      if (resolved.isError) {
        throw Exception('JS Promise 异常: ${resolved.rawResult}');
      }

      final raw = resolved.stringResult;
      if (raw.isEmpty || raw == 'null' || raw == 'undefined') {
        return null;
      }
      dynamic data;
      try {
        data = jsonDecode(raw);
        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (_) {}
        }
      } catch (e) {
        data = raw;
      }

      if (data is Map && data['__error'] == true) {
        throw Exception('JS 执行异常: ${data['message']}');
      }
      return data;
    } finally {
      queueCompleter.complete();
      _activeEvals--;
      if (_isDisposed &&
          _activeEvals == 0 &&
          _evalDrainCompleter != null &&
          !_evalDrainCompleter!.isCompleted) {
        _evalDrainCompleter!.complete();
      }
    }
  }

  List<Map<String, dynamic>> _toListOfMaps(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> _parseFilters(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else if (raw is Map) {
      return raw.entries
          .map(
            (e) => <String, dynamic>{'key': e.key.toString(), 'value': e.value},
          )
          .toList();
    }
    return [];
  }

  void _assertReady() {
    if (_isDisposed) throw StateError('CatPawJsRuntime 已经被销毁');
    if (!_ready) throw StateError('CatPawJsRuntime 尚未初始化，请先调用 init()');
  }

  static const _evalAsyncShim = r'''
globalThis.__evalAsync = async function(fn) {
  try {
    var res = await fn();
    return JSON.stringify(res);
  } catch (e) {
    return JSON.stringify({
      __error: true,
      message: e ? (e.message || String(e)) : "Unknown JS error"
    });
  }
};
''';

  static const _fetchShim = r'''
globalThis.fetch = async function(url, opts) {
  opts = opts || {};
  var method = (opts.method || 'GET').toUpperCase();
  var headers = opts.headers || {};
  var body = opts.body || '';
  if (typeof body === 'object') {
    try { body = JSON.stringify(body); } catch (_) {}
  }
  var raw = await sendMessage("__fetch__", JSON.stringify({
    url: String(url),
    method: method,
    headers: headers,
    body: String(body)
  }));
  var parsed = (typeof raw === 'string') ? JSON.parse(raw) : raw;
  var status = (parsed && typeof parsed.status === 'number') ? parsed.status : 200;
  var respBody = (parsed && parsed.body != null) ? String(parsed.body) : '';
  var respHeaders = (parsed && parsed.headers) ? parsed.headers : {};
  return {
    status: status,
    ok: status >= 200 && status < 300,
    headers: respHeaders,
    body: respBody,
    text: async function() { return respBody; },
    json: async function() {
      try {
        if (typeof respBody === 'object' && respBody !== null) return respBody;
        return JSON.parse(respBody);
      } catch (e) {
        return {};
      }
    }
  };
};
''';

  static const _htmlShim = r'''
var html = (function() {
  var voidTags = {
    area: true, base: true, br: true, col: true, embed: true,
    hr: true, img: true, input: true, link: true, meta: true,
    param: true, source: true, track: true, wbr: true
  };

  function parseAttrs(attrStr) {
    var attrs = {};
    if (!attrStr) return attrs;
    var re = /([a-zA-Z0-9_\-:]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
    var match;
    while ((match = re.exec(attrStr)) !== null) {
      var key = match[1].toLowerCase();
      var val = match[2] !== undefined ? match[2] : (match[3] !== undefined ? match[3] : (match[4] !== undefined ? match[4] : ""));
      attrs[key] = val;
    }
    return attrs;
  }

  function Node(tag, attrs) {
    this.tag = (tag || "").toLowerCase();
    this.attrs = attrs || {};
    this.children = [];
    this.parent = null;
    this.texts = [];
  }

  Node.prototype.text = function() {
    var parts = [];
    function collect(n) {
      for (var i = 0; i < n.texts.length; i++) {
        if (n.texts[i]) parts.push(n.texts[i]);
      }
      for (var j = 0; j < n.children.length; j++) {
        collect(n.children[j]);
      }
    }
    collect(this);
    return parts.join(" ").replace(/\s+/g, " ").trim();
  };

  Node.prototype.attr = function(name) {
    if (!name) return "";
    return this.attrs[name.toLowerCase()] || "";
  };

  function matchSingle(node, sel) {
    if (!sel || !node.tag) return false;
    sel = sel.trim();
    if (sel === "*") return true;
    if (sel.indexOf("#") === 0) {
      var id = sel.substring(1);
      return (node.attrs["id"] || "") === id;
    }
    if (sel.indexOf(".") === 0) {
      var cls = sel.substring(1);
      var nodeCls = node.attrs["class"] || "";
      var classes = nodeCls.split(/\s+/);
      return classes.indexOf(cls) !== -1;
    }
    if (sel.indexOf(".") > 0) {
      var parts = sel.split(".");
      var tag = parts[0].toLowerCase();
      var c = parts[1];
      if (node.tag !== tag) return false;
      var nCls = node.attrs["class"] || "";
      return nCls.split(/\s+/).indexOf(c) !== -1;
    }
    if (sel.indexOf("#") > 0) {
      var p = sel.split("#");
      var t = p[0].toLowerCase();
      var i = p[1];
      return node.tag === t && (node.attrs["id"] || "") === i;
    }
    return node.tag === sel.toLowerCase();
  }

  function NodeList(nodes) {
    this._nodes = nodes || [];
    this.length = this._nodes.length;
    for (var i = 0; i < this._nodes.length; i++) {
      this[i] = this._wrapNode(this._nodes[i]);
    }
  }

  NodeList.prototype._wrapNode = function(node) {
    return {
      tag: node.tag,
      attrs: node.attrs,
      text: function() { return node.text(); },
      attr: function(name) { return node.attr(name); },
      find: function(sel) { return findInNodes([node], sel); },
      eq: function(idx) { return (idx === 0) ? this : NodeList.empty().eq(0); },
      first: function() { return this; },
      length: 1
    };
  };

  NodeList.empty = function() {
    return new NodeList([]);
  };

  NodeList.prototype.eq = function(idx) {
    if (idx < 0 || idx >= this._nodes.length) {
      return {
        text: function() { return ""; },
        attr: function() { return ""; },
        find: function() { return NodeList.empty(); },
        eq: function() { return NodeList.empty().eq(0); },
        first: function() { return NodeList.empty().eq(0); },
        length: 0
      };
    }
    return this._wrapNode(this._nodes[idx]);
  };

  NodeList.prototype.first = function() {
    return this.eq(0);
  };

  NodeList.prototype.text = function() {
    var arr = [];
    for (var i = 0; i < this._nodes.length; i++) {
      var t = this._nodes[i].text();
      if (t) arr.push(t);
    }
    return arr.join(" ").replace(/\s+/g, " ").trim();
  };

  NodeList.prototype.attr = function(name) {
    if (this._nodes.length === 0) return "";
    return this._nodes[0].attr(name);
  };

  NodeList.prototype.find = function(sel) {
    return findInNodes(this._nodes, sel);
  };

  function findInNodes(roots, selector) {
    if (!selector) return NodeList.empty();
    var parts = selector.trim().split(/\s+/);
    var currentNodes = roots.slice();

    for (var p = 0; p < parts.length; p++) {
      var subSel = parts[p];
      var nextLevel = [];
      for (var n = 0; n < currentNodes.length; n++) {
        var startNode = currentNodes[n];
        var matched = [];
        function walk(node, isRoot) {
          if (!isRoot && matchSingle(node, subSel)) {
            matched.push(node);
          }
          for (var c = 0; c < node.children.length; c++) {
            walk(node.children[c], false);
          }
        }
        walk(startNode, true);
        for (var m = 0; m < matched.length; m++) {
          if (nextLevel.indexOf(matched[m]) === -1) {
            nextLevel.push(matched[m]);
          }
        }
      }
      currentNodes = nextLevel;
    }
    return new NodeList(currentNodes);
  }

  function parseHtml(htmlStr) {
    if (!htmlStr) return new NodeList([]);
    var root = new Node("root", {});
    var current = root;

    var clean = String(htmlStr)
      .replace(/<!--[\s\S]*?-->/g, "")
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/<style[\s\S]*?<\/style>/gi, "");

    var tagRegex = /<(\/)?([a-zA-Z0-9_\-]+)([^>]*)>|([^<]+)/g;
    var match;

    while ((match = tagRegex.exec(clean)) !== null) {
      var isClose = !!match[1];
      var tagName = match[2];
      var rawAttrs = match[3];
      var textContent = match[4];

      if (textContent) {
        var t = textContent.trim();
        if (t) current.texts.push(t);
      } else if (tagName) {
        var lowerTag = tagName.toLowerCase();
        if (isClose) {
          var temp = current;
          while (temp && temp !== root && temp.tag !== lowerTag) {
            temp = temp.parent;
          }
          if (temp && temp !== root) {
            current = temp.parent || root;
          }
        } else {
          var attrs = parseAttrs(rawAttrs);
          var newNode = new Node(lowerTag, attrs);
          newNode.parent = current;
          current.children.push(newNode);

          var isSelfClosing = voidTags[lowerTag] || (rawAttrs && rawAttrs.trim().slice(-1) === "/");
          if (!isSelfClosing) {
            current = newNode;
          }
        }
      }
    }

    return {
      find: function(selector) {
        return findInNodes([root], selector);
      },
      text: function() {
        return root.text();
      }
    };
  }

  return {
    parse: parseHtml
  };
})();
''';
}

class CatPawRuntimePool {
  final http.Client _httpClient;
  final Map<String, CatPawJsRuntime> _pool = {};
  final Map<String, String> _scripts = {};
  bool _isDisposed = false;

  CatPawRuntimePool([http.Client? httpClient])
    : _httpClient = httpClient ?? http.Client();

  bool get isDisposed => _isDisposed;

  Future<CatPawJsRuntime> get(String sourceId, String script) async {
    if (_isDisposed) {
      throw StateError('CatPawRuntimePool 已经销毁');
    }
    if (_pool.containsKey(sourceId)) {
      if (_scripts[sourceId] == script) {
        return _pool[sourceId]!;
      }
      remove(sourceId);
    }

    final rt = CatPawJsRuntime(_httpClient);
    await rt.init(script);
    _pool[sourceId] = rt;
    _scripts[sourceId] = script;
    return rt;
  }

  void remove(String sourceId) {
    _scripts.remove(sourceId);
    final rt = _pool.remove(sourceId);
    rt?.dispose();
  }

  void clear() {
    for (final rt in _pool.values) {
      rt.dispose();
    }
    _pool.clear();
    _scripts.clear();
  }

  void disposeAll() {
    _isDisposed = true;
    clear();
  }
}
