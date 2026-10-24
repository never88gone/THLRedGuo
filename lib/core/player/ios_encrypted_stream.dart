import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/models/catalog/models.dart';

class IosEncryptedStream {
  IosEncryptedStream({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('duanju/encrypted_stream');

  final MethodChannel _channel;
  HttpServer? _server;
  String? _id;
  String? _url;
  bool _closed = false;
  Future<void>? _closeFuture;
  int _length = 0;

  String? get url => _url;

  Future<PlaybackPlan> open(PlaybackPlan plan) async {
    if (_closed || _id != null) throw StateError('播放通道已关闭');
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _id = id;
    try {
      final metadata = await _channel.invokeMapMethod<String, dynamic>('open', {
        'id': id,
        'url': plan.url,
        'headers': plan.headers,
        'key': plan.decryptionKey,
      });
      if (_closed) throw AppFailure('已取消播放准备', code: 'cancelled');
      _length = (metadata?['mediaBytes'] as num?)?.toInt() ?? 0;
      if (_length <= 0) throw const FormatException('媒体分段信息无效');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_closed) {
        await server.close(force: true);
        throw AppFailure('已取消播放准备', code: 'cancelled');
      }
      _server = server;
      server.autoCompress = false;
      server.listen(
        (request) => unawaited(_serve(request, id)),
        onError: (Object _) {},
      );
      _url = 'http://127.0.0.1:${server.port}/$id/media.mp4';
      return PlaybackPlan(
        url: _url!,
        mediaBytes: _length,
        quality: plan.quality,
        qualities: plan.qualities,
        session: plan.session,
        danmakuId: plan.danmakuId,
        prefetchedBytes: (metadata?['bytesFetched'] as num?)?.toInt() ?? 0,
        expiresAt: plan.expiresAt,
        routeIndex: plan.routeIndex,
        routeCount: plan.routeCount,
      );
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> _serve(HttpRequest request, String id) async {
    final response = request.response;
    var connected = true;
    unawaited(
      response.done.then<void>(
        (_) => connected = false,
        onError: (Object _) {
          connected = false;
        },
      ),
    );
    try {
      if (_closed ||
          request.uri.path != '/$id/media.mp4' ||
          request.connectionInfo?.remoteAddress.isLoopback != true) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      if (!{'GET', 'HEAD'}.contains(request.method)) {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await response.close();
        return;
      }
      var start = 0;
      var end = _length - 1;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null || match[1]!.isEmpty && match[2]!.isEmpty) {
          await _invalidRange(response);
          return;
        }
        if (match[1]!.isEmpty) {
          final suffix = int.tryParse(match[2]!) ?? 0;
          if (suffix <= 0) {
            await _invalidRange(response);
            return;
          }
          start = max(0, _length - suffix);
        } else {
          start = int.tryParse(match[1]!) ?? _length;
          end = match[2]!.isEmpty
              ? end
              : min(end, int.tryParse(match[2]!) ?? -1);
        }
        if (start < 0 || start >= _length || end < start) {
          await _invalidRange(response);
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$_length',
        );
      }
      response.headers.contentType = ContentType('video', 'mp4');
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.contentLength = end - start + 1;
      response.bufferOutput = false;
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      var cursor = start;
      while (cursor <= end && !_closed && connected) {
        final count = min(256 * 1024, end - cursor + 1);
        final bytes = await _channel.invokeMethod<Uint8List>('read', {
          'id': id,
          'offset': cursor,
          'count': count,
        });
        if (_closed || !connected) break;
        if (bytes == null || bytes.length != count) {
          throw const FormatException('媒体分段数据不完整');
        }
        response.add(bytes);
        await response.flush();
        cursor += bytes.length;
      }
      await response.close();
    } catch (_) {
      try {
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _invalidRange(HttpResponse response) async {
    response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$_length');
    await response.close();
  }

  Future<Map<String, dynamic>> statistics() async {
    if (_closed || _id == null) return {};
    return await _channel.invokeMapMethod<String, dynamic>('stats', {
          'id': _id,
        }) ??
        {};
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    final server = _server;
    _server = null;
    await server?.close(force: true);
    final id = _id;
    if (id != null) {
      try {
        await _channel.invokeMethod<void>('close', {'id': id});
      } catch (_) {}
    }
  }
}
