import 'dart:async';
import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/utils/theme/app_theme.dart';
import 'package:THLRedLook/core/danmaku/danmaku_controller.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/core/player/playback_preloader.dart';
import 'package:THLRedLook/views/player/player_menu.dart';
import 'package:THLRedLook/views/television/television_controls.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/player/player_quality_sheet_view.dart';
import 'package:THLRedLook/views/player/player_episodes_sheet_view.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';

/// 播放器弹窗与面板辅助工具类
class PlayerDialogHelper {
  const PlayerDialogHelper._();

  /// 打开移动端画质选择半屏沉浸式抽屉
  static Future<int?> openQualitySheet({
    required BuildContext context,
    required List<int> qualities,
    required int selectedQuality,
    required int actualQuality,
    required bool isLocal,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) => PlayerQualitySheetView(
        qualities: qualities,
        selectedQuality: selectedQuality,
        actualQuality: actualQuality,
        isLocal: isLocal,
        onQualitySelected: (quality) => Navigator.pop(sheetContext, quality),
      ),
    );
  }

  /// 打开移动端选集半屏沉浸式抽屉
  static Future<int?> openEpisodesSheet({
    required BuildContext context,
    required List<Episode> episodes,
    required int currentIndex,
    String? dramaTitle,
    List<HongguoSeriesEntry> seriesEntries = const [],
    String? currentDramaId,
    ValueChanged<Drama>? onSeasonSelected,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) => PlayerEpisodesSheetView(
        episodes: episodes,
        currentIndex: currentIndex,
        dramaTitle: dramaTitle,
        seriesEntries: seriesEntries,
        currentDramaId: currentDramaId,
        onEpisodeSelected: (index) => Navigator.pop(sheetContext, index),
        onSeasonSelected: (drama) {
          Navigator.pop(sheetContext);
          onSeasonSelected?.call(drama);
        },
      ),
    );
  }

  /// 打开移动端/通用选集与设置面板
  static Future<int?> openMenuPanel({
    required BuildContext context,
    required PlayerMenuSection section,
    required DramaDetail detail,
    required int currentIndex,
    required PlaybackPreferences preferences,
    required PlaybackPlan? plan,
    required LocalStore store,
    required DanmakuController danmaku,
    required PlaybackPreloader preloader,
    required VideoEnhancementController enhancement,
    required VideoEnhancementController? enhancementForUi,
    required bool fullscreen,
    required bool mobile,
    required Listenable menuRevision,
    required Future<void> Function(PlaybackPreferences) onPreferences,
  }) async {
    final menuTheme = fullscreen ? AppTheme.dark : Theme.of(context);
    return showDialog<int>(
      context: context,
      builder: (menuContext) => AnimatedBuilder(
        animation: Listenable.merge([menuRevision, store, danmaku, preloader]),
        builder: (_, _) => Theme(
          data: menuTheme,
          child: PlayerMenu(
            section: section,
            episodes: detail.episodes,
            currentIndex: currentIndex,
            preferences: preferences,
            qualities: plan?.qualities ?? [],
            actualQuality: plan?.quality ?? 0,
            local: plan?.offline == true,
            favorite: store.isFavorite(detail.drama.id),
            mobile: mobile,
            onEpisode: (index) => Navigator.pop(menuContext, index),
            onPreferences: onPreferences,
            showDanmaku: detail.drama.source == 'hongguo',
            danmakuStatus: danmaku.status,
            onRetryDanmaku: danmaku.canRetry ? danmaku.retry : null,
            preloadStatus: preloader.status,
            enhancement: enhancementForUi,
            onCompareEnhancement: () {
              unawaited(enhancement.toggleCompare());
              Navigator.pop(menuContext);
            },
            onFavorite: () => store.toggleFavorite(detail.drama),
          ),
        ),
      ),
    );
  }

  /// 打开电视端选集面板
  static Future<int?> openTelevisionEpisodes({
    required BuildContext context,
    required List<Episode> episodes,
    required int currentIndex,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => Theme(
        data: televisionTheme(AppTheme.dark),
        child: TelevisionEpisodeDialog(
          episodes: episodes,
          currentIndex: currentIndex,
        ),
      ),
    );
  }

  /// 打开电视端设置面板
  static Future<TelevisionPlaybackSetting?> openTelevisionSettings({
    required BuildContext context,
    required double speed,
    required int quality,
    required List<int> qualities,
    required bool favorite,
    required VoidCallback onFavorite,
    required bool autoAdvance,
    required bool danmaku,
    required bool showDanmaku,
    required String danmakuStatus,
    required VoidCallback? onRetryDanmaku,
    required bool preload,
    required String preloadStatus,
    required VideoEnhancementController enhancement,
    required VideoEnhancementController? enhancementForUi,
    required DanmakuController danmakuController,
    required PlaybackPreloader preloader,
  }) {
    return showDialog<TelevisionPlaybackSetting>(
      context: context,
      builder: (menuContext) => AnimatedBuilder(
        animation: Listenable.merge([danmakuController, preloader]),
        builder: (_, _) => Theme(
          data: televisionTheme(AppTheme.dark),
          child: TelevisionSettingsDialog(
            speed: speed,
            quality: quality,
            qualities: qualities,
            favorite: favorite,
            onFavorite: onFavorite,
            autoAdvance: autoAdvance,
            danmaku: danmaku,
            showDanmaku: showDanmaku,
            danmakuStatus: danmakuStatus,
            onRetryDanmaku: onRetryDanmaku,
            preload: preload,
            preloadStatus: preloadStatus,
            enhancement: enhancementForUi,
            onCompareEnhancement: () {
              unawaited(enhancement.toggleCompare());
              Navigator.pop(menuContext);
            },
          ),
        ),
      ),
    );
  }
}
