import 'package:THLRedLook/models/drama/drama.dart';

class Episode {
  Episode(this.raw, int fallback)
    : id = raw['id'] as String? ?? '',
      title = raw['title'] as String? ?? '第$fallback集',
      number = intValue(raw['currentEpisode']) > 0
          ? intValue(raw['currentEpisode'])
          : fallback,
      vip =
          (raw['source'] == 'hongguo' ||
              (raw['id'] as String? ?? '').startsWith('hongguo:') ||
              (raw['url'] as String? ?? '').contains('hongguoduanju.com'))
          ? false
          : raw['vip'] == true;

  final Map<String, dynamic> raw;
  final String id;
  final String title;
  final int number;
  final bool vip;
}
