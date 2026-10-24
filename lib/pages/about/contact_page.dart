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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('联系方式'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              // 1. 官方支持邮箱卡片
              _buildContactCard(
                context,
                icon: Icons.mail_outline_rounded,
                title: '官方支持与反馈邮箱',
                value: emailAddress,
                hint: '商务合作、使用咨询、版权与技术反馈，欢迎来信沟通',
                primaryBtnKey: 'btn-open-email',
                primaryBtnText: '发送邮件',
                primaryBtnIcon: Icons.email_rounded,
                onPrimary: () => _openEmail(context),
                copyBtnKey: 'btn-copy-email',
                copyBtnText: '复制邮箱',
                onCopy: () => _copyToClipboard(context, emailAddress, '邮箱地址'),
              ),
              const SizedBox(height: 16),

              // 2. GitHub 官方开源卡片
              _buildContactCard(
                context,
                icon: Icons.code_rounded,
                title: 'GitHub 官方开源仓库',
                value: githubUrl,
                hint: '面向开源社区透明维护，欢迎 Star 关注、提交 Issue 与参与共建',
                primaryBtnKey: 'btn-open-github',
                primaryBtnText: '打开 GitHub',
                primaryBtnIcon: Icons.open_in_new_rounded,
                onPrimary: () => _openUrl(context, githubUrl, 'GitHub 地址'),
                copyBtnKey: 'btn-copy-github',
                copyBtnText: '复制链接',
                onCopy: () => _copyToClipboard(context, githubUrl, 'GitHub 地址'),
              ),
              const SizedBox(height: 16),

              // 3. Telegram 官方频道与交流卡片
              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.send_rounded,
                          size: 36,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Telegram 官方交流与反馈',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        telegramChannel,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              isDark ? AppColors.darkSurface : AppColors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.blackSubtle20,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/branding/telegram_qr.png',
                            width: 180,
                            height: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 180,
                              height: 180,
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.08,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.qr_code_2_rounded,
                                    size: 56,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '扫码加入频道',
                                    style: TextStyle(
                                      color: theme.textTheme.bodySmall?.color,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '扫码上方二维码，或轻触下方按钮直接跳转',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              key: const ValueKey('btn-open-telegram'),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                              ),
                              label: const Text('直接打开 Telegram'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => _openTelegram(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            key: const ValueKey('btn-copy-telegram'),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('复制链接'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
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
              ),
              const SizedBox(height: 16),

              // 4. 说明卡片
              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.help_outline_rounded,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '交流与反馈说明',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoItem(
                        context,
                        icon: Icons.chat_bubble_outline_rounded,
                        title: '功能体验与建议',
                        detail:
                            '欢迎分享您的观看体验、改进建议，或者提出希望新增的播放与管理特性。',
                      ),
                      const Divider(height: 20),
                      _buildInfoItem(
                        context,
                        icon: Icons.bug_report_outlined,
                        title: '异常与排查诊断',
                        detail:
                            '若遇播放失败、无法加载等异常，可在【设置 - 数据源诊断】中复制脱敏报告协助排查。',
                      ),
                      const Divider(height: 20),
                      _buildInfoItem(
                        context,
                        icon: Icons.verified_user_outlined,
                        title: '开源社区与合作',
                        detail:
                            '本软件遵循开源规范开发，所有反馈与技术探讨均欢迎通过邮箱与 GitHub 进行。',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard(
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
    required String copyBtnText,
    required VoidCallback onCopy,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      color: isDark ? AppColors.darkCard : AppColors.greyLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              value,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: ValueKey(primaryBtnKey),
                    icon: Icon(primaryBtnIcon, size: 18),
                    label: Text(primaryBtnText),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  key: ValueKey(copyBtnKey),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(copyBtnText),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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

  Widget _buildInfoItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  color: theme.textTheme.bodySmall?.color,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
