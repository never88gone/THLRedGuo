import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../core_bridge.dart';
import '../../diary_service.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../../sources_screen.dart';
import '../../widgets.dart';

/// 播放器异常与加载状态覆盖层
class PlayerStatusOverlayView extends StatelessWidget {
  const PlayerStatusOverlayView({
    super.key,
    required this.loading,
    required this.loadingMessage,
    required this.error,
    required this.localFailure,
    required this.allowOnlineFallback,
    required this.localOnly,
    required this.repository,
    required this.store,
    required this.drama,
    required this.onRetry,
    required this.onSwitchOnline,
  });

  final bool loading;
  final String loadingMessage;
  final String? error;
  final bool localFailure;
  final bool allowOnlineFallback;
  final bool localOnly;
  final AppRepository repository;
  final LocalStore store;
  final Drama drama;
  final VoidCallback onRetry;
  final VoidCallback onSwitchOnline;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ColoredBox(
        color: AppColors.blackWithAlpha(0.78),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.hongguoRed),
              const SizedBox(height: 16),
              Text(
                loadingMessage,
                style: const TextStyle(color: AppColors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (error != null) {
      return ColoredBox(
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
                onPressed: () => DiaryService.showDiaryDialog(context),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('查看播放日记'),
              ),
              if (localFailure && allowOnlineFallback)
                TextButton.icon(
                  onPressed: onSwitchOnline,
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('改为在线播放'),
                )
              else if (!localFailure && !localOnly && repository.supportsSourceManagement)
                SourceDiagnosticsButton(
                  repository: repository,
                  store: store,
                  drama: drama,
                ),
            ],
          ),
          icon: Icons.play_disabled_rounded,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
