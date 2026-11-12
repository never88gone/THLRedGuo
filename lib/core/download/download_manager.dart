import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:THLRedLook/core/storage/app_storage.dart';

class _ActiveTask {
  _ActiveTask(this.client);
  final http.Client client;
  bool isCancelled = false;
  IOSink? sink;

  void cancel() {
    isCancelled = true;
    try {
      sink?.close();
    } catch (_) {}
    client.close();
  }
}

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  String _directory = '';
  String get directory => _directory;
  File get _jobsFile => File(p.join(_directory, 'jobs.json'));

  final Map<String, Map<String, dynamic>> _jobs = {};
  final Map<String, _ActiveTask> _activeTasks = {};
  final Set<String> _runningJobIds = {};

  Future<Map<String, dynamic>> Function(Map<String, dynamic> input)?
  _resolvePlayback;
  bool _isSaving = false;
  bool _hasPendingSave = false;
  bool _initialized = false;

  static const int maxConcurrentDownloads = 2;

  Future<void> init(
    String directory, {
    required Future<Map<String, dynamic>> Function(Map<String, dynamic> input)
    resolvePlayback,
  }) async {
    _resolvePlayback = resolvePlayback;
    if (_directory == directory && _initialized) {
      return;
    }
    _initialized = true;
    for (final task in _activeTasks.values) {
      task.cancel();
    }
    _activeTasks.clear();
    _runningJobIds.clear();

    _directory = directory;
    await Directory(_directory).create(recursive: true);
    await _loadJobs();
  }

  Future<void> _loadJobs() async {
    _jobs.clear();
    if (!await _jobsFile.exists()) return;
    try {
      final content = await _jobsFile.readAsString();
      if (content.trim().isEmpty) return;
      final list = jsonDecode(content);
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final id = map['id']?.toString() ?? '';
            if (id.isNotEmpty) {
              if (map['state'] == 'downloading') {
                map['state'] = 'queued';
              }
              _jobs[id] = map;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveJobs() async {
    if (_isSaving) {
      _hasPendingSave = true;
      return;
    }
    _isSaving = true;
    try {
      do {
        _hasPendingSave = false;
        final list = _jobs.values.toList();
        final content = jsonEncode(list);
        final tmpFile = File(p.join(_directory, 'jobs.json.tmp'));
        await tmpFile.writeAsString(content, flush: true);
        if (await _jobsFile.exists()) {
          await _jobsFile.delete();
        }
        await tmpFile.rename(_jobsFile.path);
      } while (_hasPendingSave);
    } catch (_) {
    } finally {
      _isSaving = false;
    }
  }

  List<Map<String, dynamic>> getJobs() {
    return _jobs.values.map((job) => Map<String, dynamic>.from(job)).toList();
  }

  Future<int> enqueue({
    required Map<String, dynamic> drama,
    required List<Map<String, dynamic>> entries,
    int quality = 0,
    bool force = false,
  }) async {
    final dramaId = drama['id']?.toString() ?? 'drama';
    final cleanId = _cleanDramaDir(dramaId);
    final dramaDir = Directory(p.join(_directory, cleanId));
    await dramaDir.create(recursive: true);

    var added = 0;
    for (final entry in entries) {
      final chapter = entry['chapter'] is Map
          ? Map<String, dynamic>.from(entry['chapter'] as Map)
          : <String, dynamic>{};
      final index = (entry['index'] as num?)?.toInt() ?? 1;
      final jobId = '${dramaId}_$index';

      final mp4File = File(p.join(dramaDir.path, 'ep_$index.mp4'));
      final existsCompleted =
          await mp4File.exists() && await mp4File.length() > 0;

      final existing = _jobs[jobId];
      if (existing != null && !force) {
        continue;
      }

      if (existsCompleted && !force) {
        _jobs[jobId] = {
          'id': jobId,
          'drama': drama,
          'chapter': chapter,
          'index': index,
          'state': 'completed',
          'bytes': await mp4File.length(),
          'total': await mp4File.length(),
          'progress': 1.0,
          'quality': quality,
          'actualQuality': quality,
          'error': '',
          'created': DateTime.now().millisecondsSinceEpoch,
          'revision': 1,
          'archived': false,
        };
        continue;
      }

      _jobs[jobId] = {
        'id': jobId,
        'drama': drama,
        'chapter': chapter,
        'index': index,
        'state': 'queued',
        'bytes': 0,
        'total': 0,
        'progress': 0.0,
        'quality': quality,
        'actualQuality': quality,
        'error': '',
        'created': DateTime.now().millisecondsSinceEpoch,
        'revision': ((existing?['revision'] as num?)?.toInt() ?? 0) + 1,
        'archived': false,
      };
      added++;
    }

    await _saveJobs();
    _schedule();
    return added;
  }

  void _schedule() {
    if (_runningJobIds.length >= maxConcurrentDownloads) return;

    final queued = _jobs.values
        .where(
          (job) =>
              job['state'] == 'queued' && !_runningJobIds.contains(job['id']),
        )
        .toList();
    if (queued.isEmpty) return;

    queued.sort((a, b) {
      final aCreated = (a['created'] as num?)?.toInt() ?? 0;
      final bCreated = (b['created'] as num?)?.toInt() ?? 0;
      return aCreated.compareTo(bCreated);
    });

    final availableSlots = maxConcurrentDownloads - _runningJobIds.length;
    for (var i = 0; i < availableSlots && i < queued.length; i++) {
      final job = queued[i];
      final jobId = job['id'] as String;
      _runningJobIds.add(jobId);
      _executeJob(jobId);
    }
  }

  Future<void> _executeJob(String jobId) async {
    final job = _jobs[jobId];
    if (job == null || job['state'] != 'queued') {
      _runningJobIds.remove(jobId);
      _schedule();
      return;
    }

    job['state'] = 'downloading';
    job['error'] = '';
    job['revision'] = ((job['revision'] as num?)?.toInt() ?? 0) + 1;
    await _saveJobs();

    final drama = Map<String, dynamic>.from(job['drama'] as Map? ?? {});
    final dramaId = drama['id']?.toString() ?? 'drama';
    final cleanId = _cleanDramaDir(dramaId);
    final dramaDir = Directory(p.join(_directory, cleanId));
    await dramaDir.create(recursive: true);

    final index = (job['index'] as num?)?.toInt() ?? 1;
    final mp4File = File(p.join(dramaDir.path, 'ep_$index.mp4'));
    final partFile = File(p.join(dramaDir.path, 'ep_$index.mp4.part'));

    final httpClient = http.Client();
    final activeTask = _ActiveTask(httpClient);
    _activeTasks[jobId] = activeTask;

    try {
      if (await mp4File.exists() && await mp4File.length() > 0) {
        final length = await mp4File.length();
        job['state'] = 'completed';
        job['bytes'] = length;
        job['total'] = length;
        job['progress'] = 1.0;
        job['revision'] = ((job['revision'] as num?)?.toInt() ?? 0) + 1;
        await _saveJobs();
        return;
      }

      if (_resolvePlayback == null) {
        throw StateError('流媒体解析引擎未就绪');
      }

      final resolved = await _resolvePlayback!({
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

      final streamedResponse = await httpClient.send(request);
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
          _saveJobs();
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
      await _saveJobs();
    } catch (e) {
      if (!activeTask.isCancelled) {
        job['state'] = 'failed';
        job['error'] = e.toString();
        job['revision'] = ((job['revision'] as num?)?.toInt() ?? 0) + 1;
        await _saveJobs();
      }
    } finally {
      activeTask.cancel();
      _activeTasks.remove(jobId);
      _runningJobIds.remove(jobId);
      _schedule();
    }
  }

  Future<void> control(String command, {String jobId = ''}) async {
    if (command == 'pauseAll') {
      final activeIds = _jobs.values
          .where((j) => j['state'] != 'completed')
          .map((j) => j['id'] as String)
          .toList();
      for (final id in activeIds) {
        await _pauseJob(id);
      }
      await _saveJobs();
      return;
    }

    if (command == 'resumeAll') {
      final resumable = _jobs.values
          .where((j) => j['state'] == 'paused' || j['state'] == 'failed')
          .toList();
      for (final job in resumable) {
        job['state'] = 'queued';
        job['error'] = '';
        job['revision'] = ((job['revision'] as num?)?.toInt() ?? 0) + 1;
      }
      await _saveJobs();
      _schedule();
      return;
    }

    if (jobId.isEmpty) return;

    if (command == 'pause') {
      await _pauseJob(jobId);
      await _saveJobs();
    } else if (command == 'resume') {
      final job = _jobs[jobId];
      if (job != null &&
          (job['state'] == 'paused' || job['state'] == 'failed')) {
        job['state'] = 'queued';
        job['error'] = '';
        job['revision'] = ((job['revision'] as num?)?.toInt() ?? 0) + 1;
        await _saveJobs();
        _schedule();
      }
    } else if (command == 'remove') {
      await _removeJob(jobId);
      await _saveJobs();
    }
  }

  Future<void> _pauseJob(String jobId) async {
    final active = _activeTasks[jobId];
    if (active != null) {
      active.cancel();
      _activeTasks.remove(jobId);
    }
    _runningJobIds.remove(jobId);
    final job = _jobs[jobId];
    if (job != null && job['state'] != 'completed') {
      job['state'] = 'paused';
      job['revision'] = ((job['revision'] as num?)?.toInt() ?? 0) + 1;
    }
  }

  Future<void> _removeJob(String jobId) async {
    final active = _activeTasks[jobId];
    if (active != null) {
      active.cancel();
      _activeTasks.remove(jobId);
    }
    _runningJobIds.remove(jobId);
    final job = _jobs.remove(jobId);
    if (job != null) {
      final drama = job['drama'] as Map? ?? {};
      final dramaId = drama['id']?.toString() ?? 'drama';
      final cleanId = _cleanDramaDir(dramaId);
      final index = job['index'] ?? 1;
      final mp4File = File(p.join(_directory, cleanId, 'ep_$index.mp4'));
      final partFile = File(p.join(_directory, cleanId, 'ep_$index.mp4.part'));
      try {
        if (await mp4File.exists()) await mp4File.delete();
        if (await partFile.exists()) await partFile.delete();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> controlBatch(
    String command,
    List<String> jobIds,
  ) async {
    final completed = <String>[];
    final failures = <String, String>{};

    for (final id in jobIds.toSet()) {
      try {
        if (command == 'pause') {
          await _pauseJob(id);
          completed.add(id);
        } else if (command == 'resume') {
          final job = _jobs[id];
          if (job != null) {
            job['state'] = 'queued';
            job['error'] = '';
            job['revision'] = ((job['revision'] as num?)?.toInt() ?? 0) + 1;
            completed.add(id);
          } else {
            failures[id] = '任务不存在';
          }
        } else if (command == 'remove') {
          await _removeJob(id);
          completed.add(id);
        }
      } catch (e) {
        failures[id] = e.toString();
      }
    }

    await _saveJobs();
    if (command == 'resume') {
      _schedule();
    }

    return {'completed': completed, 'failures': failures};
  }

  Future<Map<String, dynamic>> localPlayback(
    Map<String, dynamic> drama,
    int index,
  ) async {
    final dramaId = drama['id']?.toString() ?? '';
    final cleanId = _cleanDramaDir(dramaId);
    final filePath = p.join(_directory, cleanId, 'ep_$index.mp4');
    final file = File(filePath);

    if (await file.exists() && await file.length() > 0) {
      final jobId = '${dramaId}_$index';
      final job = _jobs[jobId];
      return {
        'url': file.uri.toString(),
        'local': true,
        'mimeType': 'video/mp4',
        'mediaBytes': await file.length(),
        if (job?['decryptionKey'] != null &&
            (job!['decryptionKey'] as String).isNotEmpty)
          'decryptionKey': job['decryptionKey'],
      };
    }

    return {'url': ''};
  }

  Future<Map<String, dynamic>> storage() async {
    await Directory(_directory).create(recursive: true);
    return {
      'directory': _directory,
      'usedBytes': await directoryBytes(Directory(_directory)),
      'freeBytes': availableDiskBytes(_directory),
    };
  }

  Future<void> moveDownloads(String targetDir) async {
    if (targetDir.trim().isEmpty || targetDir == _directory) return;
    await control('pauseAll');

    final newDir = Directory(targetDir);
    await newDir.create(recursive: true);

    final currentDir = Directory(_directory);
    if (await currentDir.exists()) {
      await for (final entity in currentDir.list(recursive: false)) {
        final dest = p.join(targetDir, p.basename(entity.path));
        if (entity is File) {
          await entity.copy(dest);
          await entity.delete();
        } else if (entity is Directory) {
          final targetSubDir = Directory(dest);
          await targetSubDir.create(recursive: true);
          await for (final subEntity in entity.list(recursive: false)) {
            if (subEntity is File) {
              await subEntity.copy(
                p.join(targetSubDir.path, p.basename(subEntity.path)),
              );
              await subEntity.delete();
            }
          }
          await entity.delete(recursive: true);
        }
      }
    }

    _directory = targetDir;
    await _loadJobs();
  }

  String _cleanDramaDir(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }
}
