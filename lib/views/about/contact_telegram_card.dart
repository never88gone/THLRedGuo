import 'package:flutter/material.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// Telegram 官方交流与反馈卡片
class ContactTelegramCard extends StatelessWidget {
  const ContactTelegramCard({
    super.key,
    required this.telegramChannel,
    required this.onOpenTelegram,
    required this.onCopyTelegram,
    required this.onShowQrDialog,
  });

  final String telegramChannel;
  final VoidCallback onOpenTelegram;
  final VoidCallback onCopyTelegram;
  final VoidCallback onShowQrDialog;

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
          color: primaryColor.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.send_rounded, size: 18, color: primaryColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Telegram 官方交流与反馈',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              telegramChannel,
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '扫码右侧二维码，或轻触下方按钮直接跳转交流群',
                    style: TextStyle(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('btn-open-telegram'),
                        icon: const Icon(Icons.open_in_new_rounded, size: 14),
                        label: const Text('直接打开', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: const Size(60, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: onOpenTelegram,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const ValueKey('btn-copy-telegram'),
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('复制链接', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          minimumSize: const Size(60, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: onCopyTelegram,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: onShowQrDialog,
              borderRadius: BorderRadius.circular(10),
              child: Tooltip(
                message: '轻触放大二维码',
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.blackSubtle20,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'assets/branding/telegram_qr.png',
                          width: 66,
                          height: 66,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 66,
                            height: 66,
                            color: primaryColor.withValues(alpha: 0.08),
                            child: Icon(Icons.qr_code_2_rounded, size: 36, color: primaryColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '扫码加入频道',
                        style: TextStyle(
                          color: AppColors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
