import 'dart:math';
import 'package:flutter/material.dart';

import '../../hongguo_series.dart';
import '../../models.dart';
import '../../utils/theme/app_colors.dart';

/// 移动端沉浸式选集半屏抽屉面板
class PlayerEpisodesSheetView extends StatefulWidget {
  const PlayerEpisodesSheetView({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onEpisodeSelected,
    this.dramaTitle,
    this.seriesEntries = const [],
    this.currentDramaId,
    this.onSeasonSelected,
  });

  final List<Episode> episodes;
  final int currentIndex;
  final ValueChanged<int> onEpisodeSelected;
  final String? dramaTitle;
  final List<HongguoSeriesEntry> seriesEntries;
  final String? currentDramaId;
  final ValueChanged<Drama>? onSeasonSelected;

  @override
  State<PlayerEpisodesSheetView> createState() => _PlayerEpisodesSheetViewState();
}

class _PlayerEpisodesSheetViewState extends State<PlayerEpisodesSheetView> {
  static const int _groupSize = 30;
  bool _isReversed = false;
  late int _selectedGroupIndex;

  @override
  void initState() {
    super.initState();
    _initSelectedGroup();
  }

  void _initSelectedGroup() {
    final validIndex = widget.currentIndex.clamp(0, max(0, widget.episodes.length - 1));
    _selectedGroupIndex = widget.episodes.isEmpty ? 0 : validIndex ~/ _groupSize;
  }

  int get _totalGroups => widget.episodes.isEmpty
      ? 1
      : ((widget.episodes.length - 1) ~/ _groupSize) + 1;

  List<int> _getIndicesForGroup(int groupIndex) {
    if (widget.episodes.isEmpty) return [];
    final start = groupIndex * _groupSize;
    final end = min(start + _groupSize, widget.episodes.length);
    final list = List<int>.generate(end - start, (i) => start + i);
    return _isReversed ? list.reversed.toList() : list;
  }

  String _groupLabel(int groupIndex) {
    if (widget.episodes.isEmpty) return '1-1';
    final start = groupIndex * _groupSize + 1;
    final end = min((groupIndex + 1) * _groupSize, widget.episodes.length);
    return '$start-$end';
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.episodes;
    final currentEp = episodes.isNotEmpty && widget.currentIndex >= 0 && widget.currentIndex < episodes.length
        ? episodes[widget.currentIndex]
        : null;

    final groupIndices = _getIndicesForGroup(_selectedGroupIndex);

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.58,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部抓手指示条
            Center(
              child: Container(
                width: 38,
                height: 3.5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.whiteWithAlpha(0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 标题与排序切换行
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '选集',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '共 ${episodes.length} 集',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiaryDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        currentEp != null
                            ? '当前播放：第 ${currentEp.number} 集'
                            : '轻点卡片即刻切换播放',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.hongguoRed,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // 正序/倒序切换胶囊按钮（圆润 Pill 造型，消除硬朗边角）
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _isReversed = !_isReversed),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurfaceHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.whiteWithAlpha(0.04)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isReversed ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          size: 13,
                          color: AppColors.textSecondaryDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isReversed ? '倒序' : '正序',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondaryDark),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            // 剧集分多季时的快速季切换栏
            if (widget.seriesEntries.length > 1) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.layers_rounded, size: 14, color: AppColors.hongguoRed),
                  const SizedBox(width: 4),
                  const Text(
                    '系列多季',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accentTrack35,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '共 ${widget.seriesEntries.length} 季',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.hongguoRed,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '快速切季',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 6, bottom: 4),
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.seriesEntries.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, sIdx) {
                    final sEntry = widget.seriesEntries[sIdx];
                    final isCurrentSeason = sEntry.drama.id == widget.currentDramaId;
                    return InkWell(
                      borderRadius: BorderRadius.circular(17),
                      onTap: isCurrentSeason
                          ? null
                          : () => widget.onSeasonSelected?.call(sEntry.drama),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isCurrentSeason
                              ? AppColors.hongguoRed
                              : AppColors.darkSurfaceElevated,
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: isCurrentSeason
                                ? AppColors.hongguoRed
                                : AppColors.whiteWithAlpha(0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCurrentSeason) ...[
                              const Icon(Icons.play_circle_fill_rounded, size: 14, color: AppColors.textPrimaryDark),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              sEntry.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isCurrentSeason ? FontWeight.bold : FontWeight.w500,
                                color: isCurrentSeason ? AppColors.textPrimaryDark : AppColors.textSecondaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 12),
            // 分组胶囊条（全圆角流体胶囊，消除硬边线）
            if (_totalGroups > 1) ...[
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _totalGroups,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, gIdx) {
                    final isSelected = gIdx == _selectedGroupIndex;
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _selectedGroupIndex = gIdx),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.hongguoRedWithAlpha(0.14)
                              : AppColors.darkSurfaceHigh,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.hongguoRedWithAlpha(0.5)
                                : AppColors.whiteWithAlpha(0.03),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          _groupLabel(gIdx),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? AppColors.hongguoRed
                                : AppColors.textSecondaryDark,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 集数网格卡片区（柔和 12px 圆角 + 品牌渐变微光，消除 8px 硬框）
            Expanded(
              child: episodes.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无可用剧集',
                        style: TextStyle(color: AppColors.textTertiaryDark, fontSize: 13),
                      ),
                    )
                  : GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        crossAxisSpacing: 9,
                        mainAxisSpacing: 9,
                        childAspectRatio: 1.25,
                      ),
                      itemCount: groupIndices.length,
                      itemBuilder: (context, index) {
                        final epIndex = groupIndices[index];
                        final ep = episodes[epIndex];
                        final isPlaying = epIndex == widget.currentIndex;

                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            widget.onEpisodeSelected(epIndex);
                            Navigator.pop(context);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: isPlaying ? null : AppColors.darkSurfaceHigh,
                              gradient: isPlaying
                                  ? const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppColors.hongguoRed,
                                        AppColors.hongguoOrange,
                                      ],
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                              border: isPlaying
                                  ? null
                                  : Border.all(
                                      color: AppColors.whiteWithAlpha(0.03),
                                      width: 0.8,
                                    ),
                              boxShadow: isPlaying
                                  ? [
                                      BoxShadow(
                                        color: AppColors.hongguoRedWithAlpha(0.35),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${ep.number}',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isPlaying
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: isPlaying
                                            ? AppColors.white
                                            : AppColors.textPrimaryDark,
                                      ),
                                    ),
                                    if (isPlaying) ...[
                                      const SizedBox(height: 2),
                                      const Text(
                                        '播放中',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.white,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
