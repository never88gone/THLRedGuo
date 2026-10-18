import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

class ThirdPartyPage extends StatelessWidget {
  const ThirdPartyPage({super.key});

  static const List<Map<String, String>> components = [
    {
      'name': 'Flutter SDK',
      'license': 'BSD-3-Clause',
      'version': '3.29.x',
      'description': 'Google 跨平台现代响应式 UI 渲染框架与基础运行环境。',
    },
    {
      'name': 'media_kit & media_kit_video',
      'license': 'MIT',
      'version': '^1.2.6 / ^2.0.1',
      'description': '全平台高性能硬件解码音视频底层引擎，基于 libmpv。',
    },
    {
      'name': 'video_player',
      'license': 'BSD-3-Clause',
      'version': '^2.9.2',
      'description': 'Flutter 官方原生音视频播放与流媒体基础播放驱动。',
    },
    {
      'name': 'flutter_js',
      'license': 'MIT',
      'version': '^0.8.7',
      'description': '端侧独立沙箱 JavaScript 解释器与执行运行时。',
    },
    {
      'name': 'url_launcher',
      'license': 'BSD-3-Clause',
      'version': '^6.3.3',
      'description': '跨平台安全调起系统外部应用、浏览器与协议链接。',
    },
    {
      'name': 'http',
      'license': 'BSD-3-Clause',
      'version': '^1.6.0',
      'description': '高并发可组合异步 HTTP 网络请求与响应处理库。',
    },
    {
      'name': 'html',
      'license': 'BSD-3-Clause',
      'version': '^0.15.7',
      'description': '本地 HTML/DOM 语法树解析、清洗与元素提取工具。',
    },
    {
      'name': 'shared_preferences',
      'license': 'BSD-3-Clause',
      'version': '^2.5.5',
      'description': '本地轻量键值偏好设置、历史与播放状态持久化存储。',
    },
    {
      'name': 'wakelock_plus',
      'license': 'MIT',
      'version': '^1.8.1',
      'description': '视频播放与分集批量下载过程中的设备防息屏看护。',
    },
    {
      'name': 'window_manager',
      'license': 'MIT',
      'version': '^0.5.1',
      'description': '桌面端窗口控制、全屏影院模式与视窗尺寸管理。',
    },
    {
      'name': 'package_info_plus',
      'license': 'BSD-3-Clause',
      'version': '^10.2.1',
      'description': '读取宿主操作系统应用包名、版本号与构建编号元数据。',
    },
    {
      'name': 'path_provider',
      'license': 'BSD-3-Clause',
      'version': '^2.1.5',
      'description': '跨平台标准应用沙箱目录与离线存储路径寻址。',
    },
    {
      'name': 'file_picker',
      'license': 'MIT',
      'version': '13.1.0',
      'description': '系统本地文件浏览、自定义数据源脚本导入与备份选择器。',
    },
    {
      'name': 'ffmpeg_kit_flutter_new_min_gpl',
      'license': 'LGPL-3.0',
      'version': '2.6.2',
      'description': '本地高性能音视频封装、流合并与格式转码工具链。',
    },
    {
      'name': 'crypto',
      'license': 'BSD-3-Clause',
      'version': '^3.0.7',
      'description': '数据散列、安全哈希算法计算与防篡改校验套件。',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('第三方开源组件'),
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
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.handshake_outlined,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '致敬开源贡献',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '糖葫芦Haw 基于优秀的开源技术生态构建，各组件版权均归原作者所有。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                                height: 1.4,
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
              for (final comp in components) ...[
                Card(
                  elevation: 0,
                  color: isDark ? AppColors.darkCard : AppColors.greyLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                comp['name']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                comp['license']!,
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          comp['description']!,
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('btn-system-license-page'),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('查看完整依赖许可文本 (LicensePage)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  showLicensePage(
                    context: context,
                    applicationName: '糖葫芦Haw',
                    applicationVersion: '1.0.0',
                    applicationIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/branding/app_icon.png',
                          width: 48,
                          height: 48,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.play_circle_filled_rounded,
                            size: 48,
                            color: AppColors.hongguoRed,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
