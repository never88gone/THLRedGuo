import 'package:flutter/material.dart';

import 'package:THLRedLook/models/download/download_job.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class OfflineEpisodesSheet extends StatelessWidget {
  const OfflineEpisodesSheet({
    super.key,
    required this.completedJobs,
    required this.currentIndex,
    required this.onSelectEpisode,
  });

  final List<DownloadJob> completedJobs;
  final int currentIndex;
  final ValueChanged<int> onSelectEpisode;

  static void show({
    required BuildContext context,
    required List<DownloadJob> completedJobs,
    required int currentIndex,
    required ValueChanged<int> onSelectEpisode,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => OfflineEpisodesSheet(
        completedJobs: completedJobs,
        currentIndex: currentIndex,
        onSelectEpisode: onSelectEpisode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '离线已下载集数',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppColors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.4,
                ),
                itemCount: completedJobs.length,
                itemBuilder: (context, index) {
                  final isCurrent = index == currentIndex;
                  final job = completedJobs[index];
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onSelectEpisode(index);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppColors.hongguoRed
                            : AppColors.offlinePlayerPanel,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${job.episode.number}',
                        style: TextStyle(
                          color: AppColors.white,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
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
