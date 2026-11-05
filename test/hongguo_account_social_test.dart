import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/account/hongguo_account_social.dart';
import 'package:THLRedLook/core/account/hongguo_social_models.dart';
import 'package:THLRedLook/models/catalog/models.dart';

class _Service extends HongguoAccountService {
  _Service(HongguoAccountSession session) : super(session: session);
  bool fail = false;
  Completer<HongguoSocialSnapshot>? gate;
  HongguoSocialSnapshot value = const HongguoSocialSnapshot([
    HongguoEpisodeLike('7345678901234567998', 1, false, 10),
  ], []);
  @override
  Future<HongguoSocialSnapshot> social(Drama drama) async => value;
  @override
  Future<HongguoSocialSnapshot> setLiked(
    Drama drama,
    HongguoEpisodeLike episode,
    bool liked,
  ) async {
    if (fail) throw const HongguoAccountFailure('synthetic failure');
    return gate?.future ??
        HongguoSocialSnapshot([
          HongguoEpisodeLike(episode.id, episode.number, liked, 11),
        ], []);
  }
}

final drama = Drama(
  id: 'hongguo:7345678901234567999',
  source: 'hongguo',
  sourceId: '7345678901234567999',
  title: '合成',
  cover: '',
  description: '',
  episodes: 2,
);
Future<void> login(HongguoAccountSession session, String id) async {
  final jar = HongguoAccountCookies()
    ..merge(Uri.parse('https://hongguoduanju.com/'), [
      'sessionid=synthetic; Path=/; Secure',
    ]);
  await session.accept(jar, {'id': id}, expectedRevision: session.revision);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('失败保留已确认点赞状态，服务端确认后才更新', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final session = HongguoAccountSession();
    await session.bindProfile('social');
    await login(session, '123');
    final service = _Service(session);
    final controller = HongguoAccountSocial(service: service);
    addTearDown(controller.dispose);
    await controller.load(drama);
    final episode = controller.snapshot(drama)!.episode(1)!;
    service.fail = true;
    await expectLater(
      controller.like(drama, episode, true),
      throwsA(isA<HongguoAccountFailure>()),
    );
    expect(controller.snapshot(drama)!.episode(1)!.liked, false);
    service.fail = false;
    await controller.like(drama, episode, true);
    expect(controller.snapshot(drama)!.episode(1)!.liked, true);
  });
  test('账号切换后拒绝旧账号的进行中响应', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final session = HongguoAccountSession();
    await session.bindProfile('social-race');
    await login(session, '123');
    final service = _Service(session);
    final controller = HongguoAccountSocial(service: service);
    addTearDown(controller.dispose);
    await controller.load(drama);
    service.gate = Completer();
    final pending = controller.like(
      drama,
      controller.snapshot(drama)!.episode(1)!,
      true,
    );
    final rejected = expectLater(
      pending,
      throwsA(isA<HongguoAccountFailure>()),
    );
    await Future<void>.delayed(Duration.zero);
    await session.logout();
    await login(session, '456');
    service.gate!.complete(
      const HongguoSocialSnapshot([
        HongguoEpisodeLike('7345678901234567998', 1, true, 11),
      ], []),
    );
    await rejected;
    expect(controller.snapshot(drama), isNull);
    expect(controller.busy(drama), false);
  });
}
