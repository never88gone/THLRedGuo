import 'package:flutter/material.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 极简单行紧凑渠道卡片（邮箱 / GitHub）
class ContactChannelTile extends StatelessWidget {
  const ContactChannelTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
    required this.primaryBtnKey,
    required this.primaryBtnText,
    required this.primaryBtnIcon,
    required this.onPrimary,
    required this.copyBtnKey,
    required this.onCopy,
  });

  final IconData icon;
  final String title;
  final String value;
  final String hint;
  final String primaryBtnKey;
  final String primaryBtnText;
  final IconData primaryBtnIcon;
  final VoidCallback onPrimary;
  final String copyBtnKey;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: isDark ? AppColors.darkCard : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : theme.colorScheme.outlineVariant,
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    value,
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  key: ValueKey(copyBtnKey),
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 13),
                  label: const Text('复制', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: const Size(0, 32),
                    side: BorderSide(
                      color: isDark ? AppColors.white15 : theme.colorScheme.outlineVariant,
                      width: 0.8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  key: ValueKey(primaryBtnKey),
                  onPressed: onPrimary,
                  icon: Icon(primaryBtnIcon, size: 13),
                  label: Text(primaryBtnText, style: const TextStyle(fontSize: 11)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
