import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  final source = File('assets/sources/hongguo.js').readAsStringSync();
  const id = '7345678901234567000';
  const url = 'https://v5-reading-video.qznovelvod.com/synthetic.mp4';
  Future<CatPawPlayResult> resolve(
    List<String> variants,
    List<String> probes, {
    Set<String> rejected = const {},
  }) async {
    final client = MockClient((r) async {
      expect(r.method, 'HEAD');
      probes.add(r.url.toString());
      return http.Response(
        '',
        rejected.contains(r.url.toString()) ? 403 : 200,
        headers: {'content-type': 'video/mp4'},
      );
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init('''
${source.replaceFirst('const existingPlay = spider.play;', "const existingPlay = async function(){return {url:''};};")}
HongguoApp.fetchAppPlayUrl=async function(){return {variants:[${variants.map((v) => "{vid:'$id',quality:'720p',url:'$v'}").join(',')}]};};
''');
    return runtime.play(
      '',
      '7345678901234567100_$id',
      flags: [
        {'avoidUrl': url},
      ],
    );
  }

  test(
    'the only route is revalidated after a temporary player failure',
    () async {
      final probes = <String>[];
      final result = await resolve([url], probes);
      expect(result.url, url);
      expect(probes, [url]);
    },
  );
  test('an alternative route remains preferred', () async {
    const alternate = 'https://v5-reading-video.qznovelvod.com/alternate.mp4';
    final probes = <String>[];
    expect((await resolve([url, alternate], probes)).url, alternate);
    expect(probes, [alternate]);
  });
  test(
    'failed alternatives do not permanently exclude a now healthy route',
    () async {
      const alternate = 'https://v5-reading-video.qznovelvod.com/alternate.mp4';
      final probes = <String>[];
      expect(
        (await resolve([url, alternate], probes, rejected: {alternate})).url,
        url,
      );
      expect(probes, [alternate, url]);
    },
  );
  test('denied media keeps a useful error code and bounded probes', () async {
    final probes = <String>[];
    final result = await resolve([url], probes, rejected: {url});
    expect(result.url, isEmpty);
    expect(result.errorCode, 'MEDIA_HTTP_403');
    expect(probes.length, lessThanOrEqualTo(5));
  });
}
