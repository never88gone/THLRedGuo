import 'package:flutter/foundation.dart';
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
import 'package:THLRedLook/core/player/playback_diagnostics.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/core/player/player_interactions.dart';
import 'package:THLRedLook/views/player/player_menu.dart';
import 'package:THLRedLook/pages/sources/sources_page.dart';
import 'package:THLRedLook/views/television/television_controls.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/player/desktop_pip_overlay.dart';
import 'package:THLRedLook/views/player/player_controls_view.dart';
import 'package:THLRedLook/views/player/player_loading_overlay_view.dart';
import 'package:THLRedLook/views/player/player_pip_placeholder_view.dart';
import 'package:THLRedLook/views/player/player_save_warning_banner.dart';
import 'package:THLRedLook/views/player/episode_transition_view.dart';
import 'package:THLRedLook/models/danmaku/danmaku_models.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';

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
    this.onDismissSaveWarning,
    required this.onOpenPanel,
    required this.onToggleDanmaku,
    this.onDanmakuSettings,
    required this.onRetryDanmaku,
    required this.onPushToDevice,
    this.onCast,
    this.casting = false,
    this.castOverlay,
    required this.onEnterPictureInPicture,
    this.onRestorePictureInPicture,
    required this.onTelevisionEpisodes,
    required this.onTelevisionSettings,
    this.onComments,
    this.onFetchDiagnostics,
    this.fillStyle,
    this.topPadding = 0.0,
    this.videoFit = BoxFit.contain,
    this.backgroundAudio = false,
    this.onToggleBackgroundAudio,
    this.episodeTransition = true,
  });

  final double topPadding;
  final PlayerFillStyle? fillStyle;
  final BoxFit videoFit;
  final bool backgroundAudio;
  final bool episodeTransition;
  final VoidCallback? onToggleBackgroundAudio;
  final VoidCallback? onComments;
  final Future<PlaybackTechnicalDiagnostics?> Function()? onFetchDiagnostics;
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
  final VoidCallback? onDismissSaveWarning;
  final Future<void> Function(PlayerMenuSection) onOpenPanel;
  final Future<void> Function() onToggleDanmaku;
  final Future<void> Function()? onDanmakuSettings;
  final Future<void> Function() onRetryDanmaku;
  final Future<void> Function()? onPushToDevice;
  final Future<void> Function()? onCast;
  final bool casting;
  final Widget? castOverlay;
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
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    final showPipPlaceholder =
        hideOverlayForPictureInPicture && !isAndroid && !isDesktop;
    final Widget controls = showPipPlaceholder
        ? PlayerPipPlaceholderView(
            title: title,
            onBack: onBack,
            onRestorePictureInPicture: onRestorePictureInPicture,
          )
        : (hideOverlayForPictureInPicture && isDesktop)
        ? DesktopPipOverlay(
            player: player,
            title: title,
            onRestore: onRestorePictureInPicture,
            onBack: onBack,
            onTogglePlayback: onTogglePlayback,
          )
        : hideOverlayForPictureInPicture
        ? const SizedBox.shrink()
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
            onFetchDiagnostics: onFetchDiagnostics,
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
            onComments: onComments != null ? () async => onComments!() : null,
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
            onCast: onCast,
            casting: casting,
            onPictureInPicture: canUsePictureInPicture
                ? onEnterPictureInPicture
                : null,
            pictureInPictureRequested: pictureInPictureRequested,
            onPrevious: index > 0 ? () => onPlay(index - 1) : null,
            onNext: index + 1 < detail.episodes.length
                ? () => onPlay(index + 1)
                : null,
            backgroundAudio: backgroundAudio,
            onToggleBackgroundAudio: onToggleBackgroundAudio,
          );

    final layeredControls = Stack(
      fit: StackFit.expand,
      children: [
        if (!hideOverlayForPictureInPicture) ...[
          RepaintBoundary(
            child: DanmakuOverlay(
              controller: danmaku,
              aspectRatio: aspectRatio,
              style: danmakuStyle ?? const DanmakuStyle(),
            ),
          ),
          ?controlsOverlay,
        ],
        if (hideOverlayForPictureInPicture)
          controls
        else if (controlsOverlay == null)
          RepaintBoundary(child: controls),
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
              // 0. 最底层托底背景（根据用户设置的播放器填充样式：纯黑 / 当前主题色 / 短剧海报氛围）
              _buildFillBackground(context),
              Positioned(
                top: topPadding,
                left: 0,
                right: 0,
                bottom: 0,
                child: EpisodeTransitionView(
                  episodeIndex: index,
                  enabled: episodeTransition,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (videoBuilder != null)
                        videoBuilder!(layeredControls)
                      else if (player is LunaExoPlayer)
                        LunaExoVideoView(
                          player: player as LunaExoPlayer,
                          fit: videoFit,
                          controls: (_) => layeredControls,
                        )
                      else if (videoController != null)
                        Video(
                          controller: videoController!,
                          fit: videoFit,
                          controls: (_) => layeredControls,
                        ),
                      if (casting &&
                          castOverlay != null &&
                          !hideOverlayForPictureInPicture &&
                          !loading &&
                          error == null)
                        Positioned.fill(child: castOverlay!),
                      if (loading && !hideOverlayForPictureInPicture)
                        PlayerLoadingOverlayView(
                          drama: detail.drama,
                          repository: repository,
                          loadingMessage: loadingMessage,
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
                                  onPressed: () => DiaryService.showDiaryDialog(
                                    context,
                                    fetchDiagnostics: onFetchDiagnostics,
                                  ),
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
                    ],
                  ),
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
                PlayerSaveWarningBanner(
                  message: saveWarning!,
                  onRetry: onSaveProgress,
                  onDismiss: onDismissSaveWarning,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFillBackground(BuildContext context) {
    if (pictureInPictureVisible) {
      return const ColoredBox(color: AppColors.black);
    }
    final effectiveStyle = fillStyle ?? store.playbackPreferences.fillStyle;
    switch (effectiveStyle) {
      case PlayerFillStyle.black:
        return const ColoredBox(
          key: ValueKey('player-fill-background-black'),
          color: AppColors.black,
        );
      case PlayerFillStyle.theme:
        final mode = store.themeMode;
        final isDark = mode == 'dark' ||
            (mode != 'light' &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        final themeColor =
            isDark ? AppColors.darkBackground : AppColors.lightBackground;
        return ColoredBox(
          key: const ValueKey('player-fill-background-theme'),
          color: themeColor,
        );
      case PlayerFillStyle.cover:
        return KeyedSubtree(
          key: const ValueKey('player-fill-background-cover'),
          child: DramaBackdrop(
            drama: detail.drama,
            repository: repository,
            sigma: 32.0,
            dimColor: AppColors.blackWithAlpha(0.72),
          ),
        );
    }
  }
}
