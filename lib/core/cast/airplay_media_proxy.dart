import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/player/ios_encrypted_stream.dart';

class LanMediaFileProxy {
  HttpServer? _server;
  String? _token;
  File? _file;
  int _length = 0;
  bool _closed = false;

  Future<String> open(String filePath) async {
    final uri = Uri.tryParse(filePath);
    final actualPath = uri?.scheme == 'file' ? uri!.toFilePath() : filePath;
    final file = File(actualPath);
    if (!await file.exists()) {
      throw AppFailure('本地视频文件不存在，无法推送投屏');
    }
    final lanIp = await IosEncryptedStream.findLanIpv4();
    if (lanIp == null || lanIp.isEmpty) {
      throw AppFailure('未检测到局域网 Wi-Fi IP，请连接无线网络后重试');
    }
    _length = await file.length();
    _file = file;
    final rng = Random.secure();
    _token = List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      throw AppFailure('本地投屏代理已关闭');
    }
    _server = server;
    server.autoCompress = false;
    server.listen((req) => unawaited(_handle(req)), onError: (Object _) {});
    return 'http://$lanIp:${server.port}/$_token/media.mp4';
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final token = _token;
      final file = _file;
      if (_closed ||
          token == null ||
          file == null ||
          request.uri.path != '/$token/media.mp4') {
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
        if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$_length');
          await response.close();
          return;
        }
        if (match[1]!.isEmpty) {
          final suffix = int.tryParse(match[2]!) ?? 0;
          start = max(0, _length - suffix);
        } else {
          start = int.tryParse(match[1]!) ?? _length;
          end = match[2]!.isEmpty ? end : min(end, int.tryParse(match[2]!) ?? -1);
        }
        if (start < 0 || start >= _length || end < start) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$_length');
          await response.close();
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
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      await file.openRead(start, end + 1).pipe(response);
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    _closed = true;
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }
}
