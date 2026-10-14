import 'package:THLRedLook/core_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/local_profiles.dart';
import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';

/// 站源密码锁测试夹具：为非管理员会话预先写入可解锁的密码锁配置。
const gateSalt = '0123456789abcdef0123456789abcdef';
const gatePin = '666666';

/// 测试用 pin 哈希：与 [hashProfilePin] 同格式（64 位十六进制），但不用 isolate。
/// flutter test 的 fake async 环境下 [Isolate.run] 永不完成，会让用例挂到超时。
Future<String> testPinHasher(String pin, String salt) async {
  var hash = 0;
  for (final unit in '$salt|$pin'.codeUnits) {
    hash = (hash * 31 + unit) & 0xffffffff;
  }
  return List.filled(8, hash.toRadixString(16).padLeft(8, '0')).join();
}

/// 构造注入测试哈希的 [LocalStore]。
LocalStore testStore(SharedPreferences preferences) =>
    LocalStore(preferences, pinHasher: testPinHasher);

Future<Map<String, Object>> gatePreferences() async => {
  'sourceGateEnabled': true,
  'sourceGateSalt': gateSalt,
  'sourceGateHash': await testPinHasher(gatePin, gateSalt),
};

/// 解锁默认隐藏的站源，供需要访问全部站源的用例复用。
Future<void> unlockGate(LocalStore store) => store.unlockSources(gatePin);

class FixtureRepository extends AppRepository {
  int detailCalls = 0;
  bool fail = false;
  final requests = <String>[];
  final pages = <int>[];
  final forced = <bool>[];
  final cachedPages = <String, CatalogPage>{};
  final catalogPages = <String, CatalogPage>{};
  static const free = Drama(
    id: 'hongguo:100',
    source: 'hongguo',
    title: '测试短剧',
    episodes: 2,
    category: '合成数据',
  );
  static const vip = Drama(
    id: 'huangdou:200',
    source: 'huangdou',
    title: '会员测试剧',
    episodes: 4,
    vip: true,
  );
  @override
  Future<void> initialize() async {}
  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      cachedPages[source] ?? CatalogPage([]);
  @override
  Future<String> cover(Drama drama, {bool force = false}) async =>
      throw AppFailure('合成剧集没有远程海报');
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    requests.add(source);
    pages.add(page);
    forced.add(force);
    if (fail) {
      throw AppFailure('合成网络错误');
    }
    if (catalogPages.containsKey(source)) {
      return catalogPages[source]!;
    }
    return CatalogPage(
      [
        free,
        vip,
        Drama(
          id: '$source:auto-$page',
          source: source,
          title: '第$page页短剧',
          episodes: 1,
          category: '合成数据',
        ),
      ],
      page: page,
      hasMore: page < 5,
    );
  }

  @override
  Future<DramaDetail> detail(Drama drama) async {
    detailCalls++;
    return DramaDetail(drama, [
      Episode({'id': '1', 'title': '第1集', 'currentEpisode': 1}, 1),
      Episode({'id': '2', 'title': '第2集', 'currentEpisode': 2}, 2),
    ]);
  }

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async => const PlaybackPlan(url: 'https://example.test/synthetic.mp4');
  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) async =>
      throw AppFailure('没有备用线路');
  @override
  Future<void> cancelPlayback() async {}
  @override
  Future<void> release(String session) async {}
}
