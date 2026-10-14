import 'dart:async';
import 'package:THLRedLook/core_bridge.dart';
import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// E2E 测试公共工具与数据夹具
class E2EFixtures {
  static const hongguoDrama1 = Drama(
    id: 'hongguo:700101',
    source: 'hongguo',
    title: '真果之绝世神医',
    episodes: 80,
    category: 'short_play',
    cover: '',
    vip: false,
  );

  static const hongguoDrama2 = Drama(
    id: 'hongguo:700102',
    source: 'hongguo',
    title: '都市之巅峰龙婿',
    episodes: 100,
    category: 'short_play',
    cover: '',
    vip: true,
  );

  static const hongguoComicDrama = Drama(
    id: 'hongguo:700201',
    source: 'hongguo',
    title: '绝品狂仙（漫剧）',
    episodes: 50,
    category: 'comic_series',
    cover: '',
    vip: false,
  );

  static const hongguoAiDrama = Drama(
    id: 'hongguo:700301',
    source: 'hongguo',
    title: '未来觉醒2099（AI剧）',
    episodes: 30,
    category: 'ai_series',
    cover: '',
    vip: false,
  );

  static List<Episode> generateEpisodes(int count, {String dramaId = '700101'}) {
    return List.generate(count, (index) {
      final num = index + 1;
      return Episode({
        'id': '$num',
        'dramaId': dramaId,
        'currentEpisode': num,
        'title': '第$num集',
        'videoUrl': 'https://cenc.hongguo.test/stream/$dramaId/$num/video.mp4',
        'vip': num > 5,
      }, num);
    });
  }

  static Future<LocalStore> createTestStore({
    Map<String, Object> initialValues = const {},
  }) async {
    SharedPreferences.setMockInitialValues(Map.from(initialValues));
    final prefs = await SharedPreferences.getInstance();
    return LocalStore(prefs);
  }
}

/// 红果源站高仿真 E2E 仓库
class E2EHongguoRepository extends AppRepository {
  bool simulateNetworkError = false;
  bool simulateTimeout = false;
  bool simulateEmptyCatalog = false;
  bool simulateCorruptPlan = false;
  bool simulateInvalidDetail = false;

  int detailFetchCount = 0;
  int resolveCount = 0;
  int fallbackCount = 0;

  final List<String> catalogRequests = [];
  final List<String> searchQueries = [];
  final List<int> resolvedEpisodes = [];
  final List<int> resolvedQualities = [];

  final List<Drama> _catalogData = [
    E2EFixtures.hongguoDrama1,
    E2EFixtures.hongguoDrama2,
    E2EFixtures.hongguoComicDrama,
    E2EFixtures.hongguoAiDrama,
  ];

  @override
  Future<void> initialize() async {
    if (simulateNetworkError) {
      throw AppFailure('原生核心初始化网络失败');
    }
  }

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async {
    return CatalogPage([]);
  }

  @override
  Future<String> cover(Drama drama, {bool force = false}) async {
    // 返回空地址，避免触发未捕获异步异常
    return '';
  }

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    catalogRequests.add('$source:$category:$page');
    if (simulateTimeout) {
      throw AppFailure('网络连接超时，请检查网络设置');
    }
    if (simulateNetworkError) {
      throw AppFailure('网络请求失败');
    }
    if (simulateEmptyCatalog) {
      return CatalogPage([], page: page, hasMore: false);
    }

    var list = _catalogData;
    if (category.isNotEmpty && category != 'all') {
      list = list.where((d) => d.category == category).toList();
    }

    // 分页模拟
    final items = [
      ...list,
      Drama(
        id: '$source:page$page-item',
        source: source,
        title: '红果推荐剧集 P$page',
        episodes: 20,
        category: category.isNotEmpty ? category : 'short_play',
      ),
    ];

    return CatalogPage(
      items,
      page: page,
      hasMore: page < 3,
    );
  }

  @override
  Future<List<String>> suggestions(String query) async {
    searchQueries.add(query);
    if (simulateTimeout) {
      throw AppFailure('联想词服务超时');
    }
    if (simulateNetworkError) {
      throw AppFailure('联想词获取失败');
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final suggestions = <String>[];
    if ('绝世神医'.contains(trimmed) || '神医'.contains(trimmed)) {
      suggestions.addAll(['真果之绝世神医', '神医下山', '都市神医狂婿']);
    } else if ('龙婿'.contains(trimmed) || '巅峰'.contains(trimmed)) {
      suggestions.addAll(['都市之巅峰龙婿', '龙婿归来', '绝品龙婿']);
    } else {
      suggestions.addAll(['$trimmed 系列精选', '$trimmed 完结篇', '$trimmed 抢先看']);
    }
    return suggestions;
  }

  @override
  Future<DramaDetail> detail(Drama drama) async {
    detailFetchCount++;
    if (simulateNetworkError) {
      throw AppFailure('获取剧集详情失败');
    }
    if (simulateInvalidDetail) {
      return DramaDetail(drama, []);
    }

    final episodes = E2EFixtures.generateEpisodes(
      drama.episodes > 0 ? drama.episodes : 60,
      dramaId: drama.id,
    );
    return DramaDetail(drama, episodes);
  }

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    resolveCount++;
    resolvedEpisodes.add(episode.number);
    resolvedQualities.add(quality);

    if (simulateNetworkError) {
      throw AppFailure('获取视频播放链接失败');
    }

    if (simulateCorruptPlan) {
      return const PlaybackPlan(
        url: 'https://corrupt.hongguo.test/404.mp4',
        decryptionKey: 'invalid_key',
        session: 'corrupt-session',
      );
    }

    final q = quality > 0 ? quality : 1080;
    return PlaybackPlan(
      url: 'https://cenc.hongguo.test/stream/${drama.id}/${episode.number}_${q}p.mp4',
      decryptionKey: '0123456789abcdef0123456789abcdef',
      session: 'session-${drama.id}-${episode.number}-$q',
      quality: q,
      qualities: const [1080, 720, 480],
      routeIndex: 0,
      routeCount: 2,
      headers: {
        'User-Agent': 'com.dragon.read/7.3.5.32 (Linux; U; Android 14; zh_CN; Redmi K60)',
        'Referer': 'https://api5-normal-sinfonlineb.fqnovel.com',
      },
    );
  }

  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) async {
    fallbackCount++;
    if (simulateNetworkError) {
      throw AppFailure('备用线路不可用');
    }
    return PlaybackPlan(
      url: '${current.url}?route=backup',
      decryptionKey: current.decryptionKey,
      session: '${current.session}-backup',
      quality: current.quality,
      qualities: current.qualities,
      routeIndex: (current.routeIndex + 1) % current.routeCount,
      routeCount: current.routeCount,
    );
  }

  @override
  Future<void> cancelPlayback() async {}

  @override
  Future<void> release(String session) async {}
}

/// 高仿真流媒体播放器，支持精准驱动状态流
class E2EScriptedPlayer extends PlatformPlayer {
  E2EScriptedPlayer() : super(configuration: const PlayerConfiguration());

  final List<Media> openedMedia = [];
  final List<double> rateHistory = [];
  bool isDisposed = false;
  bool shouldFailOnOpen = false;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final media = playable as Media;
    openedMedia.add(media);

    final isBroken = shouldFailOnOpen || media.uri.contains('corrupt') || media.uri.contains('404');
    
    // 模拟起播缓冲 -> 就绪状态转换
    state = state.copyWith(
      buffering: true,
      playing: false,
    );
    bufferingController.add(true);
    playingController.add(false);

    await Future<void>.delayed(const Duration(milliseconds: 10));

    if (isBroken) {
      state = state.copyWith(
        buffering: false,
        playing: false,
        duration: Duration.zero,
        position: Duration.zero,
      );
      bufferingController.add(false);
      errorController.add('MediaKit/MPV: Failed to open media: HTTP 404 Not Found');
      return;
    }

    state = state.copyWith(
      buffering: false,
      playing: play,
      duration: const Duration(minutes: 2, seconds: 15),
      position: media.start ?? const Duration(seconds: 1),
      width: 1080,
      height: 1920,
    );
    bufferingController.add(false);
    durationController.add(state.duration);
    positionController.add(state.position);
    playingController.add(play);
  }

  void progressTime(Duration delta) {
    final newPos = state.position + delta;
    state = state.copyWith(position: newPos);
    positionController.add(newPos);
  }

  void triggerBuffering(bool buffering) {
    state = state.copyWith(buffering: buffering);
    bufferingController.add(buffering);
  }

  void simulateComplete() {
    state = state.copyWith(
      position: state.duration,
      completed: true,
      playing: false,
    );
    positionController.add(state.position);
    completedController.add(true);
    playingController.add(false);
  }

  @override
  Future<void> play() async {
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> playOrPause() async {
    final next = !state.playing;
    state = state.copyWith(playing: next);
    playingController.add(next);
  }

  @override
  Future<void> seek(Duration duration) async {
    state = state.copyWith(position: duration);
    positionController.add(duration);
  }

  @override
  Future<void> setRate(double rate) async {
    rateHistory.add(rate);
    state = state.copyWith(rate: rate);
    rateController.add(rate);
  }

  @override
  Future<void> stop() async {
    state = state.copyWith(
      playing: false,
      position: Duration.zero,
    );
    playingController.add(false);
    positionController.add(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await super.dispose();
  }
}
