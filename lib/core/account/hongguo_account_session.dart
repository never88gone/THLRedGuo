import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class HongguoAccountFailure implements Exception {
  const HongguoAccountFailure(this.message, [this.code = 'ACCOUNT_FAILED']);
  final String message;
  final String code;
  @override
  String toString() => message;
}

class HongguoAccountCookies {
  HongguoAccountCookies([List<Map<String, dynamic>>? values])
    : _values = values ?? [];
  final List<Map<String, dynamic>> _values;
  static const credentialNames = {
    'sessionid',
    'sessionid_ss',
    'sid_guard',
    'sid_tt',
    'uid_tt',
    'uid_tt_ss',
    'sid_ucp_v1',
    'ssid_ucp_v1',
    'passport_auth_status',
    'passport_auth_status_ss',
  };
  void merge(Uri uri, List<String> headers) {
    if (uri.scheme != 'https' || uri.host != 'hongguoduanju.com') return;
    for (final header in headers) {
      try {
        final cookie = Cookie.fromSetCookieValue(header);
        final domain = (cookie.domain ?? uri.host)
            .replaceFirst(RegExp(r'^\.'), '')
            .toLowerCase();
        if (domain != uri.host) continue;
        final path = cookie.path ?? '/';
        _values.removeWhere(
          (v) =>
              v['name'] == cookie.name &&
              v['domain'] == domain &&
              v['path'] == path,
        );
        final expires = cookie.maxAge != null
            ? DateTime.now().add(Duration(seconds: cookie.maxAge!))
            : cookie.expires;
        if (expires != null && !expires.isAfter(DateTime.now())) continue;
        _values.add({
          'name': cookie.name,
          'value': cookie.value,
          'domain': domain,
          'path': path,
          'expires': expires?.millisecondsSinceEpoch,
        });
      } catch (_) {}
    }
  }

  Iterable<Map<String, dynamic>> get valid => _values.where(
    (v) =>
        v['name'] is String &&
        v['value'] is String &&
        v['domain'] == 'hongguoduanju.com' &&
        (v['expires'] == null ||
            (v['expires'] as num) > DateTime.now().millisecondsSinceEpoch),
  );
  bool get hasSession =>
      valid.any((v) => {'sessionid', 'sessionid_ss'}.contains(v['name']));
  String websiteHeader(Uri uri) =>
      uri.scheme == 'https' && uri.host == 'hongguoduanju.com'
      ? valid
            .where((v) => _pathMatches(uri.path, v['path'] as String? ?? '/'))
            .map((v) => '${v['name']}=${v['value']}')
            .join('; ')
      : '';
  static bool _pathMatches(String path, String scope) =>
      path == scope || path.startsWith(scope.endsWith('/') ? scope : '$scope/');
  String get businessHeader => valid
      .where((v) => credentialNames.contains(v['name']))
      .map((v) => '${v['name']}=${v['value']}')
      .join('; ');
  String get csrf =>
      valid
          .where((v) => v['name'] == 'passport_csrf_token')
          .map((v) => v['value'] as String)
          .firstOrNull ??
      '';
  List<Map<String, dynamic>> toJson() =>
      valid.map((v) => Map<String, dynamic>.from(v)).toList();
}

class HongguoAccountSession extends ChangeNotifier {
  static final shared = HongguoAccountSession();
  HongguoAccountSession({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );
  final FlutterSecureStorage _storage;
  String _profile = '';
  int revision = 0;
  HongguoAccountCookies? _cookies;
  String? deviceSession;
  String id = '';
  String nickname = '';
  String? error;
  bool verified = false;
  bool get loggedIn => _cookies?.hasSession == true;
  String get profile => _profile;
  String get _key =>
      'thl.hongguo.account.${base64Url.encode(utf8.encode(_profile))}';
  Future<void> _writes = Future.value();
  Future<void> bindProfile(String profile) async {
    if (_profile == profile) return;
    _profile = profile;
    final generation = ++revision;
    final storageKey = _key;
    _cookies = null;
    deviceSession = null;
    id = '';
    nickname = '';
    verified = false;
    error = null;
    notifyListeners();
    try {
      await _writes;
      final raw = await _storage.read(key: storageKey);
      if (generation != revision || raw == null) return;
      final data = jsonDecode(raw) as Map;
      final cookies = HongguoAccountCookies(
        (data['cookies'] as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList(),
      );
      if (!cookies.hasSession) return;
      _cookies = cookies;
      deviceSession = data['device'] as String?;
      id = data['id'] as String;
      nickname = data['nickname'] as String;
      error = '登录状态待确认';
      revision++;
    } catch (_) {
      if (generation == revision) error = '账号安全存储暂不可用，请重试';
    } finally {
      notifyListeners();
    }
  }

  Future<void> accept(
    HongguoAccountCookies cookies,
    Map<String, dynamic> account, {
    required int expectedRevision,
    String? device,
  }) async {
    if (expectedRevision != revision || !cookies.hasSession) {
      throw const HongguoAccountFailure('登录操作已取消', 'CANCELLED');
    }
    final accountId = account['id']?.toString() ?? '';
    if (!RegExp(r'^\d{1,30}$').hasMatch(accountId)) {
      throw const HongguoAccountFailure('账号资料验证失败', 'ACCOUNT_INVALID');
    }
    final key = _key;
    final value = jsonEncode({
      'cookies': cookies.toJson(),
      'device': device,
      'id': accountId,
      'nickname': account['nickname']?.toString() ?? '红果用户',
    });
    final write = _writes.then((_) => _storage.write(key: key, value: value));
    _writes = write.catchError((Object _) {});
    await write;
    if (expectedRevision != revision) {
      throw const HongguoAccountFailure('登录操作已取消', 'CANCELLED');
    }
    _cookies = cookies;
    deviceSession = device;
    id = accountId;
    nickname = account['nickname']?.toString() ?? '红果用户';
    verified = true;
    error = null;
    revision++;
    notifyListeners();
  }

  void confirm(Map<String, dynamic> account, int expectedRevision) {
    if (expectedRevision != revision || account['id']?.toString() != id) return;
    verified = true;
    error = null;
    nickname = account['nickname']?.toString() ?? nickname;
    notifyListeners();
  }

  Future<void> logout() async {
    final key = _key;
    _cookies = null;
    deviceSession = null;
    id = '';
    nickname = '';
    verified = false;
    error = null;
    revision++;
    notifyListeners();
    final write = _writes.then((_) => _storage.delete(key: key));
    _writes = write.catchError((Object _) {});
    await write;
  }

  static bool businessUrl(Uri uri) =>
      uri.scheme == 'https' &&
      !uri.hasPort &&
      (uri.host == 'reading.snssdk.com' ||
          uri.host == 'api5-normal.fqnovel.com' ||
          RegExp(
            r'^api[0-9]+-normal-sinfonline[a-z]\.fqnovel\.com$',
          ).hasMatch(uri.host)) &&
      (uri.path.startsWith('/reading/') || uri.path.startsWith('/novel/'));
  String headerFor(Uri uri) =>
      businessUrl(uri) ? _cookies?.businessHeader ?? '' : '';
}
