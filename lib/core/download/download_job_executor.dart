import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:THLRedLook/core/download/download_active_task.dart';

/// 负责单个离线分集下载任务的网络请求、断点续传与文件写入执行器
abstract final class DownloadJobExecutor {
  static Future<void> execute({
    required String jobId,
    required Map<String, dynamic> job,
    required String directory,
    required DownloadActiveTask activeTask,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic> input)?
        resolvePlayback,
    required Future<void> Function() onSave,
  }) async {
    final drama = Map<String, dynamic>.from(job['drama'] as Map? ?? {});
    final dramaId = drama['id']?.toString() ?? 'drama';
    final cleanId = dramaId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final dramaDir = Directory(p.join(directory, cleanId));
    await dramaDir.create(recursive: true);

    final index = (job['index'] as num?)?.toInt() ?? 1;
    final mp4File = File(p.join(dramaDir.path, 'ep_$index.mp4'));
    final partFile = File(p.join(dramaDir.path, 'ep_$index.mp4.part'));

    if (await mp4File.exists() && await mp4File.length() > 0) {
      final length = await mp4File.length();
      job['state'] = 'completed';
      job['bytes'] = length;
      job['total'] = length;
      job['progress'] = 1.0;
      job['revision'] = ((job['revision'] as num?)?.toInt() ?? 0) + 1;
      await onSave();
      return;
    }

    if (resolvePlayback == null) {
      throw StateError('流媒体解析引擎未就绪');
    }

    final resolved = await resolvePlayback({
      'action': 'resolve',
      'drama': drama,
      'chapter': job['chapter'],
      'index': index,
      'quality': job['quality'] ?? 0,
    });

    if (activeTask.isCancelled) return;

    final url = resolved['url']?.toString() ?? '';
    if (url.isEmpty) {
      throw StateError('解析下载直链失败');
    }

    final headers = resolved['headers'] as Map? ?? {};
    final decryptionKey = resolved['decryptionKey']?.toString() ?? '';
    if (decryptionKey.isNotEmpty) {
      job['decryptionKey'] = decryptionKey;
    }
    final resolvedQuality = (resolved['quality'] as num?)?.toInt() ?? 0;
    if (resolvedQuality > 0) {
      job['actualQuality'] = resolvedQuality;
    }

    var downloadedBytes = 0;
    if (await partFile.exists()) {
      downloadedBytes = await partFile.length();
    }

    final uri = Uri.parse(url);
    final request = http.Request('GET', uri);
    headers.forEach((k, v) {
      if (k != null && v != null) {
        request.headers[k.toString()] = v.toString();
      }
    });

    if (downloadedBytes > 0) {
      request.headers['Range'] = 'bytes=$downloadedBytes-';
    }

    final streamedResponse = await activeTask.client.send(request);
    if (activeTask.isCancelled) return;

    var totalBytes = job['total'] as int? ?? 0;
    FileMode mode;

    if (streamedResponse.statusCode == 206) {
      final contentLen = streamedResponse.contentLength ?? 0;
      totalBytes = downloadedBytes + contentLen;
      mode = FileMode.append;
    } else if (streamedResponse.statusCode == 200) {
      downloadedBytes = 0;
      totalBytes = streamedResponse.contentLength ?? 0;
      mode = FileMode.write;
    } else if (streamedResponse.statusCode == 416) {
      if (downloadedBytes > 0) {
        totalBytes = downloadedBytes;
        mode = FileMode.append;
      } else {
        throw StateError('服务器返回 HTTP 416 Range Not Satisfiable');
      }
    } else {
      throw StateError('下载请求失败: HTTP ${streamedResponse.statusCode}');
    }

    job['total'] = totalBytes;
    job['bytes'] = downloadedBytes;
    if (totalBytes > 0) {
      job['progress'] = (downloadedBytes / totalBytes).clamp(0.0, 1.0);
    }

    final sink = partFile.openWrite(mode: mode);
    activeTask.sink = sink;

    var lastUpdate = DateTime.now();

    await for (final chunk in streamedResponse.stream) {
      if (activeTask.isCancelled) break;
      sink.add(chunk);
      downloadedBytes += chunk.length;
      job['bytes'] = downloadedBytes;
      if (totalBytes > 0) {
        job['progress'] = (downloadedBytes / totalBytes).clamp(0.0, 1.0);
      }

      final now = DateTime.now();
      if (now.difference(lastUpdate).inMilliseconds >= 500) {
        lastUpdate = now;
        onSave();
      }
    }

    await sink.flush();
    await sink.close();
    activeTask.sink = null;

    if (activeTask.isCancelled) {
      return;
    }

    if (await partFile.exists()) {
      if (await mp4File.exists()) {
        await mp4File.delete();
      }
      await partFile.rename(mp4File.path);
    }

    final finalLength = await mp4File.length();
    job['state'] = 'completed';
    job['bytes'] = finalLength;
    job['total'] = finalLength;
    job['progress'] = 1.0;
    job['error'] = '';
    job['revision'] = ((job['revision'] as num?)?.toInt() ?? 0) + 1;
    await onSave();
  }
}
