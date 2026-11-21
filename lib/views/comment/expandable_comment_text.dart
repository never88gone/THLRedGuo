import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 支持超过 maxLines（默认 3 行）折叠与展开收起的多行评论文本组件
class ExpandableCommentText extends StatefulWidget {
  const ExpandableCommentText({
    super.key,
    required this.text,
    this.maxLines = 3,
    this.style,
  });

  final String text;
  final int maxLines;
  final TextStyle? style;

  @override
  State<ExpandableCommentText> createState() => _ExpandableCommentTextState();
}

class _ExpandableCommentTextState extends State<ExpandableCommentText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ExpandableCommentText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.style ??
        const TextStyle(
          color: AppColors.white,
          fontSize: 14,
          height: 1.4,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return Text(
            widget.text,
            style: textStyle,
            maxLines: _expanded ? null : widget.maxLines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          );
        }

        final span = TextSpan(text: widget.text, style: textStyle);
        final tp = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxWidth);

        final bool isExceeded = tp.didExceedMaxLines;

        if (!isExceeded) {
          return Text(
            widget.text,
            style: textStyle,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: textStyle,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? '收起' : '展开全文',
                      style: const TextStyle(
                        color: AppColors.hongguoRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: AppColors.hongguoRed,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
