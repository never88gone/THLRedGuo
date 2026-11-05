import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/core/account/hongguo_social_models.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/js/hongguo_guest_session.dart';
import 'package:THLRedLook/core/account/account_transfer_payload.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';

class _Reply extends Stream<List<int>> implements HttpClientResponse {
  _Reply(this.payload, [List<String> cookies = const [], this.statusCode = 200])
    : headers = _Headers(cookies);
  final Object payload;
  @override
  final HttpHeaders headers;
  @override
  final int statusCode;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(payload))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  _Headers([this.cookies = const []]);
  final List<String> cookies;
  final fields = <String, Object>{};
  @override
  List<String>? operator [](String name) =>
      name == HttpHeaders.setCookieHeader ? cookies : null;
  @override
  String? value(String name) {
    final value = fields[name];
    if (value is Exception) throw value;
    return value?.toString();
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    fields[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.uri, this.respond);
  @override
  final Uri uri;
  final _Reply Function(Uri, _Headers) respond;
  @override
  final _Headers headers = _Headers();
  final bodyText = StringBuffer();
  @override
  void write(Object? object) => bodyText.write(object);
  @override
  bool followRedirects = true;
  bool aborted = false;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
  }

  @override
  Future<HttpClientResponse> close() async {
    if (bodyText.isNotEmpty) {
      headers.fields['synthetic-body'] = bodyText.toString();
    }
    return respond(uri, headers);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.respond);
  final _Reply Function(Uri, _Headers) respond;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(url, respond);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeferredClient extends _Client {
  _DeferredClient(super.respond);
  final opened = Completer<void>();
  final release = Completer<void>();
  late _Request pending;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    pending = _Request(url, respond);
    opened.complete();
    await release.future;
    return pending;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SourceDiagnostics.shared.clear();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      HongguoGuestSession.sessionKey: jsonEncode({
        'iid': '7345678901234567200',
        'device_id': '7345678901234567100',
        'cdid': 'synthetic-device',
      }),
    });
  });
  test('官方视频书架写入后回读确认，进度按毫秒上报并按剧读取，携带当前账号', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-writeback');
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-writeback; Path=/; Secure',
      ]);
    await session.accept(cookies, {
      'id': '123',
      'nickname': 'synthetic',
    }, expectedRevision: session.revision);
    final drama = Drama(
      id: 'hongguo:7688558312157088793',
      source: 'hongguo',
      sourceId: '7688558312157088793',
      title: 'synthetic',
      cover: '',
      description: '',
      episodes: 60,
    );
    var followed = false, updates = 0, reads = 0;
    Map<String, dynamic>? saved;
    await HttpOverrides.runZoned(
      () async {
        final service = HongguoAccountService(session: session);
        addTearDown(service.dispose);
        await service.setFollowing(drama, true);
        await service.setFollowing(drama, false);
        await service.updateProgress(
          WatchEntry(
            drama: drama,
            episode: 4,
            position: 12.345,
            duration: 95.678,
            updatedAt: DateTime.now(),
          ),
          itemId: '7688558312157088794',
        );
        final progress = await service.progress(drama);
        expect(progress!.episode, 4);
        expect(progress.position, 12.345);
        expect(progress.duration, 95.678);
        expect(updates, 2);
        expect(reads, 2);
      },
      createHttpClient: (_) => _Client((uri, headers) {
        expect(
          headers.value('Cookie'),
          contains('sessionid=synthetic-writeback'),
        );
        if (uri.path.endsWith('/bookshelf/video/update/v1/')) {
          updates++;
          final body = jsonDecode(headers.value('synthetic-body')!) as Map;
          final row =
              (body['update_bookshelf_video_list'] as List).single as Map;
          expect(row['book_id'], drama.sourceId);
          expect(row['book_type'], 2);
          followed = row['video_shelf_operate_type'] == 0;
          return _Reply({'code': 0});
        }
        if (uri.path.endsWith('/bookshelf/video/list/v1/')) {
          reads++;
          return _Reply({
            'code': 0,
            'data': {
              'video_shelf_info': [
                if (followed) {'book_id': drama.sourceId},
              ],
            },
          });
        }
        if (uri.path.endsWith('/read_progress/upload/v1/')) {
          final body = jsonDecode(headers.value('synthetic-body')!) as Map;
          expect(body['write_mode'], 1);
          saved = Map<String, dynamic>.from(
            (body['books'] as List).single as Map,
          );
          expect(saved!['item_id'], '7688558312157088794');
          expect(saved!['vid_index'], 4);
          expect(saved!['current_play_time'], 12345);
          expect(saved!['current_total_time'], 95678);
          return _Reply({'code': 0});
        }
        expect(uri.path, '/reading/bookapi/read_progress/get/v1/');
        final body = jsonDecode(headers.value('synthetic-body')!) as Map;
        expect((body['book_ids'] as Map)['2'], [int.parse(drama.sourceId)]);
        return _Reply({
          'code': 0,
          'video_data': [
            {
              ...saved!,
              'vid': saved!['item_id'],
              'last_watch_time': 1700000000000,
            },
          ],
        });
      }),
    );
  });
  test('传入账号先使用候选设备与轮转Cookie校验，提交前不覆盖当前账号', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('candidate-device');
    final candidate = AccountTransferPayload.decode(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'id': '123',
          'cookies': [
            {
              'name': 'sessionid',
              'value': 'synthetic-before',
              'domain': 'hongguoduanju.com',
              'path': '/',
              'expires': null,
            },
          ],
          'device': {
            'iid': '7345678901234567999',
            'device_id': '7345678901234567888',
            'cdid': 'synthetic-candidate',
          },
        }),
      ),
    );
    final service = HongguoAccountService(session: session);
    addTearDown(service.dispose);
    await HttpOverrides.runZoned(
      () async {
        final proof = await service.prepareTransferred(
          candidate,
          isCurrent: () => true,
        );
        expect(session.loggedIn, false);
        await service.commitTransferred(proof, isCurrent: () => true);
        expect(session.id, '123');
        expect(
          jsonDecode(session.deviceSession!)['device_id'],
          '7345678901234567888',
        );
      },
      createHttpClient: (_) => _Client((uri, headers) {
        if (uri.path == '/passport/account/info/v2/') {
          expect(headers.value('Cookie'), 'sessionid=synthetic-before');
          return _Reply(
            {'message': 'success', 'data': {}},
            ['sessionid=synthetic-rotated; Path=/; Secure'],
          );
        }
        expect(uri.path, '/reading/user/info/v1/');
        expect(uri.queryParameters['device_id'], '7345678901234567888');
        expect(headers.value('Cookie'), 'sessionid=synthetic-rotated');
        return _Reply({
          'code': 0,
          'data': {'biz_user_id': '123', 'user_name': '合成'},
        });
      }),
    );
  });
  test('轮询状态未到confirmed但已签发会话时完成App账号校验', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-flow');
    final paths = <String>[];
    await HttpOverrides.runZoned(
      () async {
        final service = HongguoAccountService(session: session);
        addTearDown(service.dispose);
        final login = await service.begin();
        expect(await service.poll(login), isTrue);
        expect(session.loggedIn, isTrue);
        expect(paths, [
          '/passport/web/get_qrcode/',
          '/passport/web/check_qrconnect/',
          '/passport/account/info/v2/',
          '/reading/user/info/v1/',
        ]);
      },
      createHttpClient: (_) => _Client((uri, headers) {
        paths.add(uri.path);
        if (uri.path.endsWith('/get_qrcode/')) {
          return _Reply({
            'message': 'success',
            'data': {
              'token': 'synthetic-token',
              'qrcode_index_url':
                  'https://reading.snssdk.com/reading_offline/novelread/page/scan-code.html?token=synthetic-token',
              'expire_time': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60,
            },
          });
        }
        if (uri.path.endsWith('/check_qrconnect/')) {
          return _Reply(
            {
              'message': 'success',
              'data': {'status': 'scanned'},
            },
            ['sessionid=synthetic-session; Path=/; Secure'],
          );
        }
        if (uri.path == '/passport/account/info/v2/') {
          return _Reply({'message': 'success', 'data': {}});
        }
        expect(headers.value('Cookie'), 'sessionid=synthetic-session');
        return _Reply({
          'code': 0,
          'data': {
            'biz_user_id': '1234567890123456789',
            'user_name': 'synthetic',
          },
        });
      }),
    );
  });
  test('账号校验暂时失败后复用已确认会话，不重查已消费二维码', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-retry');
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-session; Path=/; Secure',
      ]);
    final login = HongguoQrLogin(
      'synthetic',
      DateTime.now().subtract(const Duration(seconds: 1)),
      'synthetic-token',
      cookies,
      session.revision,
    );
    var profileRequests = 0;
    await HttpOverrides.runZoned(
      () async {
        final service = HongguoAccountService(session: session);
        addTearDown(service.dispose);
        await expectLater(
          service.poll(login),
          throwsA(
            isA<HongguoAccountFailure>().having(
              (e) => e.code,
              'business code',
              'BUSINESS_15',
            ),
          ),
        );
        expect(login.confirmed, isTrue);
        expect(await service.poll(login), isTrue);
        expect(profileRequests, 2);
        expect(session.loggedIn, isTrue);
      },
      createHttpClient: (_) => _Client((uri, headers) {
        expect(uri.path, isNot('/passport/web/check_qrconnect/'));
        if (uri.path == '/passport/account/info/v2/') {
          return _Reply({'message': 'success', 'data': {}});
        }
        profileRequests++;
        if (profileRequests == 1) return _Reply({'code': 15, 'data': {}});
        return _Reply({
          'code': 0,
          'data': {
            'biz_user_id': '1234567890123456789',
            'user_name': 'synthetic',
          },
        });
      }),
    );
  });
  test('账号追剧和历史使用当前会话并补齐剧集资料，大整数和毫秒进度不丢失', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-library');
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-library; Path=/; Secure',
      ]);
    await session.accept(cookies, {
      'id': '123',
      'nickname': '合成',
      'avatar': 'https://example.test/avatar',
    }, expectedRevision: session.revision);
    final service = HongguoAccountService(session: session);
    addTearDown(service.dispose);
    await HttpOverrides.runZoned(
      () async {
        final follows = await service.library(history: false);
        expect(follows.single.drama.cleanSourceId, '7688558312157088793');
        expect(follows.single.drama.title, '合成剧详情');
        final history = await service.library(history: true);
        expect(history.single.drama.title, '合成剧详情');
        expect(history.single.episode, 12);
        expect(history.single.position, 23.5);
        expect(history.single.duration, 90);
        expect(history.single.drama.episodes, 120);
        expect(history.single.updatedAt.millisecondsSinceEpoch, 1700000000000);
      },
      createHttpClient: (_) => _Client((uri, headers) {
        expect(headers.value('Cookie'), 'sessionid=synthetic-library');
        if (uri.path.contains('/bookshelf/')) {
          expect(uri.path, '/reading/bookapi/bookshelf/video/list/v1/');
          expect(uri.queryParameters['target_user_id'], '123');
          return _Reply({
            'code': 0,
            'data': {
              'video_shelf_info': [
                {
                  'series_id': '7688558312157088793',
                  'book_type': 2,
                  'collect_time': 1700000000,
                },
              ],
            },
          });
        }
        if (uri.path.contains('/read_progress/')) {
          expect(uri.queryParameters['limit'], '50');
          return _Reply({
            'code': 0,
            'data': null,
            'video_data': [
              {
                'series_id': '7688558312157088793',
                'vid': '1234567890123456789',
                'vid_index': 12,
                'current_play_time': 23500,
                'current_total_time': 90000,
                'last_watch_time': 1700000000,
              },
            ],
          });
        }
        expect(uri.path, '/reading/bookapi/multi-detail/v1/');
        expect(uri.queryParameters['book_id'], '7688558312157088793');
        return _Reply({
          'code': 0,
          'data': [
            {
              'book_id': '7688558312157088793',
              'book_name': '合成剧详情',
              'episode_cnt': 120,
            },
          ],
        });
      }),
    );
    await session.bindProfile('other');
    await session.bindProfile('synthetic-library');
    expect(session.avatar, 'https://example.test/avatar');
    await session.logout();
    expect(session.avatar, isEmpty);
  });
  test('创作者关注只接受用户 ID，不把展示用红果号作为关注目标', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-creator-identity');
    final jar = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-creator-identity; Path=/; Secure',
      ]);
    await session.accept(jar, {
      'id': '123',
    }, expectedRevision: session.revision);
    final service = HongguoAccountService(session: session);
    addTearDown(service.dispose);
    final drama = Drama(
      id: 'hongguo:7688558312157088793',
      source: 'hongguo',
      sourceId: '7688558312157088793',
      title: 'synthetic',
      cover: '',
      description: '',
      episodes: 1,
    );
    await HttpOverrides.runZoned(
      () async {
        final rows = await service.creators(drama);
        expect(rows.map((row) => row.id), [
          '7688558312157088794',
          '7688558312157088795',
        ]);
        expect(rows.map((row) => row.name), ['根用户编号', '基础用户编号']);
      },
      createHttpClient: (_) => _Client((uri, headers) {
        expect(uri.path, '/reading/user/celebrity/list/v1/');
        expect(headers.value('Cookie'), 'sessionid=synthetic-creator-identity');
        return _Reply({
          'code': 0,
          'data': {
            'hot_celebrity_user_list': [
              {
                'user_id': '7688558312157088794',
                'base_info': {
                  'user_id': '7688558312157088796',
                  'biz_user_id': '10001',
                  'user_name': '根用户编号',
                },
              },
              {
                'user_id': 'invalid',
                'base_info': {
                  'user_id': '7688558312157088795',
                  'biz_user_id': '10002',
                  'user_name': '基础用户编号',
                },
              },
              {
                'base_info': {'biz_user_id': '10003', 'user_name': '只有红果号'},
              },
              {
                'user_id': '7688558312157088794',
                'base_info': {'user_name': '重复'},
              },
            ],
          },
        });
      }),
    );
  });
  test('官方分集点赞和作者关注使用独立接口、当前账号并回读确认', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-social');
    final jar = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-social; Path=/; Secure',
      ]);
    await session.accept(jar, {
      'id': '123',
    }, expectedRevision: session.revision);
    final drama = Drama(
      id: 'hongguo:7688558312157088793',
      source: 'hongguo',
      sourceId: '7688558312157088793',
      title: 'synthetic',
      cover: '',
      description: '',
      episodes: 12,
    );
    var liked = false, followed = false, writes = 0, mismatch = false;
    var rejectCreator = false,
        untrustedLogId = false,
        duplicateLogId = false,
        rejectLike = false,
        malformedCreatorCode = false;
    final service = HongguoAccountService(session: session);
    addTearDown(service.dispose);
    await HttpOverrides.runZoned(
      () async {
        final initial = await service.social(drama);
        expect(initial.episode(1)!.liked, false);
        expect(initial.creators.single.id, '7688558312157088794');
        expect(initial.creators.single.relativeType, 3);
        final like = await service.setLiked(drama, initial.episode(1)!, true);
        expect(like.episode(1)!.liked, true);
        expect(like.episode(1)!.count, 11);
        final rows = await service.setCreatorFollowing(
          drama,
          initial.creators.single,
          true,
        );
        expect(rows.single.following, true);
        final removed = await service.setCreatorFollowing(
          drama,
          rows.single,
          false,
        );
        expect(removed.single.following, false);
        await service.setLiked(drama, like.episode(1)!, false);
        expect(writes, 4);
        mismatch = true;
        await expectLater(
          service.setLiked(drama, initial.episode(1)!, true),
          throwsA(
            isA<HongguoAccountFailure>().having(
              (e) => e.code,
              'readback',
              'WRITE_NOT_CONFIRMED',
            ),
          ),
        );
        expect(writes, 5);
        await expectLater(
          service.setCreatorFollowing(
            drama,
            const HongguoCreator(
              '7688558312157088794',
              'unknown',
              2,
              null,
              true,
            ),
            true,
          ),
          throwsA(isA<HongguoAccountFailure>()),
        );
        await expectLater(
          service.setCreatorFollowing(
            drama,
            const HongguoCreator('123', 'self', 2, false, true),
            true,
          ),
          throwsA(isA<HongguoAccountFailure>()),
        );
        expect(writes, 5);
        rejectCreator = true;
        await expectLater(
          service.setCreatorFollowing(drama, initial.creators.single, true),
          throwsA(
            isA<HongguoAccountFailure>()
                .having(
                  (failure) => failure.code,
                  'official rejection',
                  'BUSINESS_103012',
                )
                .having(
                  (failure) => failure.message,
                  'comment API risk classification',
                  contains('安全校验未通过'),
                ),
          ),
        );
        expect(followed, isFalse);
        expect(writes, 6);
        SourceDiagnosticEntry lastResponse() =>
            SourceDiagnostics.shared.entries.lastWhere(
              (entry) => entry.stage == 'creatorFollow' && entry.status == 200,
            );
        final record = lastResponse();
        expect(record.context, '红果作者关注');
        expect(record.businessCode, '103012');
        expect(record.errorCategory, 'upstream_security');
        expect(record.logId, 'ABCDEF0123456789ABCDEF0123456789');
        expect(record.sessionStatus, contains('gatewayLogin=1'));
        expect(record.url, endsWith('/novel/commentapi/comment/do_action/v1/'));
        expect(record.url, isNot(contains('?')));
        for (final sensitive in [
          'synthetic-social',
          'opaque-account-value',
          'private-sdk-details',
          '7688558312157088794',
        ]) {
          expect(record.toReportBlock(), isNot(contains(sensitive)));
        }
        untrustedLogId = true;
        await expectLater(
          service.setCreatorFollowing(drama, initial.creators.single, true),
          throwsA(isA<HongguoAccountFailure>()),
        );
        expect(lastResponse().logId, isEmpty);
        duplicateLogId = true;
        await expectLater(
          service.setCreatorFollowing(drama, initial.creators.single, true),
          throwsA(
            isA<HongguoAccountFailure>().having(
              (failure) => failure.code,
              'diagnostic header error preserves business failure',
              'BUSINESS_103012',
            ),
          ),
        );
        expect(lastResponse().logId, isEmpty);
        rejectLike = true;
        await expectLater(
          service.setLiked(drama, initial.episode(1)!, true),
          throwsA(
            isA<HongguoAccountFailure>().having(
              (failure) => failure.message,
              'scope classification to comment follow API',
              isNot(contains('安全校验未通过')),
            ),
          ),
        );
        expect(session.loggedIn, isTrue);
        expect(session.id, '123');
        malformedCreatorCode = true;
        await expectLater(
          service.setCreatorFollowing(drama, initial.creators.single, true),
          throwsA(isA<HongguoAccountFailure>()),
        );
        expect(lastResponse().businessCode, isEmpty);
        expect(lastResponse().errorCode, 'INVALID_RESPONSE');
        expect(
          lastResponse().toReportBlock(),
          isNot(contains('opaque-account-value')),
        );
      },
      createHttpClient: (_) => _Client((uri, headers) {
        expect(headers.value('Cookie'), 'sessionid=synthetic-social');
        if (uri.path == '/novel/player/video_detail/v1/') {
          final body = jsonDecode(headers.value('synthetic-body')!) as Map;
          expect(body['series_id'], drama.cleanSourceId);
          return _Reply({
            'code': 0,
            'data': {
              'video_data': {
                'series_id_str': drama.cleanSourceId,
                'video_list': [
                  {
                    'vid': '7688558312157088795',
                    'vid_index': 1,
                    'user_digg': mismatch ? false : liked,
                    'digged_count': liked ? 11 : 10,
                  },
                ],
              },
            },
          });
        }
        if (uri.path == '/reading/user/celebrity/list/v1/') {
          expect(uri.queryParameters['list_type'], '3');
          return _Reply({
            'code': 0,
            'data': {
              'main_creator_user_list': [
                {
                  'group_type': 'author',
                  'ugc_user_infos': [
                    {
                      'user_id': '7688558312157088794',
                      'base_info': {'user_name': '合成作者'},
                      'user_tag': {'is_author': true},
                      'user_relation': {
                        'relation_type': followed ? 2 : 1,
                        'can_follow': true,
                      },
                    },
                  ],
                },
              ],
            },
          });
        }
        final body = jsonDecode(headers.value('synthetic-body')!) as Map;
        writes++;
        if (uri.path == '/reading/ugc/action/set/v1/') {
          expect(body['object_id'], '7688558312157088795');
          expect(body['object_type'], 6);
          expect(body['action_category'], 1);
          expect([3, 4], contains(body['action_type']));
          if (rejectLike) return _Reply({'code': 103012});
          liked = body['action_type'] == 3;
        } else {
          expect(uri.path, '/novel/commentapi/comment/do_action/v1/');
          expect(body['object_id'], '7688558312157088794');
          expect(body['object_type'], 1);
          expect(body['aid'], 8662);
          expect(body['business_param'], {'shark_param': <String, dynamic>{}});
          expect(body.containsKey('relative_id'), isFalse);
          expect(body.containsKey('relative_type'), isFalse);
          expect([25, 26], contains(body['action_type']));
          if (rejectCreator) {
            final reply = _Reply({
              'code': malformedCreatorCode ? 'opaque-account-value' : 103012,
              'message': '关注失败，请稍后再试',
              'debug_info': 'private-sdk-details',
            });
            (reply.headers as _Headers).fields.addAll({
              'x-tt-logid': duplicateLogId
                  ? const HttpException('synthetic repeated header')
                  : untrustedLogId
                  ? 'sessionid=opaque-account-value'
                  : 'ABCDEF0123456789ABCDEF0123456789',
              'x-tt-agw-login': '1',
              'x-tt-token': 'opaque-account-value',
            });
            return reply;
          }
          followed = body['action_type'] == 25;
        }
        return _Reply({'code': 0});
      }),
    );
  });

  test('账号列表格式改变和业务拒绝不能变成成功空列表', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-invalid-library');
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-library; Path=/; Secure',
      ]);
    await session.accept(cookies, {
      'id': '123',
    }, expectedRevision: session.revision);
    final service = HongguoAccountService(session: session);
    addTearDown(service.dispose);
    await HttpOverrides.runZoned(
      () async {
        await expectLater(
          service.library(history: false),
          throwsA(isA<HongguoAccountFailure>()),
        );
        await expectLater(
          service.library(history: true),
          throwsA(isA<HongguoAccountFailure>()),
        );
      },
      createHttpClient: (_) => _Client(
        (uri, _) => _Reply(
          uri.path.contains('/bookshelf/')
              ? {'code': 0, 'data': {}}
              : {'code': 15, 'data': {}},
        ),
      ),
    );
  });
  test('单剧进度101112仅使用同一账号历史的匹配进度，缺失或鉴权失败不能伪装成功', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-progress-read');
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-progress; Path=/; Secure',
      ]);
    await session.accept(cookies, {
      'id': '123',
    }, expectedRevision: session.revision);
    final drama = Drama(
      id: 'hongguo:7688558312157088793',
      source: 'hongguo',
      sourceId: '7688558312157088793',
      title: 'synthetic',
      cover: '',
      description: '',
      episodes: 60,
    );
    for (final scenario in [0, 1, 2]) {
      final paths = <String>[];
      final service = HongguoAccountService(session: session);
      addTearDown(service.dispose);
      await HttpOverrides.runZoned(
        () async {
          if (scenario == 0) {
            final progress = await service.progress(drama);
            expect(progress!.episode, 2);
            expect(progress.position, 12);
          } else {
            await expectLater(
              service.progress(drama),
              throwsA(
                isA<HongguoAccountFailure>().having(
                  (e) => e.code,
                  'original rejection',
                  scenario == 1 ? 'BUSINESS_101112' : 'BUSINESS_15',
                ),
              ),
            );
          }
        },
        createHttpClient: (_) => _Client((uri, headers) {
          expect(headers.value('Cookie'), 'sessionid=synthetic-progress');
          paths.add(uri.path);
          if (uri.path.endsWith('/get/v1/')) {
            return _Reply({'code': scenario == 2 ? 15 : 101112});
          }
          expect(uri.path, '/reading/bookapi/read_progress/list/v1/');
          return _Reply({
            'code': 0,
            'video_data': scenario == 0
                ? [
                    {
                      'series_id': drama.cleanSourceId,
                      'vid': '7688558312157088794',
                      'vid_index': 2,
                      'current_play_time': 12000,
                      'current_total_time': 90000,
                      'last_watch_time': 1700000000,
                    },
                  ]
                : [],
          });
        }),
      );
      expect(paths.length, scenario == 2 ? 1 : 2);
    }
  });
  test('切换账号期间已打开但未发送的请求不能附加新账号Cookie', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-library-race');
    HongguoAccountCookies cookies(String token) => HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=$token; Path=/; Secure',
      ]);
    await session.accept(cookies('synthetic-a'), {
      'id': '123',
    }, expectedRevision: session.revision);
    var sent = 0;
    final client = _DeferredClient((_, _) {
      sent++;
      return _Reply({
        'code': 0,
        'data': {'video_shelf_info': []},
      });
    });
    await HttpOverrides.runZoned(() async {
      final service = HongguoAccountService(session: session);
      addTearDown(service.dispose);
      final result = expectLater(
        service.library(history: false),
        throwsA(
          isA<HongguoAccountFailure>().having(
            (e) => e.code,
            'code',
            'CANCELLED',
          ),
        ),
      );
      await client.opened.future;
      await session.logout();
      await session.accept(cookies('synthetic-b'), {
        'id': '456',
      }, expectedRevision: session.revision);
      client.release.complete();
      await result;
      expect(sent, 0);
      expect(client.pending.headers.value('Cookie'), isNull);
      expect(client.pending.aborted, true);
    }, createHttpClient: (_) => client);
  });
  String mix(String value) =>
      utf8.encode(value).map((v) => (v ^ 5).toRadixString(16)).join();
  test('验证码使用官方POST协议和两种CSRF Cookie，不自动注册；取得会话后才确认App账号', () async {
    for (final csrfName in [
      'passport_csrf_token',
      'passport_csrf_token_default',
    ]) {
      final session = HongguoAccountSession();
      await session.bindProfile('phone-$csrfName');
      final paths = <String>[];
      await HttpOverrides.runZoned(
        () async {
          final service = HongguoAccountService(session: session);
          addTearDown(service.dispose);
          final phone = service.phone('86', '13800138000');
          {
            expect(await service.sendPhoneCode(phone), 60);
            expect(session.loggedIn, false);
            await expectLater(
              service.sendPhoneCode(phone),
              throwsA(isA<HongguoAccountFailure>()),
            );
          }
          await service.loginPhone(phone, code: '654321');
          expect(session.loggedIn, true);
          expect(session.id, '1234567890123456789');
          expect(session.verified, true);
          expect(paths.where((p) => p.contains('mobile/register')), isEmpty);
        },
        createHttpClient: (_) => _Client((uri, headers) {
          paths.add(uri.path);
          if (uri.path.endsWith('/get_qrcode/')) {
            return _Reply(
              {
                'message': 'success',
                'data': {
                  'token': 'synthetic-token',
                  'qrcode_index_url':
                      'https://reading.snssdk.com/reading_offline/novelread/page/scan-code.html?token=synthetic-token',
                  'expire_time': 60,
                },
              },
              ['$csrfName=synthetic-csrf; Path=/; Secure'],
            );
          }
          if (uri.path.contains('/passport/web/')) {
            expect(headers.value('x-tt-passport-csrf-token'), 'synthetic-csrf');
            final form = Uri.splitQueryString(headers.value('synthetic-body')!);
            expect(form['mix_mode'], '1');
            expect(form['fixed_mix_mode'], '1');
            if (uri.path.endsWith('/send_code/')) {
              expect(form['mobile'], mix('+86 13800138000'));
              expect(form['type'], mix('24'));
              return _Reply({
                'message': 'success',
                'data': {'retry_time': 60},
              });
            }
            expect(uri.path, '/passport/web/sms_login_only/');
            expect(form['mobile'], mix('+86 13800138000'));
            expect(form['code'], mix('654321'));
            expect(form.containsKey('password'), false);
            return _Reply(
              {'message': 'success', 'data': {}},
              ['sessionid=synthetic-phone-session; Path=/; Secure'],
            );
          }
          if (uri.path == '/passport/account/info/v2/') {
            return _Reply({'message': 'success', 'data': {}});
          }
          expect(headers.value('Cookie'), 'sessionid=synthetic-phone-session');
          return _Reply({
            'code': 0,
            'data': {
              'biz_user_id': '1234567890123456789',
              'user_name': 'synthetic',
            },
          });
        }),
      );
    }
  });
  test('安全验证拒绝不自动重发短信，也不会把发送成功当作登录成功', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('phone-challenge');
    var sent = 0;
    await HttpOverrides.runZoned(
      () async {
        final service = HongguoAccountService(session: session);
        addTearDown(service.dispose);
        await expectLater(
          service.sendPhoneCode(service.phone('86', '13800138000')),
          throwsA(
            isA<HongguoAccountFailure>().having(
              (v) => v.code,
              'code',
              'CHALLENGE_REQUIRED',
            ),
          ),
        );
        expect(sent, 1);
        expect(session.loggedIn, false);
      },
      createHttpClient: (_) => _Client((uri, _) {
        if (uri.path.endsWith('/get_qrcode/')) {
          return _Reply(
            {
              'message': 'success',
              'data': {
                'token': 'synthetic-token',
                'qrcode_index_url':
                    'https://reading.snssdk.com/reading_offline/novelread/page/scan-code.html?token=synthetic-token',
                'expire_time': 60,
              },
            },
            ['passport_csrf_token=synthetic-csrf; Path=/; Secure'],
          );
        }
        sent++;
        return _Reply({
          'message': 'error',
          'data': {
            'error_code': 1102,
            'verify_center_decision_conf': {
              'code': 10000,
              'detail': 'synthetic',
            },
          },
        });
      }),
    );
  });
  _Reply bootstrap() => _Reply(
    {
      'message': 'success',
      'data': {
        'token': 'synthetic-token',
        'qrcode_index_url':
            'https://reading.snssdk.com/reading_offline/novelread/page/scan-code.html?token=synthetic-token',
        'expire_time': 60,
      },
    },
    ['passport_csrf_token_default=synthetic-csrf; Path=/; Secure'],
  );
  _Reply challenge() => _Reply({
    'message': 'error',
    'data': {
      'error_code': 1105,
      'verify_center_decision_conf': {
        'code': 10000,
        'detail': 'synthetic-private-challenge',
      },
    },
  });
  for (final scenario in ['success', 'cancel', 'repeated', 'stale']) {
    test('人工安全验证 $scenario：受用户回调和账号版本约束，最多续发一次', () async {
      final session = HongguoAccountSession();
      await session.bindProfile('verify-$scenario');
      var sent = 0, resolved = 0;
      const fp = 'verify_synthetic_1234567890';
      await HttpOverrides.runZoned(
        () async {
          final service = HongguoAccountService(session: session);
          addTearDown(service.dispose);
          final attempt = service.phone('86', '13800138000');
          final operation = service.sendPhoneCode(
            attempt,
            verify: (value) async {
              resolved++;
              expect(sent, 1);
              expect(session.loggedIn, false);
              expect(value.businessCode, '1105');
              expect(
                value.toString(),
                isNot(contains('synthetic-private-challenge')),
              );
              expect(value.cookies, everyElement(isNot(contains('sessionid'))));
              if (scenario == 'stale') await session.logout();
              return scenario == 'cancel' ? null : fp;
            },
          );
          if (scenario == 'success') {
            expect(await operation, 60);
            expect(attempt.sent, true);
          } else {
            await expectLater(
              operation,
              throwsA(
                isA<HongguoAccountFailure>().having(
                  (v) => v.code,
                  'code',
                  scenario == 'repeated'
                      ? 'VERIFICATION_NOT_ACCEPTED'
                      : 'CANCELLED',
                ),
              ),
            );
            expect(attempt.sent, false);
          }
          expect(resolved, 1);
          expect(sent, ['success', 'repeated'].contains(scenario) ? 2 : 1);
          expect(session.loggedIn, false);
          final logs = SourceDiagnostics.shared.entries
              .map((v) => v.toReportBlock())
              .join();
          expect(logs, isNot(contains('13800138000')));
          expect(logs, isNot(contains('synthetic-csrf')));
          expect(logs, isNot(contains('synthetic-private-challenge')));
          expect(logs, isNot(contains(fp)));
        },
        createHttpClient: (_) => _Client((uri, headers) {
          if (uri.path.endsWith('/get_qrcode/')) return bootstrap();
          expect(uri.path, '/passport/web/send_code/');
          sent++;
          if (sent == 1) {
            expect(uri.queryParameters.containsKey('fp'), false);
            return challenge();
          }
          expect(uri.queryParameters['fp'], fp);
          expect(uri.queryParameters['verifyFp'], fp);
          expect(headers.value('Cookie'), contains('s_v_web_id=$fp'));
          expect(headers.value('x-tt-passport-csrf-token'), 'synthetic-csrf');
          return scenario == 'repeated'
              ? challenge()
              : _Reply({
                  'message': 'success',
                  'data': {'retry_time': 60},
                });
        }),
      );
    });
  }
  for (final code in [403, 429]) {
    test('短信HTTP $code记录诊断且不包含手机号和响应正文', () async {
      final session = HongguoAccountSession();
      await session.bindProfile('http-$code');
      await HttpOverrides.runZoned(
        () async {
          final service = HongguoAccountService(session: session);
          addTearDown(service.dispose);
          await expectLater(
            service.sendPhoneCode(service.phone('86', '13800138000')),
            throwsA(
              isA<HongguoAccountFailure>().having(
                (v) => v.code,
                'code',
                'HTTP_$code',
              ),
            ),
          );
          final entry = SourceDiagnostics.shared.entries.last;
          expect(entry.stage, 'phoneCode');
          expect(entry.errorCode, 'HTTP_$code');
          expect(
            entry.toReportBlock(),
            isNot(contains('synthetic-private-body')),
          );
          expect(entry.toReportBlock(), isNot(contains('13800138000')));
        },
        createHttpClient: (_) => _Client(
          (uri, _) => uri.path.endsWith('/get_qrcode/')
              ? bootstrap()
              : _Reply('synthetic-private-body', [], code),
        ),
      );
    });
  }
  for (final failure in [
    (TimeoutException('synthetic-private-network'), 'TIMEOUT'),
    (const HandshakeException('synthetic-private-network'), 'TLS_ERROR'),
    (const SocketException('synthetic-private-network'), 'NETWORK_ERROR'),
  ]) {
    test('短信传输失败 ${failure.$2} 保留安全诊断', () async {
      final session = HongguoAccountSession();
      await session.bindProfile('network-${failure.$2}');
      await HttpOverrides.runZoned(
        () async {
          final service = HongguoAccountService(session: session);
          addTearDown(service.dispose);
          await expectLater(
            service.sendPhoneCode(service.phone('86', '13800138000')),
            throwsA(
              isA<HongguoAccountFailure>().having(
                (v) => v.code,
                'code',
                failure.$2,
              ),
            ),
          );
          final entry = SourceDiagnostics.shared.entries.last;
          expect(entry.stage, 'phoneCode');
          expect(entry.errorCode, failure.$2);
          expect(
            entry.toReportBlock(),
            isNot(contains('synthetic-private-network')),
          );
        },
        createHttpClient: (_) => _Client((uri, _) {
          if (uri.path.endsWith('/get_qrcode/')) return bootstrap();
          throw failure.$1;
        }),
      );
    });
  }
  test('二维码到期后的最终确认可接收已授权会话，最多查询一次', () async {
    for (final confirmed in [false, true]) {
      final session = HongguoAccountSession();
      await session.bindProfile('late-$confirmed');
      var polls = 0;
      await HttpOverrides.runZoned(
        () async {
          final service = HongguoAccountService(session: session);
          addTearDown(service.dispose);
          final login = HongguoQrLogin(
            'synthetic',
            DateTime.now().subtract(const Duration(seconds: 1)),
            'synthetic-token',
            HongguoAccountCookies(),
            session.revision,
          );
          expect(await service.poll(login, finalCheck: true), confirmed);
          if (!confirmed) {
            await expectLater(
              service.poll(login, finalCheck: true),
              throwsA(
                isA<HongguoAccountFailure>().having(
                  (v) => v.code,
                  'code',
                  'QR_EXPIRED',
                ),
              ),
            );
          }
          expect(polls, 1);
          expect(session.loggedIn, confirmed);
        },
        createHttpClient: (_) => _Client((uri, _) {
          if (uri.path.endsWith('/check_qrconnect/')) {
            polls++;
            return _Reply({
              'message': 'success',
              'data': {
                'status': confirmed ? 'confirmed' : 'new',
                'redirect_url': '',
              },
            }, confirmed ? ['sessionid=synthetic-late; Path=/; Secure'] : []);
          }
          if (uri.path == '/passport/account/info/v2/') {
            return _Reply({'message': 'success', 'data': {}});
          }
          return _Reply({
            'code': 0,
            'data': {
              'biz_user_id': '1234567890123456789',
              'user_name': 'synthetic',
            },
          });
        }),
      );
    }
  });
}
