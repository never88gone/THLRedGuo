import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:THLRedLook/core/account/account_pairing_crypto.dart';
import 'package:THLRedLook/core/account/account_transfer_payload.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';

/// 设备扫码/局域网配对发送方（通常运行在手机端）
class AccountPairingSender {
  AccountPairingSender(
    this.code, {
    HongguoAccountSession? session,
    HongguoAccountService? service,
  }) : session = session ?? HongguoAccountSession.shared,
       service = service ?? HongguoAccountService(session: session) {
    _http.connectionTimeout = const Duration(seconds: 5);
    _http.findProxy = (_) => 'DIRECT';
    this.session.addListener(_accountChanged);
  }
  final AccountPairingCode code;
  final HongguoAccountSession session;
  final HongguoAccountService service;
  final HttpClient _http = HttpClient();
  bool _closed = false, _sent = false;
  int? _revision;
  String receiverName = '';
  void _accountChanged() {
    if (_revision != null && _revision != session.revision) {
      _closed = true;
      _http.close(force: true);
      service.dispose();
    }
  }

  Future<Map<String, dynamic>> _request(
    String action, {
    String? credentials,
    String? transferId,
  }) async {
    if (_closed || code.expired) throw StateError('设备配对已取消或过期');
    final id = accountRandom(
      16,
    ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    final envelope = await code.seal({
      'action': action,
      'requestId': id,
      'session': ?credentials,
      'transferId': ?transferId,
    }, response: false);
    final request = await _http
        .postUrl(code.endpoint)
        .timeout(const Duration(seconds: 6));
    if (_closed ||
        code.expired ||
        (action == 'session' || action == 'commit') &&
            _revision != session.revision) {
      request.abort();
      throw StateError('当前账号或设备配对已变化');
    }
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(envelope));
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw StateError('设备配对请求未通过');
    }
    final body = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 40))) {
      if (body.length + chunk.length > 100 * 1024) throw StateError('设备配对响应无效');
      body.addAll(chunk);
    }
    if (_closed || code.expired) throw StateError('设备配对已取消或过期');
    final value = jsonDecode(utf8.decode(body));
    if (value is! Map) throw StateError('设备配对响应无效');
    final result = await code.open(
      Map<String, dynamic>.from(value),
      response: true,
    );
    if (result['requestId'] != id) throw StateError('设备配对响应无效');
    return result;
  }

  Future<void> prepare() async {
    if (!session.loggedIn) throw StateError('请先在手机登录红果账号');
    final revision = session.revision;
    _revision = revision;
    await service.verify();
    if (_closed || revision != session.revision) throw StateError('当前账号已变化');
    _revision = revision;
    final response = await _request('hello');
    if (response['status'] != 'ready' ||
        response['name'] is! String ||
        (response['name'] as String).length > 80) {
      throw StateError('接收设备未就绪');
    }
    if (_closed || _revision != session.revision) throw StateError('当前账号已变化');
    receiverName = response['name'] as String;
  }

  Future<void> sendConfirmed() async {
    if (_sent ||
        _revision == null ||
        _revision != session.revision ||
        !session.verified) {
      throw StateError('当前账号或设备配对已变化');
    }
    final payload = AccountTransferPayload.decode(session.exportForPairing());
    _sent = true;
    final reply = await _request(
      'session',
      credentials: accountBase64(payload.encode()),
    );
    if (reply['status'] != 'validated' ||
        _closed ||
        _revision != session.revision) {
      throw StateError('接收设备未通过账号校验，原有资料已保留');
    }
    final result = await _request(
      'commit',
      transferId: reply['requestId'] as String,
    );
    if (result['status'] != 'accepted') throw StateError('接收设备未确认保存账号');
  }

  void dispose() {
    session.removeListener(_accountChanged);
    _closed = true;
    _http.close(force: true);
    service.dispose();
  }
}
