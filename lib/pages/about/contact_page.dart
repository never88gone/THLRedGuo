import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/about/contact_channel_tile.dart';
import 'package:THLRedLook/views/about/contact_telegram_card.dart';
import 'package:THLRedLook/views/about/contact_info_card.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  static const String emailAddress = 'support@thltv.com';
  static const String githubUrl = 'https://github.com/never88gone/THLRedGuo';
  static const String telegramUrl = 'https://t.me/tanghulutvos';
  static const String telegramChannel = '@tanghulutvos';

  Future<void> _openUrl(BuildContext context, String url, String label) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        final fallback = await launchUrl(uri);
        if (!fallback && context.mounted) {
          _copyToClipboard(context, url, label);
        }
      }
    } catch (_) {
      if (context.mounted) {
        _copyToClipboard(context, url, label);
      }
    }
  }

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: emailAddress);
    try {
      final launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        _copyToClipboard(context, emailAddress, '邮箱地址');
      }
    } catch (_) {
      if (context.mounted) {
        _copyToClipboard(context, emailAddress, '邮箱地址');
      }
    }
  }

  Future<void> _openTelegram(BuildContext context) async {
    await _openUrl(context, telegramUrl, 'Telegram 地址');
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 $label：$text'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showQrDialog(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? AppColors.darkCard : AppColors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Telegram 频道二维码',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                telegramChannel,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.blackSubtle20,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/branding/telegram_qr.png',
                    width: 220,
                    height: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(
                        child: Icon(Icons.qr_code_2_rounded, size: 72, color: AppColors.hongguoRed),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(140, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('联系方式'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 640;

            final contactCards = [
              // 1. 官方支持邮箱卡片
              ContactChannelTile(
                icon: Icons.mail_outline_rounded,
                title: '官方支持与反馈邮箱',
                value: emailAddress,
                hint: '使用咨询、版权与技术反馈',
                primaryBtnKey: 'btn-open-email',
                primaryBtnText: '发送',
                primaryBtnIcon: Icons.email_rounded,
                onPrimary: () => _openEmail(context),
                copyBtnKey: 'btn-copy-email',
                onCopy: () => _copyToClipboard(context, emailAddress, '邮箱地址'),
              ),
              const SizedBox(height: 8),

              // 2. GitHub 官方开源卡片
              ContactChannelTile(
                icon: Icons.code_rounded,
                title: 'GitHub 官方开源仓库',
                value: githubUrl,
                hint: '透明开源维护，欢迎 Star 关注与共建',
                primaryBtnKey: 'btn-open-github',
                primaryBtnText: '访问',
                primaryBtnIcon: Icons.open_in_new_rounded,
                onPrimary: () => _openUrl(context, githubUrl, 'GitHub 地址'),
                copyBtnKey: 'btn-copy-github',
                onCopy: () => _copyToClipboard(context, githubUrl, 'GitHub 地址'),
              ),
              const SizedBox(height: 8),

              // 3. Telegram 官方频道卡片（横向集成二维码与直达）
              ContactTelegramCard(
                telegramChannel: telegramChannel,
                onOpenTelegram: () => _openTelegram(context),
                onCopyTelegram: () => _copyToClipboard(context, telegramUrl, 'Telegram 地址'),
                onShowQrDialog: () => _showQrDialog(context),
              ),
            ];

            const infoCard = ContactInfoCard();

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 11,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: contactCards,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              flex: 9,
                              child: infoCard,
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...contactCards,
                            const SizedBox(height: 10),
                            infoCard,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

}
