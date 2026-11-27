class HawCastDevice {
  const HawCastDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.model = 'THLPlay',
    this.caps = const ['aes128', 'hls', 'mp4'],
    this.manual = false,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String model;
  final List<String> caps;
  final bool manual;

  String get address => '$host:$port';

  String get baseUrl {
    final formattedHost = host.contains(':') ? '[$host]' : host;
    return 'http://$formattedHost:$port';
  }

  bool get supportsEncrypted => caps.contains('aes128');

  HawCastDevice copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? model,
    List<String>? caps,
    bool? manual,
  }) => HawCastDevice(
    id: id ?? this.id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    model: model ?? this.model,
    caps: caps ?? this.caps,
    manual: manual ?? this.manual,
  );
}

class HawCastPlayRequest {
  const HawCastPlayRequest({
    required this.sessionId,
    required this.mediaId,
    required this.title,
    required this.dramaTitle,
    required this.url,
    this.decryptionKey = '',
    this.decryptionIv = '',
    this.headers = const {},
    this.startPosition = 0.0,
    this.episodeIndex = 0,
    this.totalEpisodes = 1,
  });

  final String sessionId;
  final String mediaId;
  final String title;
  final String dramaTitle;
  final String url;
  final String decryptionKey;
  final String decryptionIv;
  final Map<String, String> headers;
  final double startPosition;
  final int episodeIndex;
  final int totalEpisodes;

  Map<String, dynamic> toJson() => {
    'cmd': 'thl_play',
    'session_id': sessionId,
    'media_id': mediaId,
    'title': title,
    'drama_title': dramaTitle,
    'url': url,
    if (decryptionKey.isNotEmpty) 'decryption_key': decryptionKey,
    if (decryptionIv.isNotEmpty) 'decryption_iv': decryptionIv,
    if (headers.isNotEmpty) 'headers': headers,
    'start_position': startPosition,
    'episode_index': episodeIndex,
    'total_episodes': totalEpisodes,
  };
}

enum HawCastControlCommand {
  play('play'),
  pause('pause'),
  stop('stop'),
  seek('seek'),
  rate('rate'),
  volume('volume'),
  previous('previous'),
  next('next');

  const HawCastControlCommand(this.action);
  final String action;
}

enum HawCastPlayState {
  idle,
  buffering,
  playing,
  paused,
  stopped,
  error;

  static HawCastPlayState fromCode(int code) => switch (code) {
    1 => HawCastPlayState.buffering,
    2 => HawCastPlayState.playing,
    3 => HawCastPlayState.paused,
    4 => HawCastPlayState.stopped,
    5 => HawCastPlayState.error,
    _ => HawCastPlayState.idle,
  };
}

class HawCastStatus {
  const HawCastStatus({
    this.sessionId = '',
    this.mediaId = '',
    this.state = HawCastPlayState.idle,
    this.position = 0.0,
    this.duration = 0.0,
    this.volume = 1.0,
    this.rate = 1.0,
    this.errorCode = 0,
  });

  final String sessionId;
  final String mediaId;
  final HawCastPlayState state;
  final double position;
  final double duration;
  final double volume;
  final double rate;
  final int errorCode;

  factory HawCastStatus.fromJson(Map<String, dynamic> json) {
    double numVal(String key, double fallback) {
      final raw = json[key];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? fallback;
      return fallback;
    }

    int intVal(String key, int fallback) {
      final raw = json[key];
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw) ?? fallback;
      return fallback;
    }

    return HawCastStatus(
      sessionId: json['session_id']?.toString() ?? '',
      mediaId: json['media_id']?.toString() ?? '',
      state: HawCastPlayState.fromCode(intVal('state', 0)),
      position: numVal('position', 0.0),
      duration: numVal('duration', 0.0),
      volume: numVal('volume', 1.0),
      rate: numVal('rate', 1.0),
      errorCode: intVal('error_code', 0),
    );
  }
}
