import 'package:flutter/material.dart';

import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({
    super.key,
    required this.store,
  });

  final LocalStore store;

  static const _themes = [
    (
      key: 'system',
      title: '跟随系统',
      subtitle: '随设备的深色或浅色模式自动切换视觉主题',
      icon: Icons.brightness_auto_rounded,
    ),
    (
      key: 'dark',
      title: '深色模式',
      subtitle: '沉浸式暗黑背景，适合夜晚观剧，低功耗防眩光',
      icon: Icons.dark_mode_rounded,
    ),
    (
      key: 'light',
      title: '浅色模式',
      subtitle: '清爽明亮界面，适合白天或明亮环境阅读与挑选短剧',
      icon: Icons.light_mode_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final currentTheme = store.themeMode;

        return Scaffold(
          appBar: AppBar(
            title: const Text('外观与主题'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Text(
                '主题模式',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.hongguoRed,
                ),
              ),
              const SizedBox(height: 8),

              ..._themes.map((item) {
                final isSelected = currentTheme == item.key;
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  color: isSelected
                      ? (isDark ? AppColors.darkSurfaceHighest : AppColors.accentSubtle12)
                      : (isDark ? AppColors.darkCard : AppColors.greyLight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isSelected
                        ? const BorderSide(color: AppColors.hongguoRed, width: 1.5)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? AppColors.hongguoRed
                          : (isDark ? AppColors.darkSurfaceHighest : AppColors.greyLight),
                      child: Icon(
                        item.icon,
                        color: isSelected ? Colors.white : theme.iconTheme.color,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? AppColors.hongguoRed : null,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        item.subtitle,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.hongguoRed)
                        : null,
                    onTap: () async {
                      if (!isSelected) {
                        await saveUserChange(context, () => store.setThemeMode(item.key));
                      }
                    },
                  ),
                );
              }),

              const SizedBox(height: 16),
              Text(
                '品牌色彩',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.hongguoRed,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: AppColors.hongguoRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: const Text('品牌视觉色'),
                  subtitle: const Text('经典活力红 · 专为短剧打造的沉浸式主题色'),
                  trailing: const Icon(Icons.done_all_rounded, color: AppColors.hongguoRed),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
