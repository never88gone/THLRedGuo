import 'package:flutter/material.dart';

import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';

class DisplayModePage extends StatelessWidget {
  const DisplayModePage({
    super.key,
    required this.store,
  });

  final LocalStore store;

  static const _modes = [
    (
      key: 'auto',
      title: '自动识别设备 (推荐)',
      subtitle: '根据当前屏幕分辨率、窗口比例及设备类型自适应切换界面布局与交互手势',
      icon: Icons.devices_rounded,
    ),
    (
      key: 'television',
      title: '电视 / 遥控器模式',
      subtitle: '专为大屏电视优化，提供大尺寸海报卡片、高对比度遥控器方向键焦点反馈',
      icon: Icons.tv_rounded,
    ),
    (
      key: 'standard',
      title: '手机 / 电脑模式',
      subtitle: '专为触控与鼠标滑轮设计，支持多列瀑布流、单指滑动切集与紧凑工具栏',
      icon: Icons.smartphone_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final currentMode = store.displayMode;

        return Scaffold(
          appBar: AppBar(
            title: const Text('页面模式'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accentSubtle12,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.dashboard_customize_rounded,
                          color: AppColors.hongguoRed,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '全平台界面呈现模式',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '根据不同使用场景随时切换，支持在大屏电视遥控、桌面电脑与移动手机间无缝流转。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                '选择界面呈现模式',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.hongguoRed,
                ),
              ),
              const SizedBox(height: 8),

              ..._modes.map((mode) {
                final isSelected = currentMode == mode.key;
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
                        mode.icon,
                        color: isSelected ? Colors.white : theme.iconTheme.color,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      mode.title,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? AppColors.hongguoRed : null,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        mode.subtitle,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.hongguoRed)
                        : null,
                    onTap: () async {
                      if (!isSelected) {
                        await saveUserChange(context, () => store.setDisplayMode(mode.key));
                      }
                    },
                  ),
                );
              }),

              const SizedBox(height: 16),
              Text(
                '显示与常亮设置',
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
                child: SwitchListTile(
                  secondary: const Icon(Icons.screen_lock_portrait_rounded),
                  title: const Text('禁止自动锁屏'),
                  subtitle: const Text('保持屏幕常亮，防止离线下载与挂机播放时设备自动息屏休眠'),
                  value: store.keepScreenOn,
                  activeThumbColor: AppColors.hongguoRed,
                  activeTrackColor: AppColors.accentTrack35,
                  onChanged: (val) async {
                    await saveUserChange(
                      context,
                      () => store.setKeepScreenOn(val),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
