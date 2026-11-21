import 'package:THLRedLook/models/drama/drama.dart';
import 'package:THLRedLook/models/drama/episode.dart';

class DramaDetail {
  DramaDetail(this.drama, this.episodes, {this.warning = ''});

  final Drama drama;
  final List<Episode> episodes;
  final String warning;

  Map<String, dynamic> toJson() => {
    'drama': drama.toJson(),
    'chapters': [for (final ep in episodes) ep.raw],
    'warning': warning,
  };

  factory DramaDetail.fromJson(Map<String, dynamic> json) {
    final rows = json['chapters'] as List? ?? const [];
    return DramaDetail(
      Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
      [
        for (var i = 0; i < rows.length; i++)
          Episode(Map<String, dynamic>.from(rows[i] as Map), i + 1),
      ],
      warning: json['warning'] as String? ?? '',
    );
  }
}

class SeriesSeason {
  const SeriesSeason({
    required this.drama,
    required this.season,
    required this.playable,
    this.status = '',
  });

  final Drama drama;
  final int season;
  final bool playable;
  final String status;

  factory SeriesSeason.fromJson(Map<String, dynamic> json) => SeriesSeason(
    drama: Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
    season: (json['season'] as num).toInt(),
    playable: json['playable'] == true,
    status: json['status'] as String? ?? '',
  );
}
