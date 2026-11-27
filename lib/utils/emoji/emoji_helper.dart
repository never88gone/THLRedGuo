import 'package:flutter/material.dart';
import 'package:flutter_emoji/flutter_emoji.dart';

class EmojiHelper {
  EmojiHelper._();

  static final EmojiParser _parser = EmojiParser();

  static const List<String> emojiFontFallback = [
    'Apple Color Emoji',
    'Noto Color Emoji',
    'Segoe UI Emoji',
    'Android Emoji',
    'EmojiSymbols',
  ];

  static const Map<String, String> _customEmojiMap = {
    '[微笑]': '😊',
    '[大笑]': '😆',
    '[偷笑]': '🤭',
    '[呲牙]': '😁',
    '[调皮]': '😜',
    '[捂脸]': '🤦',
    '[机智]': '🤓',
    '[思考]': '🤔',
    '[流泪]': '😭',
    '[哭]': '😭',
    '[发怒]': '😡',
    '[生气]': '😡',
    '[可爱]': '🥰',
    '[害羞]': '😳',
    '[白眼]': '🙄',
    '[委屈]': '🥺',
    '[酷]': '😎',
    '[困]': '🥱',
    '[给力]': '💪',
    '[加油]': '💪',
    '[666]': '🤙',
    '[点赞]': '👍',
    '[赞]': '👍',
    '[强]': '👍',
    '[爱心]': '❤️',
    '[心]': '❤️',
    '[比心]': '🫰',
    '[鼓掌]': '👏',
    '[抱拳]': '🙏',
    '[握手]': '🤝',
    '[胜利]': '✌️',
    '[耶]': '✌️',
    '[庆祝]': '🎉',
    '[火]': '🔥',
    '[便便]': '💩',
    '[衰]': '😞',
    '[吐血]': '🤮',
    '[汗]': '😅',
    '[问号]': '❓',
    '[叹号]': '❗️',
    '[100]': '💯',
    '[红包]': '🧧',
    '[玫瑰]': '🌹',
  };

  static final RegExp _tagRegex = RegExp(r'\[[^\]\s]{1,6}\]');

  static String emojify(String input) {
    if (input.isEmpty) return input;
    var result = input;
    if (result.contains('[') && result.contains(']')) {
      result = result.replaceAllMapped(_tagRegex, (match) {
        final key = match.group(0);
        return _customEmojiMap[key] ?? key!;
      });
    }
    if (result.contains(':')) {
      result = _parser.emojify(result);
    }
    return result;
  }

  static TextStyle withEmojiFont(TextStyle? style) {
    final existing = style?.fontFamilyFallback ?? const [];
    final merged = <String>[...existing];
    for (final font in emojiFontFallback) {
      if (!merged.contains(font)) {
        merged.add(font);
      }
    }
    return (style ?? const TextStyle()).copyWith(
      fontFamilyFallback: merged,
    );
  }
}

class EmojiText extends StatelessWidget {
  const EmojiText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.textScaler,
    this.softWrap,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final TextScaler? textScaler;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final converted = EmojiHelper.emojify(text);
    final effectiveStyle = EmojiHelper.withEmojiFont(style);

    return Text(
      converted,
      style: effectiveStyle,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      textScaler: textScaler,
      softWrap: softWrap,
    );
  }
}
