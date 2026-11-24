import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/pages/settings/player_fill_settings_page.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/settings/settings_option_pill.dart';
import 'package:THLRedLook/views/settings/settings_switch_tile.dart';
import 'package:THLRedLook/views/settings/settings_tile.dart';

class PlaybackSettingsPage extends StatelessWidget {
  const PlaybackSettingsPage({
    super.key,
    required this.store,
  });

  final LocalStore store;

  Future<void> _chooseQuality(BuildContext context) async {
    final qualities = [
      {'label': '自动 · 优先原画', 'value': 0},
      {'label': '1080P · 超清', 'value': 1080},
      {'label': '720P · 高清', 'value': 720},
      {'label': '480P · 标清', 'value': 480},
    ];
    final selected = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '默认起播画质',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (var i = 0; i < qualities.length; i++)
              SettingsTile(
                autofocus: i == 0,
                title: Text(qualities[i]['label'] as String),
                trailing: store.playbackPreferences.quality ==
                        (qualities[i]['value'] as int)
                    ? const Icon(Icons.check_rounded, color: AppColors.hongguoRed)
                    : null,
                onTap: () => Navigator.pop(context, qualities[i]['value'] as int),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) {
      final updated = store.playbackPreferences.copyWith(quality: selected);
      await saveUserChange(context, () => store.setPlaybackPreferences(updated));
    }
  }

  Future<void> _chooseSpeed(BuildContext context) async {
    final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final selected = await showModalBottomSheet<double>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '默认播放倍速',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (var i = 0; i < speeds.length; i++)
              SettingsTile(
                autofocus: i == 0,
                title: Text('${speeds[i]}x${speeds[i] == 1.0 ? ' (正常速度)' : ''}'),
                trailing: store.playbackPreferences.speed == speeds[i]
                    ? const Icon(Icons.check_rounded, color: AppColors.hongguoRed)
                    : null,
                onTap: () => Navigator.pop(context, speeds[i]),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) {
      final updated = store.playbackPreferences.copyWith(speed: selected);
      await saveUserChange(context, () => store.setPlaybackPreferences(updated));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isTv = AppLayout.isTelevision(context);

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final prefs = store.playbackPreferences;
        final qualityLabel = switch (prefs.quality) {
          1080 => '1080P 超清',
          720 => '720P 高清',
          480 => '480P 标清',
          _ => '自动（优先原画）',
        };

        return Scaffold(
          appBar: AppBar(
            title: const Text('播放设置'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Text(
                '基础播放偏好',
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SettingsTile(
                        autofocus: isTv,
                        leading: const Icon(Icons.hd_outlined),
                        title: const Text('默认起播画质'),
                        subtitle: Text(qualityLabel),
                        onTap: () => _chooseQuality(context),
                      ),
                      const Divider(height: 1, indent: 56),
                      SettingsTile(
                        leading: const Icon(Icons.speed_rounded),
                        title: const Text('默认播放倍速'),
                        subtitle: Text('${prefs.speed}x'),
                        onTap: () => _chooseSpeed(context),
                      ),
                      const Divider(height: 1, indent: 56),
                      SettingsTile(
                        key: const ValueKey('playback-settings-fill-style-entry'),
                        leading: const Icon(Icons.aspect_ratio_rounded),
                        title: const Text('播放器填充样式'),
                        subtitle: Text(prefs.fillStyle.label),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PlayerFillSettingsPage(store: store),
                          ),
                        ),
                      ),
                      if (defaultTargetPlatform == TargetPlatform.android ||
                          defaultTargetPlatform == TargetPlatform.iOS) ...[
                        const Divider(height: 1, indent: 56),
                        SettingsSwitchTile(
                          key: const ValueKey('settings-pip-switch'),
                          leading: const Icon(Icons.picture_in_picture_alt_rounded),
                          title: const Text('画中画模式'),
                          subtitle: Text(
                            prefs.pictureInPicture
                                ? '已开启画中画，播放时支持悬浮小窗播放'
                                : '关闭后播放器隐藏画中画入口',
                          ),
                          value: prefs.pictureInPicture,
                          onChanged: (val) async {
                            final updated = prefs.copyWith(pictureInPicture: val);
                            await saveUserChange(
                              context,
                              () => store.setPlaybackPreferences(updated),
                            );
                          },
                        ),
                        const Divider(height: 1, indent: 56),
                        SettingsSwitchTile(
                          key: const ValueKey('settings-background-audio-switch'),
                          leading: const Icon(Icons.headphones_rounded),
                          title: const Text('后台收听（听剧模式）'),
                          subtitle: Text(
                            prefs.backgroundAudio
                                ? '退至后台或锁屏时保持声音连续播放，接管锁屏控制'
                                : '退至后台或锁屏时自动暂停播放',
                          ),
                          value: prefs.backgroundAudio,
                          onChanged: (val) async {
                            final updated = prefs.copyWith(backgroundAudio: val);
                            await saveUserChange(
                              context,
                              () => store.setPlaybackPreferences(updated),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              Text(
                '弹幕呈现偏好',
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SettingsSwitchTile(
                        leading: const Icon(Icons.comment_bank_outlined),
                        title: const Text('弹幕总开关'),
                        subtitle: Text(prefs.danmaku ? '已开启弹幕渲染' : '默认静默不显示弹幕'),
                        value: prefs.danmaku,
                        onChanged: (val) async {
                          final updated = prefs.copyWith(danmaku: val);
                          await saveUserChange(context, () => store.setPlaybackPreferences(updated));
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.format_size_rounded,
                                  size: 22,
                                  color: isDark ? AppColors.whiteWithAlpha(0.7) : AppColors.greyDark,
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  '弹幕字号',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  switch (prefs.danmakuStyle.fontSizeScale) {
                                    < 0.9 => '小号 (0.8x)',
                                    > 1.3 => '特大 (1.5x)',
                                    > 1.1 => '大号 (1.25x)',
                                    _ => '标准 (1.0x)',
                                  },
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.hongguoRed,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (final (scale, label) in [
                                  (0.8, '小'),
                                  (1.0, '标准'),
                                  (1.25, '大'),
                                  (1.5, '特大'),
                                ])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: SettingsOptionPill(
                                        key: ValueKey('settings-danmaku-size-$scale'),
                                        label: label,
                                        selected: (prefs.danmakuStyle.fontSizeScale - scale).abs() < 0.05,
                                        isDark: isDark,
                                        onTap: () async {
                                          final updated = prefs.copyWith(
                                            danmakuStyle: prefs.danmakuStyle.copyWith(fontSizeScale: scale),
                                          );
                                          await saveUserChange(context, () => store.setPlaybackPreferences(updated));
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.opacity_rounded,
                                  size: 22,
                                  color: isDark ? AppColors.whiteWithAlpha(0.7) : AppColors.greyDark,
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  '弹幕不透明度',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${(prefs.danmakuStyle.opacity * 100).toInt()}%',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.hongguoRed,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (final (op, label) in [
                                  (0.4, '40%'),
                                  (0.6, '60%'),
                                  (0.8, '80%'),
                                  (1.0, '100%'),
                                ])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: SettingsOptionPill(
                                        key: ValueKey('settings-danmaku-opacity-$op'),
                                        label: label,
                                        selected: (prefs.danmakuStyle.opacity - op).abs() < 0.05,
                                        isDark: isDark,
                                        onTap: () async {
                                          final updated = prefs.copyWith(
                                            danmakuStyle: prefs.danmakuStyle.copyWith(opacity: op),
                                          );
                                          await saveUserChange(context, () => store.setPlaybackPreferences(updated));
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
