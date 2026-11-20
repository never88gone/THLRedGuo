import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';

/// 播放器视口默认填充样式设置子页面
class PlayerFillSettingsPage extends StatelessWidget {
  const PlayerFillSettingsPage({
    super.key,
    required this.store,
  });

  final LocalStore store;

  Color _themeFillColor(BuildContext context) {
    final mode = store.themeMode;
    final isDark = mode == 'dark' ||
        (mode != 'light' &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return isDark ? AppColors.darkBackground : AppColors.lightBackground;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final currentStyle = store.playbackPreferences.fillStyle;
        final themeColor = _themeFillColor(context);

        return Scaffold(
          appBar: AppBar(
            title: const Text('播放器填充样式'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. 实时预览视口卡片
              _buildLivePreview(
                context,
                currentStyle: currentStyle,
                themeColor: themeColor,
                isDark: isDark,
              ),

              const SizedBox(height: 24),
              Text(
                '留白填充样式',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.hongguoRed,
                ),
              ),
              const SizedBox(height: 8),

              // 2. 三种填充模式卡片选项
              ...PlayerFillStyle.values.map((style) {
                final isSelected = currentStyle == style;
                final (icon, subtitle) = switch (style) {
                  PlayerFillStyle.black => (
                    Icons.dark_mode_rounded,
                    '传统经典纯黑底色，沉浸式观影无视觉打扰',
                  ),
                  PlayerFillStyle.theme => (
                    Icons.palette_outlined,
                    '使用当前应用主题背景色（跟随浅色/深色主题一体融合）',
                  ),
                  PlayerFillStyle.cover => (
                    Icons.image_outlined,
                    '提取当前短剧海报进行高斯模糊氛围填充，画面生动丰富',
                  ),
                };

                return Card(
                  key: ValueKey('fill-style-option-${style.name}'),
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
                        icon,
                        color: isSelected ? AppColors.white : theme.iconTheme.color,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      style.label,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? AppColors.hongguoRed : null,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.hongguoRed,
                            size: 22,
                          )
                        : null,
                    onTap: () async {
                      if (currentStyle == style) return;
                      final updated = store.playbackPreferences.copyWith(fillStyle: style);
                      await saveUserChange(
                        context,
                        () => store.setPlaybackPreferences(updated),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLivePreview(
    BuildContext context, {
    required PlayerFillStyle currentStyle,
    required Color themeColor,
    required bool isDark,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.blackWithAlpha(isDark ? 0.4 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 底层填充背景
                _buildPreviewBackground(currentStyle, themeColor),

                // 居中的 9:16 模拟短剧画面
                Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF3A2420),
                            Color(0xFF221411),
                            Color(0xFF140B09),
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.whiteWithAlpha(0.25),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blackWithAlpha(0.6),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppColors.whiteWithAlpha(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: AppColors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '短剧播放画面',
                                style: TextStyle(
                                  color: AppColors.whiteWithAlpha(0.85),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          // 模拟底部进度条
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 6,
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppColors.whiteWithAlpha(0.3),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: 28,
                                  decoration: BoxDecoration(
                                    color: AppColors.hongguoRed,
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 顶部提示条
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.blackWithAlpha(0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          color: AppColors.white,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '效果预览 · ${currentStyle.label}',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewBackground(PlayerFillStyle style, Color themeColor) {
    switch (style) {
      case PlayerFillStyle.black:
        return const ColoredBox(
          key: ValueKey('preview-background-black'),
          color: AppColors.black,
        );
      case PlayerFillStyle.theme:
        return ColoredBox(
          key: const ValueKey('preview-background-theme'),
          color: themeColor,
        );
      case PlayerFillStyle.cover:
        return Stack(
          key: const ValueKey('preview-background-cover'),
          fit: StackFit.expand,
          children: [
            // 模拟海报氛围渐变底色
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF8B2500),
                    Color(0xFF5E1914),
                    Color(0xFF1E0807),
                  ],
                ),
              ),
            ),
            // 高斯模糊与遮罩暗层
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: AppColors.blackWithAlpha(0.65),
                ),
              ),
            ),
          ],
        );
    }
  }
}
