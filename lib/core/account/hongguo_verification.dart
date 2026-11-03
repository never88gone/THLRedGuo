import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'hongguo_account_session.dart';

class HongguoVerificationChallenge extends HongguoAccountFailure {
  HongguoVerificationChallenge._(
    this.data,
    this.userAgent,
    this.cookies,
    this.businessCode,
  ) : super('请先完成红果安全验证', 'CHALLENGE_REQUIRED');
  factory HongguoVerificationChallenge.fromResult(
    Map<String, dynamic> result,
    HongguoAccountCookies? jar,
  ) {
    final raw = result['verification'];
    if (result['rejected'] != true ||
        raw is! Map ||
        raw['kind'] != 'captcha' ||
        raw['script'] != script ||
        raw['aid'] != '513755' ||
        raw['repoId'] != 579047 ||
        raw['origin'] != origin ||
        raw['data'] is! String ||
        (raw['data'] as String).length > 32 * 1024 ||
        raw['userAgent'] is! String ||
        (raw['userAgent'] as String).length > 512) {
      throw const HongguoAccountFailure(
        '官方安全验证暂不支持，请使用红果 App 扫码登录',
        'VERIFICATION_UNSUPPORTED',
      );
    }
    final data = jsonDecode(raw['data'] as String);
    if (data is! Map || data['code'].toString() != '10000') {
      throw const HongguoAccountFailure(
        '官方安全验证数据无效，请重新发起登录',
        'VERIFICATION_INVALID',
      );
    }
    return HongguoVerificationChallenge._(
      Map<String, dynamic>.from(data),
      raw['userAgent'] as String,
      [
        for (final cookie in jar?.valid ?? <Map<String, dynamic>>[])
          if ({
            'passport_csrf_token',
            'passport_csrf_token_default',
            'reg-store-region',
          }.contains(cookie['name']))
            '${cookie['name']}=${cookie['value']}; Path=/; Secure; SameSite=Lax',
      ],
      RegExp(r'^-?\d{1,9}$').hasMatch('${result['errorCode']}')
          ? '${result['errorCode']}'
          : '',
    );
  }
  static const origin = 'https://hongguoduanju.com/';
  static const script =
      'https://lf-rc1.yhgfb-cn-static.com/obj/rc-verifycenter/verifycenter/@latest/index.js';
  final String businessCode;
  final Map<String, dynamic> data;
  final String userAgent;
  final List<String> cookies;
  static bool validFingerprint(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{16,256}$').hasMatch(value);
  static String newPageID() =>
      base64UrlEncode(AesGcm.with256bits().newNonce()).replaceAll('=', '');
  String html(String pageID, String sdkSource) {
    final config =
        jsonEncode({
              'id': pageID,
              'verifyData': data,
              'cookies': cookies,
              'sdk': sdkSource,
            })
            .replaceAll('<', r'\u003c')
            .replaceAll('>', r'\u003e')
            .replaceAll('&', r'\u0026');
    return '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><meta http-equiv="Cache-Control" content="no-store"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://lf-rc1.yhgfb-cn-static.com https://lf-rc2.yhgfb-cn-static.com https://lf-cdn-tos.bytescm.com; connect-src https://vcs.zijieapi.com https://verify.zijieapi.com https://verify.snssdk.com https://verify-s-sg.byteintl.com https://verify-s-va.byteintl.com https://verify-s.byteintlapi.com https://verify.byteintlapi.com; img-src data: blob: https://*.byteimg.com https://*.douyinpic.com https://*.ibytedtos.com https://*.bytedtos.com https://*.yhgfb-cn-static.com https://lf-cdn-tos.bytescm.com; style-src 'unsafe-inline'; frame-src https://rmc.bytedance.com https://*.snssdk.com https://*.zijieapi.com; font-src data:; base-uri 'none'; form-action 'none'"><style>body{margin:0;background:#fff;font:16px system-ui;color:#222}#state{padding:24px;text-align:center}</style></head><body><div id="state">正在加载红果安全验证</div><script>
const config=$config;
let completed=false;
function reply(event,fp){if(completed&&event!=='ready')return;if(event!=='ready')completed=true;const state=document.getElementById('state');if(state)state.textContent=event==='error'?'安全验证加载失败，请返回重试':'';if(window.flutter_inappwebview)window.flutter_inappwebview.callHandler('THLVerify',{id:config.id,event,fp:fp||''});}
async function start(){try{for(const value of config.cookies)document.cookie=value;const sdk=window.verifySDK;if(!sdk||!sdk.initVerifyOptions||!sdk.getCaptchaWebId||!sdk.autoRender)throw Error('sdk');sdk.initVerifyOptions({commonOptions:{aid:513755,iid:'0',did:'0',repoId:579047},captchaOptions:{logConfig:{sample_rate:0}}});const fp=await sdk.getCaptchaWebId();if(typeof fp!=='string'||!fp)throw Error('fp');reply('ready');sdk.autoRender({verify_data:config.verifyData,captchaOptions:{fp,successCb:async()=>reply('success',await sdk.getCaptchaWebId()),closeCb:()=>reply('cancel'),errorCb:()=>reply('error')}});}catch(_){reply('error');}}
let launched=false;function load(){if(launched)return;launched=true;const script=document.createElement('script');try{script.textContent=config.sdk;document.head.appendChild(script);start();}catch(_){reply('error');}}if(window.flutter_inappwebview&&window.flutter_inappwebview.callHandler)load();else window.addEventListener('flutterInAppWebViewPlatformReady',load,{once:true});
</script></body></html>''';
  }

  @override
  String toString() => 'HongguoVerificationChallenge([redacted])';
}

typedef HongguoVerificationResolver =
    Future<String?> Function(HongguoVerificationChallenge challenge);
