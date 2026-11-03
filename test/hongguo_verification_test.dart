import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/account/hongguo_verification.dart';

void main() {
  test('验证页面只使用官方组件和匿名Cookie，拒绝二次验证与非官方脚本', () {
    final jar = HongguoAccountCookies()
      ..merge(Uri.parse(HongguoVerificationChallenge.origin), [
        'sessionid=synthetic-private-account; Path=/; Secure',
        'passport_csrf_token=synthetic-anonymous-csrf; Path=/; Secure',
        's_v_web_id=verify_synthetic_previous_123456; Path=/; Secure',
      ]);
    Map<String, dynamic> result() => {
      'rejected': true,
      'errorCode': 1105,
      'verification': {
        'kind': 'captcha',
        'origin': HongguoVerificationChallenge.origin,
        'script': HongguoVerificationChallenge.script,
        'aid': '513755',
        'repoId': 579047,
        'userAgent': 'synthetic-agent',
        'data': jsonEncode({
          'code': 10000,
          'detail': '</script><script>hostile()</script>',
        }),
      },
    };
    final challenge = HongguoVerificationChallenge.fromResult(result(), jar);
    final html = challenge.html(
      HongguoVerificationChallenge.newPageID(),
      'window.verifySDK={};',
    );
    expect(html, contains('synthetic-anonymous-csrf'));
    expect(
      challenge.cookies,
      contains(
        's_v_web_id=verify_synthetic_previous_123456; Path=/; Secure; SameSite=Lax',
      ),
    );
    expect(html, isNot(contains('synthetic-private-account')));
    expect(html, isNot(contains('</script><script>hostile()')));
    expect(challenge.toString(), isNot(contains('hostile')));
    expect(challenge.businessCode, '1105');
    final other = result();
    (other['verification'] as Map)['script'] = 'https://evil.test/script.js';
    expect(
      () => HongguoVerificationChallenge.fromResult(other, jar),
      throwsA(isA<HongguoAccountFailure>()),
    );
    final secondary = result();
    (secondary['verification'] as Map)['data'] = '{"code":20000}';
    expect(
      () => HongguoVerificationChallenge.fromResult(secondary, jar),
      throwsA(isA<HongguoAccountFailure>()),
    );
  });
}
