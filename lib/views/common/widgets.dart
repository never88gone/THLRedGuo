import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/remote/remote_widgets.dart';
import 'package:THLRedLook/views/drama/drama_cover_view.dart';

export 'package:THLRedLook/views/drama/drama_cover_view.dart';

Future<void> saveUserChange(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未能保存，请检查存储空间和权限后重试。')));
    }
  }
}

class RefreshAction extends StatefulWidget {
  const RefreshAction({
    super.key,
    required this.loading,
    required this.tooltip,
    required this.onPressed,
  });
  final bool loading;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<RefreshAction> createState() => _RefreshActionState();
}

class _RefreshActionState extends State<RefreshAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (widget.loading) _rotation.repeat();
  }

  @override
  void didUpdateWidget(covariant RefreshAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading == oldWidget.loading) return;
    if (widget.loading) {
      _rotation.repeat();
    } else {
      _rotation.reset();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    value: widget.loading ? '正在更新' : null,
    child: IconButton(
      tooltip: widget.loading ? '正在更新' : widget.tooltip,
      onPressed: widget.loading ? null : widget.onPressed,
      disabledColor: widget.loading
          ? Theme.of(context).colorScheme.primary
          : null,
      icon: RotationTransition(
        turns: _rotation,
        child: const Icon(Icons.refresh_rounded),
      ),
    ),
  );
}

class DramaTile extends StatelessWidget {
  const DramaTile({
    super.key,
    required this.drama,
    required this.repository,
    required this.onTap,
    this.subtitle,
    this.focusNode,
    this.onFocus,
    this.actions,
    this.badge,
    this.selected,
    this.onMore,
    this.onLongPress,
    this.heroTag,
  });
  final Drama drama;
  final AppRepository repository;
  final VoidCallback onTap;
  final String? subtitle;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final Widget? actions;
  final String? badge;
  final bool? selected;
  final VoidCallback? onMore;
  final VoidCallback? onLongPress;
  final String? heroTag;

  static double titleHeight(BuildContext context) =>
      MediaQuery.textScalerOf(
        context,
      ).scale(AppLayout.isTelevision(context) ? 17 : 14) *
      2.6;

  static double subtitleHeight(BuildContext context) =>
      MediaQuery.textScalerOf(
        context,
      ).scale(AppLayout.isTelevision(context) ? 14 : 12) *
      1.3;

  static double extentFor(BuildContext context, double width) =>
      (width * 1.5 + 13 + titleHeight(context) + subtitleHeight(context))
          .ceilToDouble();

  @override
  Widget build(BuildContext context) {
    final television = AppLayout.isTelevision(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag ?? 'drama-cover-${drama.id}',
                child: DramaCover(
                  drama: drama,
                  repository: repository,
                  radius: 14,
                  showEpisodeCount: badge == null || badge!.isEmpty,
                ),
              ),
              if (badge != null && badge!.isNotEmpty)
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.blackWithAlpha(0.72),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Text(
                        [
                          badge!,
                          if (drama.episodes > 0) '共 ${drama.episodes} 集',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 12,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              if (actions != null && selected == null)
                Positioned(top: 2, right: 2, child: actions!),
              if (selected != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: selected!
                        ? Theme.of(context).colorScheme.primary
                        : AppColors.blackWithAlpha(0.64),
                    child: Icon(
                      selected! ? Icons.check_rounded : Icons.circle_outlined,
                      size: 22,
                      color: selected!
                          ? Theme.of(context).colorScheme.onPrimary
                          : AppColors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(
            height: titleHeight(context),
            child: Text(
              drama.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                height: 1.3,
                fontSize: television ? 17 : 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(
            height: subtitleHeight(context),
            child: Text(
              subtitle ?? drama.displayCategory,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: television ? 14 : 12,
                height: 1.3,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
    if (television) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.contextMenu): ?onMore,
        },
        child: RemoteTarget(
          focusNode: focusNode,
          onFocus: onFocus,
          onPressed: onTap,
          selected: selected ?? false,
          label:
              '${drama.title}，${drama.episodes}集${badge == null ? '' : '，$badge'}',
          child: content,
        ),
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: '${drama.title}，${drama.episodes}集',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress ?? onMore,
        onSecondaryTap: onMore,
        borderRadius: BorderRadius.circular(18),
        child: content,
      ),
    );
  }
}

class StatusPanel extends StatelessWidget {
  const StatusPanel({
    super.key,
    required this.title,
    this.message = '',
    this.onRetry,
    this.icon = Icons.movie_filter_outlined,
    this.action = '重试',
    this.secondaryAction,
  });
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;
  final String action;
  final Widget? secondaryAction;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              autofocus: AppLayout.isTelevision(context),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(action),
            ),
          ],
          if (secondaryAction != null) ...[
            const SizedBox(height: 8),
            secondaryAction!,
          ],
        ],
      ),
    ),
  );
}

SliverGridDelegate dramaGridDelegate(BuildContext context, double width) {
  final columns = width < 600 ? 3 : (width / 180).floor().clamp(4, 9);
  final spacing = width < 600 ? 10.0 : 18.0;
  final tileWidth = (width - (columns - 1) * spacing) / columns;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: 22,
    crossAxisSpacing: spacing,
    mainAxisExtent: DramaTile.extentFor(context, tileWidth),
  );
}

String formatPosition(double seconds) {
  final value = seconds.isFinite ? seconds.toInt().clamp(0, 999999) : 0;
  return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
}
