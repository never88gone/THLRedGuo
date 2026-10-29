import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/media/cover_decoder.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 短剧海报毛玻璃托底背景组件，突出剧目图片质感并提供沉浸式环境光晕
class DramaBackdrop extends StatelessWidget {
  const DramaBackdrop({
    super.key,
    required this.drama,
    required this.repository,
    this.sigma = 28.0,
    this.dimColor,
    this.gradient,
    this.fadeBottom = false,
    this.child,
  });

  final Drama drama;
  final AppRepository repository;
  final double sigma;
  final Color? dimColor;
  final Gradient? gradient;
  final bool fadeBottom;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fallbackColor = isDark
        ? const Color(0xFF131419)
        : const Color(0xFFF1F3F5);

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        if (!DramaCover.imagesDisabled && drama.cover.isNotEmpty)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.mirror,
              ),
              child: Transform.scale(
                scale: 1.18,
                child: CachedCoverImage(
                  key: ValueKey(
                    'backdrop-${drama.cleanSourceId.isNotEmpty ? drama.cleanSourceId : drama.id}',
                  ),
                  drama: drama,
                  repository: repository,
                  placeholder: Container(color: fallbackColor),
                ),
              ),
            ),
          )
        else
          Container(color: fallbackColor),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  dimColor ??
                  (isDark
                      ? Colors.black.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.60)),
              gradient: gradient,
            ),
          ),
        ),
        if (child != null) Positioned.fill(child: child!),
      ],
    );

    if (fadeBottom) {
      content = ShaderMask(
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Colors.black,
              Color(0xCC000000),
              Color(0x4D000000),
              Colors.transparent,
            ],
            stops: [0.0, 0.40, 0.68, 0.88, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: content,
      );
    }

    return content;
  }
}

class DramaCover extends StatelessWidget {
  const DramaCover({
    super.key,
    required this.drama,
    required this.repository,
    this.radius = 14,
    this.showEpisodeCount = true,
  });

  final Drama drama;
  final AppRepository repository;
  final double radius;
  final bool showEpisodeCount;

  static const imagesDisabled = bool.fromEnvironment('DISABLE_REMOTE_IMAGES');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerHighest, colors.surfaceContainer],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 40,
          color: colors.onSurfaceVariant,
        ),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.25),
            width: 0.8,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3D000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              placeholder,
              if (!imagesDisabled && drama.id.isNotEmpty)
                CachedCoverImage(
                  key: ValueKey(
                    'drama-cover-${drama.cleanSourceId.isNotEmpty ? drama.cleanSourceId : drama.id}',
                  ),
                  drama: drama,
                  repository: repository,
                  placeholder: placeholder,
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.posterOverlay,
                    ),
                  ),
                ),
              ),
              if (showEpisodeCount && drama.episodes > 0)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x99000000),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0x26FFFFFF),
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      '共 ${drama.episodes} 集',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              if (drama.vip)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppGradients.gold,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66FFC028),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'VIP',
                      style: TextStyle(
                        color: AppColors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CachedCoverImage extends StatefulWidget {
  const CachedCoverImage({
    super.key,
    required this.drama,
    required this.repository,
    required this.placeholder,
  });

  final Drama drama;
  final AppRepository repository;
  final Widget placeholder;

  @override
  State<CachedCoverImage> createState() => _CachedCoverImageState();
}

class _CachedCoverImageState extends State<CachedCoverImage> {
  late Future<String> _file;
  int _coverRevision = 0;
  bool _coverFailed = false;
  bool _retryOnFailure = false;
  bool _retryQueued = false;
  String? _failedPath;
  String? _resolvedPath;

  @override
  void initState() {
    super.initState();
    _coverRevision = widget.repository.catalogUpdates.coverRevision(
      widget.drama.id,
    );
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    _loadFile(widget.drama);
  }

  void _loadFile(Drama drama, {bool force = false}) {
    final future = widget.repository.cover(drama, force: force);
    _file = future;
    future
        .then((path) {
          if (!mounted || _file != future) return;
          if (path.isNotEmpty && _resolvedPath != path) {
            setState(() {
              _resolvedPath = path;
              _coverFailed = false;
            });
          }
        })
        .catchError((_) {
          if (!mounted || _file != future) return;
          if (_resolvedPath == null) {
            setState(() => _coverFailed = true);
          }
        });
  }

  @override
  void didUpdateWidget(covariant CachedCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.catalogUpdates.removeListener(_metadataChanged);
      widget.repository.catalogUpdates.addListener(_metadataChanged);
    }
    if (oldWidget.repository != widget.repository ||
        oldWidget.drama.id != widget.drama.id ||
        oldWidget.drama.cover != widget.drama.cover ||
        oldWidget.drama.source != widget.drama.source) {
      _coverFailed = _retryOnFailure = false;
      _failedPath = null;
      _coverRevision = widget.repository.catalogUpdates.coverRevision(
        widget.drama.id,
      );
      _loadFile(widget.drama);
    }
  }

  void _metadataChanged() {
    final revision = widget.repository.catalogUpdates.coverRevision(
      widget.drama.id,
    );
    if (revision == _coverRevision) return;
    _coverRevision = revision;
    _retryOnFailure = true;
    if (_coverFailed) _queueRetry();
  }

  void _queueRetry() {
    if (_retryQueued || !_retryOnFailure) return;
    _retryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryQueued = false;
      if (!mounted || !_retryOnFailure) return;
      _retryOnFailure = false;
      _retry(_failedPath);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    super.dispose();
  }

  Future<void> _retry(String? path) async {
    if (path != null) {
      await ResizeImage.resizeIfNeeded(
        440,
        null,
        FileImage(File(path)),
      ).evict();
    }
    if (mounted) {
      setState(() {
        _coverFailed = _retryOnFailure = false;
        _failedPath = null;
      });
      _loadFile(
        widget.repository.catalogUpdates.current(widget.drama),
        force: true,
      );
    }
  }

  Widget _failed(String? path) {
    _coverFailed = true;
    _failedPath = path;
    if (_retryOnFailure) _queueRetry();
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.placeholder,
        Center(
          child: IconButton(
            tooltip: '重试海报',
            onPressed: () => _retry(path),
            icon: Icon(
              Icons.refresh_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _networkFallback() {
    final coverUrl = normalizeCoverUrl(widget.drama.cover.trim());
    if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
      return Image.network(
        coverUrl,
        fit: BoxFit.cover,
        cacheWidth: 440,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: child,
          );
        },
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return widget.placeholder;
        },
        errorBuilder: (_, _, _) => _failed(null),
      );
    }
    return _failed(null);
  }

  Widget _buildImage(String path) {
    final resolved = normalizeCoverUrl(path.trim());
    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      return Image.network(
        resolved,
        fit: BoxFit.cover,
        cacheWidth: 440,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: child,
          );
        },
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return widget.placeholder;
        },
        errorBuilder: (_, _, _) => _failed(null),
      );
    }
    return Image.file(
      File(resolved),
      fit: BoxFit.cover,
      cacheWidth: 440,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      errorBuilder: (_, error, stack) => _networkFallback(),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _file,
    initialData: _resolvedPath,
    builder: (context, snapshot) {
      final path =
          (snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.isNotEmpty)
          ? snapshot.data!
          : _resolvedPath;

      if (path != null && path.isNotEmpty && !_coverFailed) {
        return _buildImage(path);
      }

      if (snapshot.connectionState != ConnectionState.done && !_coverFailed) {
        final coverUrl = widget.drama.cover.trim();
        if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
          return Image.network(
            coverUrl,
            fit: BoxFit.cover,
            cacheWidth: 440,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: child,
              );
            },
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return widget.placeholder;
            },
            errorBuilder: (_, _, _) => widget.placeholder,
          );
        }
        return widget.placeholder;
      }

      return _networkFallback();
    },
  );
}
