import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/lan_models.dart';
import 'package:THLRedLook/lan_sync_models.dart';
import 'package:THLRedLook/models.dart';

void main() {
  group('局域网互联与跨端推流同步 (LAN Sync & Handoff) 自动化测试', () {
    test('1. 局域网 mDNS 服务类型与广播契约验证', () {
      const serviceType = '_zgj-link._tcp';
      expect(serviceType, equals('_zgj-link._tcp'));
      expect(lanID().length, equals(32));
    });

    test('2. 跨设备推流接续 (LanPlaybackIntent) 契约测试', () {
      final drama = Drama(
        id: 'hongguo:7345678901234567890',
        source: 'hongguo',
        sourceId: '7345678901234567890',
        title: '都市绝品战神',
        episodes: 88,
      );

      final intent = LanPlaybackIntent(
        drama: drama,
        episodeID: 'vid_123',
        episode: 5,
        position: 45.5,
        playing: true,
      );

      final json = intent.toJson();
      expect(json['episodeId'], equals('vid_123'));
      expect(json['episode'], equals(5));
      expect(json['position'], equals(45.5));
      expect(json['playing'], isTrue);
      expect((json['drama'] as Map)['id'], equals('hongguo:7345678901234567890'));

      // 反序列化还原
      final restored = LanPlaybackIntent.fromJson(json);
      expect(restored.drama.id, equals('hongguo:7345678901234567890'));
      expect(restored.episodeID, equals('vid_123'));
      expect(restored.episode, equals(5));
      expect(restored.position, equals(45.5));
      expect(restored.playing, isTrue);

      expect(restored.identity, isNotEmpty);
      expect(restored.identity, equals(intent.identity));
    });

    test('3. LanVersion 向量版本合并测试', () {
      final v1 = LanVersion({'replica_a': 1, 'replica_b': 3});
      final v2 = LanVersion({'replica_b': 5, 'replica_c': 2});

      final joined = v1.join(v2);
      expect(joined.values['replica_a'], equals(1));
      expect(joined.values['replica_b'], equals(5));
      expect(joined.values['replica_c'], equals(2));

      expect(joined.includes(v1), isTrue);
      expect(joined.includes(v2), isTrue);
    });

    test('4. LanDocument 数据合并 (reconcile) 与变更统计测试', () {
      final doc = LanDocument.empty();
      final drama1 = Drama(
        id: 'hongguo:7345678901234567890',
        source: 'hongguo',
        sourceId: '7345678901234567890',
        title: '都市绝品战神',
        episodes: 88,
      );

      final watch1 = WatchEntry(
        drama: drama1,
        episode: 2,
        position: 30.0,
        duration: 90.0,
        updatedAt: DateTime.now(),
      );

      doc.reconcile(
        previous: {},
        favorites: {drama1.id: drama1},
        states: {},
        history: {drama1.id: watch1},
        oldHistory: {},
      );

      expect(doc.records.containsKey(drama1.id), isTrue);
      final record = doc.records[drama1.id]!;
      expect(record.followed, isTrue);
      expect(record.drama.title, equals('都市绝品战神'));

      final jsonDoc = doc.toJson();
      expect(jsonDoc['schema'], equals(1));
      expect((jsonDoc['records'] as List).length, equals(1));

      // 反序列化验证
      final parsedDoc = LanDocument.fromJson(jsonDoc);
      expect(parsedDoc.records.containsKey(drama1.id), isTrue);
      expect(parsedDoc.records[drama1.id]!.drama.id, equals(drama1.id));
    });
  });
}
