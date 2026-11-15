import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

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
              _buildCompactChannelTile(
                context,
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
              _buildCompactChannelTile(
                context,
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
              _buildCompactTelegramCard(context),
            ];

            final infoCard = _buildCompactInfoCard(context);

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
                            Expanded(
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

  Widget _buildCompactChannelTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required String hint,
    required String primaryBtnKey,
    required String primaryBtnText,
    required IconData primaryBtnIcon,
    required VoidCallback onPrimary,
    required String copyBtnKey,
    required VoidCallback onCopy,
  }) {
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
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonal(
                  key: ValueKey(primaryBtnKey),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(48, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: onPrimary,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(primaryBtnIcon, size: 14),
                      const SizedBox(width: 4),
                      Text(primaryBtnText, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  key: ValueKey(copyBtnKey),
                  tooltip: '复制',
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(32, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: onCopy,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactTelegramCard(BuildContext context) {
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
                        onPressed: () => _openTelegram(context),
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
                        onPressed: () => _copyToClipboard(
                          context,
                          telegramUrl,
                          'Telegram 地址',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: () => _showQrDialog(context),
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

  Widget _buildCompactInfoCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.help_outline_rounded,
                  color: theme.colorScheme.primary,
                  size: 16,
                ),
                const SizedBox(width: 6),
                const Text(
                  '交流与反馈说明',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCompactInfoRow(
              context,
              icon: Icons.chat_bubble_outline_rounded,
              title: '功能体验与建议',
              detail: '欢迎分享您的观看体验与改进设想，共同完善软件功能。',
            ),
            const SizedBox(height: 6),
            _buildCompactInfoRow(
              context,
              icon: Icons.bug_report_outlined,
              title: '异常与排查诊断',
              detail: '若遇播放失败，可在【设置 - 数据源诊断】中复制脱敏报告协助排查。',
            ),
            const SizedBox(height: 6),
            _buildCompactInfoRow(
              context,
              icon: Icons.verified_user_outlined,
              title: '开源社区与共建',
              detail: '遵循开源规范透明维护，技术探讨与反馈欢迎通过邮件与 GitHub 交流。',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactInfoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: theme.textTheme.bodySmall?.color,
                fontSize: 11.5,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$title：',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
