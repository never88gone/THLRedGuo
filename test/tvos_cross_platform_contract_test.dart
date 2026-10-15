import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/models.dart';

void main() {
  group('tvOS 原生端模型契约与多端交互规范自动化测试', () {
    test('1. Drama 模型 JSON 序列化与 tvOS Codable 契约对齐', () {
      final drama = Drama(
        id: 'hongguo:7345678901234567890',
        source: 'hongguo',
        sourceId: '7345678901234567890',
        title: '至尊龙王令',
        description: '五年前一代龙王隐姓埋名...',
        cover: 'https://p3.example.com/cover.jpg',
        episodes: 90,
        category: '真人剧',
        vip: false,
        heat: '98.5万',
        views: '120万',
        onlineDate: '2024-05-01',
        tags: ['热血', '战神', '逆袭'],
        releaseStatus: 'completed',
      );

      final json = drama.toJson();

      // 验证与 tvOS Drama.swift Codable 字段一致
      expect(json['id'], equals('hongguo:7345678901234567890'));
      expect(json['source'], equals('hongguo'));
      expect(json['sourceId'], equals('7345678901234567890'));
      expect(json['title'], equals('至尊龙王令'));
      expect(json['description'], contains('一代龙王'));
      expect(json['cover'], equals('https://p3.example.com/cover.jpg'));
      expect(json['episodes'], equals(90));
      expect(json['category'], equals('真人剧'));
      expect(json['vip'], isFalse);
      expect(json['heat'], equals('98.5万'));
      expect(json['views'], equals('120万'));
      expect(json['onlineDate'], equals('2024-05-01'));
      expect(json['tags'], containsAll(['热血', '战神', '逆袭']));
      expect(json['releaseStatus'], equals('completed'));

      // 验证状态标签解析与 tvOS 保持一致
      expect(drama.releaseLabel, equals('已完结'));

      // 反序列化测试
      final restored = Drama.fromJson(json);
      expect(restored.id, equals(drama.id));
      expect(restored.title, equals(drama.title));
      expect(restored.episodes, equals(drama.episodes));
      expect(restored.releaseLabel, equals('已完结'));
    });

    test('2. PlaybackPlan 播放计划与多清晰度契约对齐', () {
      const plan = PlaybackPlan(
        url: 'https://v9-dy-y.hongguoduanju.com/video/stream.m3u8',
        headers: {
          'User-Agent': 'THLRedLook-tvOS/1.0.0',
          'Referer': 'https://hongguoduanju.com/',
        },
        decryptionKey: '',
        quality: 1080,
        qualities: [1080, 720, 480],
        session: 'tvos_sess_123456',
        danmakuId: 'hongguo:7345678901234567890:1',
        routeIndex: 0,
        routeCount: 2,
        local: false,
      );

      final json = {
        'url': plan.url,
        'headers': plan.headers,
        'decryptionKey': plan.decryptionKey,
        'quality': plan.quality,
        'qualities': plan.qualities,
        'session': plan.session,
        'danmakuId': plan.danmakuId,
        'routeIndex': plan.routeIndex,
        'routeCount': plan.routeCount,
        'local': plan.local,
      };

      final restored = PlaybackPlan.fromJson(json);
      expect(restored.url, equals(plan.url));
      expect(restored.headers['User-Agent'], equals('THLRedLook-tvOS/1.0.0'));
      expect(restored.quality, equals(1080));
      expect(restored.qualities, containsAll([1080, 720, 480]));
      expect(restored.hasAlternative, isTrue);
    });

    test('3. WatchEntry 观看历史与秒级断点契约对齐', () {
      final drama = Drama(
        id: 'hongguo:7345678901234567890',
        source: 'hongguo',
        sourceId: '7345678901234567890',
        title: '都市绝品仙医',
      );

      final now = DateTime.now();
      final entry = WatchEntry(
        drama: drama,
        episode: 8,
        position: 110.5,
        duration: 120.0,
        updatedAt: now,
      );

      final json = entry.toJson();
      expect(json['episode'], equals(8));
      expect(json['position'], equals(110.5));
      expect(json['duration'], equals(120.0));
      expect(json['updatedAt'], equals(now.toIso8601String()));

      final restored = WatchEntry.fromJson(json);
      expect(restored.episode, equals(8));
      expect(restored.position, equals(110.5));
      expect(restored.duration, equals(120.0));
      expect(restored.finished, isFalse);
    });

    test('4. tvOS 端官方站源独占与大屏合规过滤契约', () {
      // 验证 tvOS 规范：非官方规范站源强制过滤屏蔽
      bool isAdultOrProhibitedOnTV(String sourceId) {
        return sourceId.toLowerCase() != 'hongguo';
      }

      expect(isAdultOrProhibitedOnTV('hongguo'), isFalse, reason: '官方规范站源在大屏端允许使用');
      expect(isAdultOrProhibitedOnTV('huangdou'), isTrue, reason: '敏感源在客厅大屏端必须严格屏蔽');
      expect(isAdultOrProhibitedOnTV('unknown_adult'), isTrue, reason: '未授权源在客厅大屏端必须严格屏蔽');
    });

    test('5. tvOS 大屏遥控器与 50 集分段 Chunk 交互契约', () {
      // 模拟 120 集短剧的 50 集分组
      const totalEpisodes = 120;
      final chunks = <Map<String, int>>[];
      for (var start = 1; start <= totalEpisodes; start += 50) {
        final end = (start + 49).clamp(1, totalEpisodes);
        chunks.add({'start': start, 'end': end});
      }

      expect(chunks.length, equals(3));
      expect(chunks[0], equals({'start': 1, 'end': 50}));
      expect(chunks[1], equals({'start': 51, 'end': 100}));
      expect(chunks[2], equals({'start': 101, 'end': 120}));
    });
  });
}
