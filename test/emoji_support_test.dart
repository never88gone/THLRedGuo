import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:THLRedLook/models/danmaku/danmaku_models.dart';
import 'package:THLRedLook/utils/emoji/emoji_helper.dart';
import 'package:THLRedLook/views/comment/expandable_comment_text.dart';
import 'package:THLRedLook/views/danmaku/danmaku_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Emoji 核心解析与显示库测试', () {
    test('1. 常见 shortcode 自动转换为对应 Unicode Emoji 图标', () {
      final input = '这部剧太精彩了 :fire: :heart: :thumbsup: :joy:';
      final output = EmojiHelper.emojify(input);

      expect(output, contains('🔥'));
      expect(output, contains('❤️'));
      expect(output, contains('👍'));
      expect(output, contains('😂'));
      expect(output, isNot(contains(':fire:')));
      expect(output, isNot(contains(':heart:')));
    });

    test('2. 常见中文表情标签映射转换为对应 Emoji 图标', () {
      final input = '男女主太甜了[偷笑][心]，结局看哭了[流泪]，演技直接[点赞][666]！';
      final output = EmojiHelper.emojify(input);

      expect(output, contains('🤭'));
      expect(output, contains('❤️'));
      expect(output, contains('😭'));
      expect(output, contains('👍'));
      expect(output, contains('🤙'));
      expect(output, isNot(contains('[偷笑]')));
      expect(output, isNot(contains('[心]')));
      expect(output, isNot(contains('[流泪]')));
      expect(output, isNot(contains('[点赞]')));
      expect(output, isNot(contains('[666]')));
    });

    test('3. 混合文本与已有原生 Emoji 保持完整无损', () {
      final input = '原汁原味 😊 [微笑] :smile: 混合测试 123 !?';
      final output = EmojiHelper.emojify(input);

      expect(output, contains('😊'));
      expect(output, contains('😄'));
      expect(output, contains('混合测试 123 !?'));
      expect(output, isNot(contains('[微笑]')));
      expect(output, isNot(contains(':smile:')));
    });

    test('4. TextStyle 注入多端系统彩色 Emoji 字体族 fallback', () {
      const baseStyle = TextStyle(fontSize: 16, color: Colors.white, fontFamily: 'PingFang SC');
      final emojiStyle = EmojiHelper.withEmojiFont(baseStyle);

      expect(emojiStyle.fontSize, 16);
      expect(emojiStyle.color, Colors.white);
      expect(emojiStyle.fontFamily, 'PingFang SC');
      expect(emojiStyle.fontFamilyFallback, contains('Apple Color Emoji'));
      expect(emojiStyle.fontFamilyFallback, contains('Noto Color Emoji'));
      expect(emojiStyle.fontFamilyFallback, contains('Segoe UI Emoji'));
    });
  });

  group('Emoji 组件呈现与业务联动测试', () {
    testWidgets('5. EmojiText 控件正常渲染转化后的 Emoji', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmojiText('短剧大好评 :heart: [点赞]'),
          ),
        ),
      );

      expect(find.text('短剧大好评 ❤️ 👍'), findsOneWidget);
    });

    testWidgets('6. 评论多行折叠组件 ExpandableCommentText 渲染表情图标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExpandableCommentText(
              text: '这反转绝了 [捂脸] :clap: 期待第二季 [给力]',
            ),
          ),
        ),
      );

      expect(find.text('这反转绝了 🤦 👏 期待第二季 💪'), findsOneWidget);
    });

    testWidgets('7. 弹幕规划器 planDanmaku 包含表情符号时正常度量排版', (tester) async {
      final items = [
        const DanmakuItem(id: 'd1', text: '前排围观 :fire: [666]', timeMs: 1000),
        const DanmakuItem(id: 'd2', text: '女主太飒了 [点赞]', timeMs: 1500),
      ];

      final flights = planDanmaku(
        items,
        width: 1920,
        rows: 4,
        measure: (text) => text.length * 16.0,
      );

      expect(flights.length, 2);
      expect(flights[0].text, contains('🔥'));
      expect(flights[0].text, contains('🤙'));
      expect(flights[0].text, isNot(contains(':fire:')));
      expect(flights[1].text, contains('👍'));
      expect(flights[1].text, isNot(contains('[点赞]')));
    });
  });
}
