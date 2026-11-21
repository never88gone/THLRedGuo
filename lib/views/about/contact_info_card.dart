import 'package:flutter/material.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 交流与反馈说明卡片
class ContactInfoCard extends StatelessWidget {
  const ContactInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
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
            _buildRow(
              context,
              icon: Icons.chat_bubble_outline_rounded,
              title: '功能体验与建议',
              detail: '欢迎分享您的观看体验与改进设想，共同完善软件功能。',
            ),
            const SizedBox(height: 6),
            _buildRow(
              context,
              icon: Icons.bug_report_outlined,
              title: '异常与排查诊断',
              detail: '若遇播放失败，可在【设置 - 数据源诊断】中复制脱敏报告协助排查。',
            ),
            const SizedBox(height: 6),
            _buildRow(
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

  Widget _buildRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 14,
            color: isDark ? AppColors.textSecondaryDark : theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$title：',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.white : AppColors.black,
                  ),
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
