import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/build/app_build.dart';

class AppIntroPage extends StatelessWidget {
  const AppIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('应用说明'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.accentSubtle12,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: AppColors.hongguoRed,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '全平台独立短剧与流媒体聚合播放器',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '本应用专注于提供沉浸、纯粹、高效的短剧视听体验。所有网络请求、站源解析、加密解密和流媒体调度均在您的设备本地端侧直接完成，不依赖任何自建云端中转服务器，充分保障速度与私密性。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.stars_rounded, color: theme.colorScheme.primary, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            '核心特性与优势',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureTile(
                        context,
                        icon: Icons.bolt_rounded,
                        title: '端侧闭环解析',
                        description: '内置独立 JavaScript 沙箱环境与解密驱动，站源协议实时动态执行，毫秒级直接获取高清直链。',
                      ),
                      const Divider(height: 24),
                      _buildFeatureTile(
                        context,
                        icon: Icons.devices_rounded,
                        title: '多端全场景适配',
                        description: '针对触屏手势、电脑键鼠与电视遥控器进行专用 UI 布局优化，支持沉浸全屏、画中画及大屏焦点漫游。',
                      ),
                      const Divider(height: 24),
                      _buildFeatureTile(
                        context,
                        icon: Icons.speed_rounded,
                        title: '极速播放与倍速切换',
                        description: '底层集成硬件加速解码引擎，支持 0.5x ~ 3.0x 多档流畅倍速即时生效与记忆保存。',
                      ),
                      const Divider(height: 24),
                      _buildFeatureTile(
                        context,
                        icon: Icons.subtitles_rounded,
                        title: '个性化实时弹幕',
                        description: '支持弹幕字体比例、透明度及显示区域自由调节，长按弹幕按钮随时唤起快速设置。',
                      ),
                      const Divider(height: 24),
                      _buildFeatureTile(
                        context,
                        icon: Icons.download_done_rounded,
                        title: '并发离线下载',
                        description: '支持全集批量队列调度、断点续传与离线播放，通勤旅途无网环境下随时畅快追剧。',
                      ),
                      const Divider(height: 24),
                      _buildFeatureTile(
                        context,
                        icon: Icons.security_rounded,
                        title: '本地隐私与保险箱',
                        description: '观看进度与追剧收藏全部保存在本地，支持配置独立手势密码与私密安全锁。',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tips_and_updates_rounded, color: AppColors.warning, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '常用操作技巧',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTipItem('双击屏幕中央快速暂停或恢复播放；'),
                      _buildTipItem('屏幕左侧上下滑动调节屏幕亮度，右侧上下滑动调节音量；'),
                      _buildTipItem('轻触右上方弹幕按钮快速切换开关，长按可进入详细弹幕样式微调；'),
                      _buildTipItem('播放器右下角轻点「倍速」即可呼出紧凑倍速抽屉，点击选项即刻变速生效。'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accentSubtle12,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.hongguoRed),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: theme.textTheme.bodySmall?.color,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, height: 1.5)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
