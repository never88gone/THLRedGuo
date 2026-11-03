import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/account/account_pairing_crypto.dart';
import 'package:THLRedLook/core/account/account_pairing_service.dart';
import 'package:THLRedLook/core/account/account_transfer_payload.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';

class _SyntheticService extends HongguoAccountService {
  _SyntheticService(HongguoAccountSession session) : super(session: session);
  bool fail = false;
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<void> verify() async {}
  @override
  Future<VerifiedAccountTransfer> prepareTransferred(
    AccountTransferPayload candidate, {
    required bool Function() isCurrent,
    int? expectedRevision,
  }) async {
    if (!entered.isCompleted) entered.complete();
    if (gate != null) await gate!.future;
    if (fail || !isCurrent()) throw StateError('合成拒绝');
    return VerifiedAccountTransfer(candidate, {
      'id': candidate.id,
      'nickname': '合成账号',
    }, expectedRevision ?? session.revision);
  }
}

Future<HongguoAccountSession> _session(
  String profile, {
  bool loggedIn = false,
}) async {
  final session = HongguoAccountSession();
  await session.bindProfile(profile);
  if (loggedIn) {
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-test-session; Path=/; Secure',
        'passport_csrf_token=synthetic-csrf; Path=/; Secure',
        'ttwid=synthetic-region; Path=/; Secure',
      ]);
    await session.accept(
      cookies,
      {'id': '1234567890123456789', 'nickname': '合成账号'},
      expectedRevision: session.revision,
      device: jsonEncode({
        'iid': '7345678901234567200',
        'device_id': '7345678901234567100',
        'cdid': 'synthetic-device',
      }),
    );
  }
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('与 Node 标准库独立生成的 HKDF AES-GCM 向量互通，拒绝篡改与方向混用', () async {
    final vector =
        jsonDecode(
              await File(
                'test/fixtures/account_pairing_vector.json',
              ).readAsString(),
            )
            as Map;
    final code = AccountPairingCode(
      id: vector['id'] as String,
      host: '192.168.1.2',
      port: 3000,
      name: '合成设备',
      expiresAt: DateTime.now().add(const Duration(seconds: 60)),
      key: accountDecode64(vector['key'], max: 32),
    );
    final envelope = Map<String, dynamic>.from(vector['envelope'] as Map);
    expect(await code.open(envelope, response: false), vector['payload']);
    await expectLater(code.open(envelope, response: true), throwsA(anything));
    final tampered = Map<String, dynamic>.from(envelope)
      ..['cipher'] = accountBase64([1, 2, 3]);
    await expectLater(code.open(tampered, response: false), throwsA(anything));
  });
  test('只接受短期局域网 IP 配对码，密钥不进入 HTTP URL', () async {
    final code = AccountPairingCode(
      id: '0123456789abcdef0123456789abcdef',
      host: '192.168.1.2',
      port: 3000,
      name: '合成电视',
      expiresAt: DateTime.now().add(const Duration(seconds: 60)),
      key: List.filled(32, 42),
    );
    final parsed = AccountPairingCode.parse(code.encode());
    expect(
      parsed.endpoint.toString(),
      'http://192.168.1.2:3000/thl/account-pair/v1',
    );
    expect(
      parsed.endpoint.toString(),
      isNot(contains(accountBase64(List.filled(32, 42)))),
    );
    for (final host in [
      '8.8.8.8',
      '127.0.0.1',
      '169.255.1.1',
      'example.com',
      'localhost',
    ]) {
      expect(
        () => AccountPairingCode.parse(
          code.encode().replaceFirst('192.168.1.2', host),
        ),
        throwsFormatException,
      );
    }
    expect(accountPrivateAddress(InternetAddress('fc00::123')), true);
    expect(
      accountPrivateAddress(InternetAddress('2001:4860:4860::8888')),
      false,
    );
    final expired = AccountPairingCode(
      id: code.id,
      host: code.host,
      port: code.port,
      name: code.name,
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      key: List.filled(32, 42),
    );
    expect(
      () => AccountPairingCode.parse(expired.encode()),
      throwsFormatException,
    );
  });
  test('授权包仅含允许的会话和绑定设备，排除CSRF、地区、固定配置和本地资料', () async {
    final sender = await _session('payload', loggedIn: true);
    final data = jsonDecode(utf8.decode(sender.exportForPairing())) as Map;
    expect(data.keys.toSet(), {'v', 'id', 'cookies', 'device'});
    expect((data['cookies'] as List).map((v) => v['name']), ['sessionid']);
    final candidate = AccountTransferPayload.decode(sender.exportForPairing());
    expect(candidate.id, sender.id);
    data['material'] = 'forbidden';
    expect(
      () => AccountTransferPayload.decode(utf8.encode(jsonEncode(data))),
      throwsFormatException,
    );
  });
  test('HTTP 收发完成应用层加密；收到确认才保存，成功后配对码失效', () async {
    final senderSession = await _session('sender', loggedIn: true),
        receiverSession = await _session('receiver');
    final receiver = AccountPairingReceiver(
      session: receiverSession,
      service: _SyntheticService(receiverSession),
      allowLoopback: true,
    );
    addTearDown(receiver.dispose);
    await receiver.start(name: '合成电脑', host: '127.0.0.1');
    final sender = AccountPairingSender(
      AccountPairingCode.parse(receiver.code!.encode(), allowLoopback: true),
      session: senderSession,
      service: _SyntheticService(senderSession),
    );
    addTearDown(sender.dispose);
    await sender.prepare();
    expect(receiverSession.loggedIn, false);
    expect(sender.receiverName, '合成电脑');
    await sender.sendConfirmed();
    expect(receiverSession.id, senderSession.id);
    expect(receiverSession.verified, true);
    expect(receiver.accepted, true);
    expect(receiver.active, false);
    expect(
      receiverSession.headerFor(
        Uri.parse('https://reading.snssdk.com/reading/user/info/v1/'),
      ),
      'sessionid=synthetic-test-session',
    );
  });
  test('账号验证失败和配对页面关闭都保留接收端原有账号', () async {
    final senderSession = await _session('sender-failed', loggedIn: true),
        receiverSession = await _session('receiver-kept', loggedIn: true);
    final original = receiverSession.id;
    final service = _SyntheticService(receiverSession)..fail = true;
    final receiver = AccountPairingReceiver(
      session: receiverSession,
      service: service,
      allowLoopback: true,
    );
    addTearDown(receiver.dispose);
    await receiver.start(name: '合成电脑', host: '127.0.0.1');
    final sender = AccountPairingSender(
      AccountPairingCode.parse(receiver.code!.encode(), allowLoopback: true),
      session: senderSession,
      service: _SyntheticService(senderSession),
    );
    addTearDown(sender.dispose);
    await sender.prepare();
    await expectLater(sender.sendConfirmed(), throwsA(isA<StateError>()));
    expect(receiverSession.id, original);
    expect(receiver.accepted, false);
    receiver.stop();
    expect(receiver.code, isNull);
  });
  test('接收设备切换本地用户后，旧配对不能把账号写入新用户', () async {
    final senderSession = await _session('sender-owner', loggedIn: true),
        receiverSession = await _session('receiver-owner');
    final receiver = AccountPairingReceiver(
      session: receiverSession,
      service: _SyntheticService(receiverSession),
      allowLoopback: true,
    );
    addTearDown(receiver.dispose);
    await receiver.start(name: '合成电脑', host: '127.0.0.1');
    final sender = AccountPairingSender(
      AccountPairingCode.parse(receiver.code!.encode(), allowLoopback: true),
      session: senderSession,
      service: _SyntheticService(senderSession),
    );
    addTearDown(sender.dispose);
    await sender.prepare();
    await receiverSession.bindProfile('different-user');
    await expectLater(sender.sendConfirmed(), throwsA(isA<StateError>()));
    expect(receiverSession.loggedIn, false);
  });
  test('发送端撤销或换账号时关闭在途连接，接收端不保存迟到会话', () async {
    final senderSession = await _session('sender-cancel', loggedIn: true),
        receiverSession = await _session('receiver-cancel');
    final service = _SyntheticService(receiverSession)
      ..gate = Completer<void>();
    final receiver = AccountPairingReceiver(
      session: receiverSession,
      service: service,
      allowLoopback: true,
    );
    addTearDown(receiver.dispose);
    await receiver.start(name: '合成电脑', host: '127.0.0.1');
    final sender = AccountPairingSender(
      AccountPairingCode.parse(receiver.code!.encode(), allowLoopback: true),
      session: senderSession,
      service: _SyntheticService(senderSession),
    );
    addTearDown(sender.dispose);
    await sender.prepare();
    final result = expectLater(sender.sendConfirmed(), throwsA(anything));
    await service.entered.future;
    await senderSession.logout();
    await result;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    service.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(receiverSession.loggedIn, false);
  });
  test('同一个认证数据包不能重放，HTTP 报文不含明文账号 Cookie 或临时密钥', () async {
    final session = await _session('receiver-replay');
    final receiver = AccountPairingReceiver(
      session: session,
      service: _SyntheticService(session),
      allowLoopback: true,
    );
    addTearDown(receiver.dispose);
    await receiver.start(name: '合成设备', host: '127.0.0.1');
    final code = receiver.code!;
    final envelope = await code.seal({
      'action': 'hello',
      'requestId': '0123456789abcdef0123456789abcdef',
    }, response: false);
    final body = jsonEncode(envelope);
    expect(body, isNot(contains('synthetic-test-session')));
    final uri = Uri.parse(code.encode());
    expect(body, isNot(contains(Uri.splitQueryString(uri.fragment)['key']!)));
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    Future<int> send() async {
      final request = await client.postUrl(code.endpoint);
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    expect(await send(), 200);
    expect(await send(), 400);
  });
}
