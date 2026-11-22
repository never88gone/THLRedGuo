import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'account_pairing_crypto.dart';
import 'account_transfer_payload.dart';
import 'hongguo_account_service.dart';
import 'hongguo_account_session.dart';

class AccountPairingReceiver extends ChangeNotifier {
  AccountPairingReceiver({
    HongguoAccountSession? session,
    HongguoAccountService? service,
    this.allowLoopback = false,
    this.approveReplacement,
  }) : session = session ?? HongguoAccountSession.shared,
       service = service ?? HongguoAccountService(session: session);
  final HongguoAccountSession session;
  final HongguoAccountService service;
  final bool allowLoopback;
  final Future<bool> Function(String accountID)? approveReplacement;
  HttpServer? _server;
  Timer? _expiry;
  AccountPairingCode? code;
  String message = '正在准备设备配对';
  bool accepted = false;
  bool _closed = false, _processing = false;
  int? _receiverRevision;
  VerifiedAccountTransfer? _prepared;
  String? _transferID;
  final _seen = <String>{};
  final _peers = <HttpRequest>{};
  int _badRequests = 0;
  DateTime _rateWindow = DateTime.now();
  VoidCallback? onAccepted;
  List<String> addresses = [];
  bool get active => !_closed && !accepted && code != null && !code!.expired;
  Future<void> start({required String name, String? host}) async {
    if (_server != null || _closed) throw StateError('设备配对状态无效');
    if (allowLoopback && !kDebugMode) throw StateError('设备配对地址无效');
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: true,
    );
    final all = interfaces
        .expand((v) => v.addresses)
        .where((v) => accountPrivateAddress(v))
        .map((v) => v.address)
        .toSet()
        .toList();
    if (allowLoopback) all.insert(0, '127.0.0.1');
    if (_closed) return;
    addresses = all;
    final address = host ?? all.firstOrNull;
    if (address == null || !all.contains(address)) {
      throw StateError('请连接与手机相同的局域网后重试');
    }
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      return;
    }
    _server = server;
    _receiverRevision = session.revision;
    code = AccountPairingCode(
      id: accountRandom(
        16,
      ).map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
      host: address,
      port: server.port,
      name: name.substring(0, name.length.clamp(0, 80)),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
      key: accountRandom(32),
    );
    message = '使用手机糖葫芦 Haw 的“扫一扫登录其他设备”扫描';
    _expiry = Timer(const Duration(seconds: 120), () {
      message = '配对码已过期，请重新生成';
      stop();
    });
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object _) {
        if (!_closed) {
          message = '设备配对连接失败';
          stop();
        }
      },
    );
    notifyListeners();
  }

  Future<void> _handle(HttpRequest request) async {
    _peers.add(request);
    final response = request.response;
    var ownsProcessing = false;
    var connected = true;
    var committed = false;
    unawaited(
      response.done.then<void>(
        (_) {
          connected = false;
        },
        onError: (Object _, StackTrace _) {
          connected = false;
        },
      ),
    );
    response.headers.set('Cache-Control', 'no-store');
    response.headers.contentType = ContentType.json;
    response.persistentConnection = false;
    try {
      final remote = request.connectionInfo?.remoteAddress;
      if (!active ||
          session.revision != _receiverRevision ||
          remote == null ||
          !accountPrivateAddress(remote, allowLoopback: allowLoopback) ||
          request.method != 'POST' ||
          request.uri.path != '/thl/account-pair/v1' ||
          request.uri.hasQuery ||
          request.headers.value('Origin') != null ||
          request.headers.contentType?.mimeType != 'application/json' ||
          request.headers.contentLength < 1 ||
          request.headers.contentLength > 100 * 1024 ||
          _peers.length > 4) {
        throw const FormatException('PAIR_INVALID');
      }
      if (DateTime.now().difference(_rateWindow).inSeconds > 15) {
        _rateWindow = DateTime.now();
        _badRequests = 0;
      }
      if (_badRequests >= 6) throw const FormatException('PAIR_INVALID');
      final bytes = <int>[];
      await for (final part in request.timeout(const Duration(seconds: 5))) {
        if (bytes.length + part.length > 100 * 1024) {
          throw const FormatException('PAIR_INVALID');
        }
        bytes.addAll(part);
      }
      if (!active) throw const FormatException('PAIR_INVALID');
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map) throw const FormatException('PAIR_INVALID');
      final envelope = Map<String, dynamic>.from(raw);
      final nonce = envelope['nonce'];
      if (nonce is! String || _seen.contains(nonce) || _seen.length >= 20) {
        throw const FormatException('PAIR_INVALID');
      }
      final payload = await code!.open(envelope, response: false);
      _seen.add(nonce);
      final requestID = payload['requestId'];
      if (requestID is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(requestID)) {
        throw const FormatException('PAIR_INVALID');
      }
      if (payload['action'] == 'hello' &&
          payload.keys.every((k) => {'action', 'requestId'}.contains(k))) {
        final reply = await code!.seal({
          'requestId': requestID,
          'status': 'ready',
          'name': code!.name,
        }, response: true);
        response.write(jsonEncode(reply));
        await response.close();
        return;
      }
      if (payload['action'] == 'commit') {
        if (_processing ||
            _prepared == null ||
            payload['transferId'] != _transferID ||
            payload.keys.any(
              (k) => !{'action', 'requestId', 'transferId'}.contains(k),
            )) {
          throw const FormatException('PAIR_INVALID');
        }
        _processing = true;
        ownsProcessing = true;
        await service.commitTransferred(
          _prepared!,
          isCurrent: () =>
              active && connected && session.revision == _receiverRevision,
        );
        committed = true;
        _prepared = null;
        final reply = await code!.seal({
          'requestId': requestID,
          'status': 'accepted',
        }, response: true);
        accepted = true;
        message = '红果账号已登录';
        _expiry?.cancel();
        response.write(jsonEncode(reply));
        await response.close();
        if (!_closed) {
          await _server?.close();
          _server = null;
          notifyListeners();
          onAccepted?.call();
        }
        return;
      }
      if (payload['action'] != 'session' ||
          payload.keys.any(
            (k) => !{'action', 'requestId', 'session'}.contains(k),
          ) ||
          _processing ||
          _prepared != null) {
        throw const FormatException('PAIR_INVALID');
      }
      final candidate = AccountTransferPayload.decode(
        accountDecode64(payload['session'], max: 48 * 1024),
      );
      _processing = true;
      ownsProcessing = true;
      message = '正在校验手机授权的红果账号';
      notifyListeners();
      var success = false;
      try {
        if (session.loggedIn && candidate.id != session.id) {
          if (approveReplacement == null ||
              !await approveReplacement!(candidate.id)) {
            throw StateError('未确认切换账号');
          }
        }
        if (!active) throw StateError('设备配对已取消');
        _prepared = await service.prepareTransferred(
          candidate,
          isCurrent: () =>
              active && connected && session.revision == _receiverRevision,
          expectedRevision: _receiverRevision,
        );
        _transferID = requestID;
        success = true;
        message = '账号已验证，等待手机提交确认';
        notifyListeners();
      } catch (_) {
        if (active) {
          message = '账号校验未通过，原有账号与本地资料已保留';
          notifyListeners();
        }
      }
      final reply = await code!.seal({
        'requestId': requestID,
        'status': success ? 'validated' : 'rejected',
      }, response: true);
      response.write(jsonEncode(reply));
      await response.close();
    } catch (_) {
      if (ownsProcessing && !committed) {
        _prepared = null;
        _transferID = null;
      }
      if (committed && !_closed) {
        accepted = true;
        message = '红果账号已登录';
        _expiry?.cancel();
        unawaited(_server?.close(force: true));
        _server = null;
        notifyListeners();
        onAccepted?.call();
      }
      _badRequests++;
      try {
        response.statusCode = 400;
        response.write('{"error":"PAIR_INVALID"}');
        await response.close();
      } catch (_) {}
    } finally {
      if (ownsProcessing) _processing = false;
      _peers.remove(request);
    }
  }

  void stop() {
    if (_closed) return;
    _closed = true;
    _expiry?.cancel();
    service.dispose();
    unawaited(_server?.close(force: true));
    _server = null;
    for (final peer in _peers) {
      unawaited(peer.response.close().catchError((Object _) {}));
    }
    code = null;
    _prepared = null;
    _transferID = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
