import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:THLRedLook/core/download/download_active_task.dart';
import 'package:THLRedLook/core/download/download_job_executor.dart';
import 'package:THLRedLook/core/download/download_storage_migrator.dart';
import 'package:THLRedLook/core/storage/app_storage.dart';

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  String _directory = '';
  String get directory => _directory;
  File get _jobsFile => File(p.join(_directory, 'jobs.json'));

  final Map<String, Map<String, dynamic>> _jobs = {};
  final Map<String, DownloadActiveTask> _activeTasks = {};
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

    final httpClient = http.Client();
    final activeTask = DownloadActiveTask(httpClient);
    _activeTasks[jobId] = activeTask;

    try {
      await DownloadJobExecutor.execute(
        jobId: jobId,
        job: job,
        directory: _directory,
        activeTask: activeTask,
        resolvePlayback: _resolvePlayback,
        onSave: _saveJobs,
      );
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

    await DownloadStorageMigrator.moveDirectoryContents(_directory, targetDir);

    _directory = targetDir;
    await _loadJobs();
  }

  String _cleanDramaDir(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }
}
