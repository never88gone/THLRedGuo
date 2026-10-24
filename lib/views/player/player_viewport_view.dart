import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/utils/theme/app_theme.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/danmaku/danmaku_controller.dart';
import 'package:THLRedLook/views/danmaku/danmaku_overlay.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/core/player/player_interactions.dart';
import 'package:THLRedLook/views/player/player_menu.dart';
import 'package:THLRedLook/pages/sources/sources_page.dart';
import 'package:THLRedLook/views/television/television_controls.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/player/player_controls_view.dart';
import 'package:THLRedLook/models/danmaku/danmaku_models.dart';

/// 播放器画面视口组件（视频画面、手势、HUD、弹幕图层、加载中/错误兜底面板）
class PlayerViewportView extends StatelessWidget {
  const PlayerViewportView({
    super.key,
    required this.television,
    required this.fullscreen,
    required this.pictureInPictureVisible,
    this.pictureInPictureRequested = false,
    required this.mobile,
    required this.detail,
    required this.index,
    required this.plan,
    required this.loading,
    required this.loadingMessage,
    required this.error,
    required this.localFailure,
    required this.saveWarning,
    required this.player,
    required this.playbackRequested,
    required this.videoController,
    required this.danmaku,
    required this.danmakuEnabled,
    this.danmakuStyle,
    required this.aspectRatio,
    required this.interactions,
    required this.enhancement,
    required this.enhancementForUi,
    required this.speed,
    required this.qualityLabel,
    required this.showControlsOnPlaybackReady,
    required this.panelOpen,
    required this.canUsePictureInPicture,
    required this.playerFocus,
    required this.videoPaneKey,
    required this.allowOnlineFallback,
    required this.localOnly,
    required this.isMediaIdNull,
    required this.repository,
    required this.store,
    this.videoBuilder,
    this.controlsOverlay,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onSeekTo,
    required this.onPlay,
    required this.onRotate,
    required this.onBack,
    required this.onRetry,
    required this.onSwitchOnline,
    required this.onSaveProgress,
    required this.onOpenPanel,
    required this.onToggleDanmaku,
    this.onDanmakuSettings,
    required this.onRetryDanmaku,
    required this.onPushToDevice,
    required this.onEnterPictureInPicture,
    this.onRestorePictureInPicture,
    required this.onTelevisionEpisodes,
    required this.onTelevisionSettings,
  });

  final bool television;
  final bool fullscreen;
  final bool pictureInPictureVisible;
  final bool pictureInPictureRequested;
  final bool mobile;
  final DramaDetail detail;
  final int index;
  final PlaybackPlan? plan;
  final bool loading;
  final String loadingMessage;
  final String? error;
  final bool localFailure;
  final String? saveWarning;
  final Player player;
  final bool playbackRequested;
  final VideoController? videoController;
  final DanmakuController danmaku;
  final bool danmakuEnabled;
  final DanmakuStyle? danmakuStyle;
  final double aspectRatio;
  final PlayerInteractions interactions;
  final VideoEnhancementController enhancement;
  final VideoEnhancementController? enhancementForUi;
  final double speed;
  final String qualityLabel;
  final bool showControlsOnPlaybackReady;
  final bool panelOpen;
  final bool canUsePictureInPicture;
  final FocusNode playerFocus;
  final Key videoPaneKey;
  final bool allowOnlineFallback;
  final bool localOnly;
  final bool isMediaIdNull;
  final AppRepository repository;
  final LocalStore store;
  final Widget Function(Widget child)? videoBuilder;
  final Widget? controlsOverlay;

  final VoidCallback onTogglePlayback;
  final void Function(int) onSeek;
  final Future<void> Function(Duration) onSeekTo;
  final Future<void> Function(int) onPlay;
  final VoidCallback onRotate;
  final VoidCallback onBack;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSwitchOnline;
  final Future<void> Function() onSaveProgress;
  final Future<void> Function(PlayerMenuSection) onOpenPanel;
  final Future<void> Function() onToggleDanmaku;
  final Future<void> Function()? onDanmakuSettings;
  final Future<void> Function() onRetryDanmaku;
  final Future<void> Function()? onPushToDevice;
  final Future<void> Function()? onEnterPictureInPicture;
  final Future<void> Function()? onRestorePictureInPicture;
  final Future<void> Function(BuildContext) onTelevisionEpisodes;
  final Future<void> Function(BuildContext) onTelevisionSettings;

  @override
  Widget build(BuildContext context) {
    final videoTheme = television
        ? televisionTheme(AppTheme.dark)
        : AppTheme.dark;
    final isHongguo = detail.drama.source == 'hongguo' || detail.drama.id.startsWith('hongguo:');
    final isVipEp = !isHongguo && detail.episodes[index].vip;
    final title =
        '${detail.drama.title} · 第 ${detail.episodes[index].number} 集${plan?.offline == true ? ' · 本地' : ''}${isVipEp ? ' · VIP 试看' : ''}${(plan?.routeIndex ?? 0) > 0 ? ' · 线路 ${plan!.routeIndex + 1}' : ''}';
    final hideOverlayForPictureInPicture = pictureInPictureVisible;
    final Widget controls = hideOverlayForPictureInPicture
        ? Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Material(
                      color: AppColors.blackWithAlpha(0.6),
                      shape: const CircleBorder(),
                      child: IconButton(
                        key: const ValueKey('player-pip-viewport-back'),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        tooltip: '退出播放',
                        onPressed: onBack,
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.blackWithAlpha(0.78),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.hongguoRed.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.picture_in_picture_alt_rounded,
                          color: AppColors.hongguoRed,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '正在画中画窗口中播放',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('player-pip-restore-btn'),
                            onPressed: onRestorePictureInPicture,
                            icon: const Icon(Icons.fullscreen_rounded, size: 18),
                            label: const Text('恢复应用内播放'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.hongguoRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('player-pip-exit-btn'),
                            onPressed: onBack,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('退出播放'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        : television
        ? TelevisionControls(
            player: player,
            title: title,
            enabled: !loading && error == null,
            showOnPlaybackReady: showControlsOnPlaybackReady,
            enhancement: enhancementForUi,
            onTogglePlayback: onTogglePlayback,
            onSeek: onSeek,
            onPrevious: index > 0 ? () => onPlay(index - 1) : null,
            onNext: index + 1 < detail.episodes.length
                ? () => onPlay(index + 1)
                : null,
            onEpisodes: () => onTelevisionEpisodes(context),
            onSettings: () => onTelevisionSettings(context),
            onBack: onBack,
          )
        : PlayerControls(
            player: player,
            playbackRequested: playbackRequested,
            interactions: interactions,
            enabled: !loading && error == null,
            enhancement: enhancementForUi,
            panelOpen: panelOpen,
            fullscreen: fullscreen,
            showOnPlaybackReady: showControlsOnPlaybackReady,
            title: title,
            onTogglePlayback: onTogglePlayback,
            swipeEnabled: mobile,
            onFullscreen: onRotate,
            onBack: onBack,
            onFocusSurface: playerFocus.requestFocus,
            onSeek: onSeekTo,
            speed: speed,
            qualityLabel: qualityLabel,
            showDanmaku: detail.drama.source == 'hongguo',
            danmakuEnabled: danmakuEnabled,
            danmakuStatus: danmaku.status,
            onEpisodes: () => onOpenPanel(PlayerMenuSection.episodes),
            onSpeed: () => onOpenPanel(PlayerMenuSection.speed),
            onQuality: () => onOpenPanel(PlayerMenuSection.quality),
            onDanmaku: detail.drama.source == 'hongguo'
                ? onToggleDanmaku
                : null,
            onDanmakuSettings: detail.drama.source == 'hongguo'
                ? onDanmakuSettings
                : null,
            onRetryDanmaku: danmaku.canRetry ? onRetryDanmaku : null,
            onPush: isMediaIdNull ? onPushToDevice : null,
            onPictureInPicture: canUsePictureInPicture
                ? onEnterPictureInPicture
                : null,
            pictureInPictureRequested: pictureInPictureRequested,
            onPrevious: index > 0 ? () => onPlay(index - 1) : null,
            onNext: index + 1 < detail.episodes.length
                ? () => onPlay(index + 1)
                : null,
          );

    final layeredControls = Stack(
      fit: StackFit.expand,
      children: [
        if (!hideOverlayForPictureInPicture)
          DanmakuOverlay(
            controller: danmaku,
            aspectRatio: aspectRatio,
            style: danmakuStyle ?? const DanmakuStyle(),
          ),
        controlsOverlay ?? controls,
      ],
    );

    return Theme(
      data: videoTheme,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final pixels = Size(
            constraints.maxWidth * ratio,
            constraints.maxHeight * ratio,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            enhancement.setViewport(pixels, television: television);
          });
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: IgnorePointer(child: SizedBox.expand(key: videoPaneKey)),
              ),
              // 0. 最底层海报毛玻璃托底背景（环境漫反射底衬，消除纯黑边违和感）
              DramaBackdrop(
                drama: detail.drama,
                repository: repository,
                sigma: 32.0,
                dimColor: AppColors.blackWithAlpha(0.72),
              ),
              if (videoBuilder != null)
                videoBuilder!(layeredControls)
              else if (player is LunaExoPlayer)
                LunaExoVideoView(
                  player: player as LunaExoPlayer,
                  fit: BoxFit.contain,
                  controls: (_) => layeredControls,
                )
              else if (videoController != null)
                Video(
                  controller: videoController!,
                  fit: BoxFit.contain,
                  controls: (_) => layeredControls,
                ),
              if (loading && !hideOverlayForPictureInPicture)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.blackWithAlpha(0.60),
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Hero(
                            tag: 'drama-cover-${detail.drama.id}',
                            child: Container(
                              width: 104,
                              height: 156,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x77000000),
                                    blurRadius: 24,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: DramaCover(
                                drama: detail.drama,
                                repository: repository,
                                radius: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.hongguoRed,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            loadingMessage,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (error != null && !hideOverlayForPictureInPicture)
                ColoredBox(
                  color: AppColors.blackWithAlpha(0.9),
                  child: StatusPanel(
                    title: '暂时无法播放',
                    message: error!,
                    onRetry: onRetry,
                    action: localFailure ? '重试本地播放' : '重试播放',
                    secondaryAction: Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              DiaryService.showDiaryDialog(context),
                          icon: const Icon(Icons.receipt_long_rounded),
                          label: const Text('查看播放日记'),
                        ),
                        if (localFailure && allowOnlineFallback)
                          TextButton.icon(
                            onPressed: onSwitchOnline,
                            icon: const Icon(Icons.cloud_outlined),
                            label: const Text('改为在线播放'),
                          )
                        else if (!localFailure &&
                            !localOnly &&
                            repository.supportsSourceManagement)
                          SourceDiagnosticsButton(
                            repository: repository,
                            store: store,
                            drama: detail.drama,
                          ),
                      ],
                    ),
                    icon: Icons.play_disabled_rounded,
                  ),
                ),
              if ((loading || error != null) &&
                  !hideOverlayForPictureInPicture &&
                  fullscreen &&
                  !television)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '退出全屏',
                          onPressed: onRotate,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              onOpenPanel(PlayerMenuSection.episodes),
                          child: const Text('选集'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (saveWarning != null && !hideOverlayForPictureInPicture)
                Positioned(
                  top: 52,
                  left: 12,
                  right: 12,
                  child: SafeArea(
                    bottom: false,
                    child: Material(
                      color: AppColors.darkSurfaceHigh,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              saveWarning!,
                              style: const TextStyle(fontSize: 12),
                            ),
                            TextButton(
                              onPressed: onSaveProgress,
                              child: const Text('重试保存'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
