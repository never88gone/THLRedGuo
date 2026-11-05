class HongguoEpisodeLike {
  const HongguoEpisodeLike(this.id, this.number, this.liked, this.count);
  final String id;
  final int number;
  final bool liked;
  final int count;
  factory HongguoEpisodeLike.fromJson(Map<String, dynamic> row) =>
      HongguoEpisodeLike(
        row['id'] as String,
        (row['number'] as num).toInt(),
        row['liked'] as bool,
        (row['count'] as num).toInt(),
      );
}

class HongguoCreator {
  const HongguoCreator(
    this.id,
    this.name,
    this.relativeType,
    this.following,
    this.canFollow,
  );
  final String id, name;
  final int relativeType;
  final bool? following;
  final bool canFollow;
  factory HongguoCreator.fromJson(Map<String, dynamic> row) => HongguoCreator(
    row['id'] as String,
    row['name'] as String,
    (row['relativeType'] as num).toInt(),
    row['following'] as bool?,
    row['canFollow'] == true,
  );
}

class HongguoSocialSnapshot {
  const HongguoSocialSnapshot(
    this.episodes,
    this.creators, {
    this.creatorError,
  });
  final List<HongguoEpisodeLike> episodes;
  final List<HongguoCreator> creators;
  final String? creatorError;
  HongguoEpisodeLike? episode(int number) =>
      episodes.where((value) => value.number == number).firstOrNull;
}
