import 'package:path/path.dart' as path;

import 'package:THLRedLook/models/catalog/models.dart';

/// 本地合并/已下载媒体记录模型
class LocalMediaItem {
  LocalMediaItem({
    required this.id,
    required this.drama,
    required this.file,
    required this.kind,
    required this.episodes,
    required this.duration,
    required this.bytes,
    required this.created,
    this.videoTranscodes = 0,
    this.audioTranscodes = 0,
    this.jobId = '',
    this.sourceVersion = '',
    this.decodeVerified = false,
    this.specialNumber = 0,
  });

  final String id, file, kind, jobId, sourceVersion;
  final bool decodeVerified;
  final int specialNumber;
  bool get special => kind == 'special';
  final Drama drama;
  final List<int> episodes;
  final double duration;
  final int bytes, videoTranscodes, audioTranscodes;
  final DateTime created;
  bool get merged => kind == 'merged';

  Map<String, dynamic> toJson() => {
    'id': id,
    'drama': drama.toJson(),
    'file': file,
    'kind': kind,
    'episodes': episodes,
    'duration': duration,
    'bytes': bytes,
    'created': created.toIso8601String(),
    'videoTranscodes': videoTranscodes,
    'audioTranscodes': audioTranscodes,
    'jobId': jobId,
    'sourceVersion': sourceVersion,
    'decodeVerified': decodeVerified,
    'specialNumber': specialNumber,
  };

  factory LocalMediaItem.fromJson(Map<String, dynamic> value) {
    final file = value['file'] as String;
    if (path.isAbsolute(file) || file.split(RegExp(r'[/\\]')).contains('..')) {
      throw const FormatException('媒体路径无效');
    }
    return LocalMediaItem(
      id: value['id'] as String,
      drama: Drama.fromJson(Map<String, dynamic>.from(value['drama'] as Map)),
      file: file,
      kind: value['kind'] as String,
      episodes: (value['episodes'] as List).map(intValue).toList(),
      duration: (value['duration'] as num).toDouble(),
      bytes: intValue(value['bytes']),
      created: DateTime.parse(value['created'] as String),
      videoTranscodes: intValue(value['videoTranscodes']),
      audioTranscodes: intValue(value['audioTranscodes']),
      jobId: value['jobId'] as String? ?? '',
      sourceVersion: value['sourceVersion'] as String? ?? '',
      decodeVerified: value['decodeVerified'] == true,
      specialNumber: intValue(value['specialNumber']),
    );
  }
}
