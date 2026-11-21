import 'dart:io';

import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/media/cover_decoder.dart';

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
    return _coverFailed ? _failed(null) : widget.placeholder;
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
