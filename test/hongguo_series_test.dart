import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/hongguo_series.dart';
import 'package:THLRedLook/models.dart';

void main() {
  group('红果多季剧集识别与聚合引擎 (Hongguo Multi-Season Engine) 测试', () {
    test('1. 基础标题清洗 (去除画质与状态杂质)', () {
      expect(cleanSeriesBaseTitle('盖世龙王 (4K高清全集)'), equals('盖世龙王'));
      expect(cleanSeriesBaseTitle('赘婿当道 [1080P完结]'), equals('赘婿当道'));
      expect(cleanSeriesBaseTitle('九天仙尊【精修版】'), equals('九天仙尊'));
      expect(cleanSeriesBaseTitle('至尊神相（热播已完结）'), equals('至尊神相'));
    });

    test('2. 中文数字与常规季数识别 (第X季/部/篇)', () {
      final drama1 = Drama(
        id: 'hongguo:101',
        source: 'hongguo',
        sourceId: '101',
        title: '都市绝品仙医 第一季',
      );
      final info1 = hongguoSeriesInfo(drama1);
      expect(info1, isNotNull);
      expect(info1!.baseTitle, equals('都市绝品仙医'));
      expect(info1.season, equals(1));
      expect(info1.unit, equals('季'));

      final drama2 = Drama(
        id: 'hongguo:102',
        source: 'hongguo',
        sourceId: '102',
        title: '都市绝品仙医 第二季',
      );
      final info2 = hongguoSeriesInfo(drama2);
      expect(info2, isNotNull);
      expect(info2!.season, equals(2));

      final drama3 = Drama(
        id: 'hongguo:103',
        source: 'hongguo',
        sourceId: '103',
        title: '都市绝品仙医 第十二季',
      );
      final info3 = hongguoSeriesInfo(drama3);
      expect(info3, isNotNull);
      expect(info3!.season, equals(12));
    });

    test('3. 英文 Season / S 标识与罗马数字季数识别', () {
      final dramaS2 = Drama(
        id: 'hongguo:201',
        source: 'hongguo',
        sourceId: '201',
        title: '狂飙之风云际会 S2',
      );
      final infoS2 = hongguoSeriesInfo(dramaS2);
      expect(infoS2, isNotNull);
      expect(infoS2!.season, equals(2));

      final dramaSeason3 = Drama(
        id: 'hongguo:202',
        source: 'hongguo',
        sourceId: '202',
        title: '狂飙之风云际会 Season 3',
      );
      final infoSeason3 = hongguoSeriesInfo(dramaSeason3);
      expect(infoSeason3, isNotNull);
      expect(infoSeason3!.season, equals(3));

      final dramaRoman = Drama(
        id: 'hongguo:203',
        source: 'hongguo',
        sourceId: '203',
        title: '狂飙之风云际会 II',
      );
      final infoRoman = hongguoSeriesInfo(dramaRoman);
      expect(infoRoman, isNotNull);
      expect(infoRoman!.season, equals(2));
    });

    test('4. 续集/大结局词缀识别', () {
      final dramaSequel = Drama(
        id: 'hongguo:301',
        source: 'hongguo',
        sourceId: '301',
        title: '霸道总裁的小娇妻 续集',
      );
      final infoSequel = hongguoSeriesInfo(dramaSequel);
      expect(infoSequel, isNotNull);
      expect(infoSequel!.season, equals(2));

      final dramaFinal = Drama(
        id: 'hongguo:302',
        source: 'hongguo',
        sourceId: '302',
        title: '霸道总裁的小娇妻 大结局',
      );
      final infoFinal = hongguoSeriesInfo(dramaFinal);
      expect(infoFinal, isNotNull);
      expect(infoFinal!.season, equals(99));
    });

    test('5. 多季聚拢 (hongguoSeriesEntries) 排序与展示测试', () {
      final anchor = Drama(
        id: 'hongguo:1001',
        source: 'hongguo',
        sourceId: '1001',
        title: '天命大反派',
      );

      final s1 = Drama(
        id: 'hongguo:1001',
        source: 'hongguo',
        sourceId: '1001',
        title: '天命大反派 第一季',
      );
      final s2 = Drama(
        id: 'hongguo:1002',
        source: 'hongguo',
        sourceId: '1002',
        title: '天命大反派 第二季',
      );
      final s3 = Drama(
        id: 'hongguo:1003',
        source: 'hongguo',
        sourceId: '1003',
        title: '天命大反派 第三季',
      );

      final entries = hongguoSeriesEntries(anchor, [s1, s2, s3]);
      expect(entries.length, equals(3));
      expect(entries[0].season, equals(1));
      expect(entries[0].label, equals('第 1 季'));
      expect(entries[1].season, equals(2));
      expect(entries[1].label, equals('第 2 季'));
      expect(entries[2].season, equals(3));
      expect(entries[2].label, equals('第 3 季'));
    });
  });
}
