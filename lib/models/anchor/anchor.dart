import 'dart:convert';

List<Map<String, dynamic>> readJsonList(String? value) {
  try {
    return (jsonDecode(value ?? '[]') as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  } catch (_) {
    return [];
  }
}

class Anchor {
  const Anchor({
    required this.id,
    required this.name,
    this.avatar = '',
    this.bio = '',
    this.fansCount,
    this.dramasCount,
    this.isFollowed = false,
    this.officialFollowing,
    this.canFollow = false,
    this.relativeType = 2,
  });

  final String id, name, avatar, bio;
  final int? fansCount, dramasCount;
  final bool isFollowed;
  final bool? officialFollowing;
  final bool canFollow;
  final int relativeType;

  Anchor copyWith({
    String? id,
    String? name,
    String? avatar,
    String? bio,
    int? fansCount,
    int? dramasCount,
    bool? isFollowed,
    bool? officialFollowing,
    bool? canFollow,
    int? relativeType,
  }) => Anchor(
    id: id ?? this.id,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    bio: bio ?? this.bio,
    fansCount: fansCount ?? this.fansCount,
    dramasCount: dramasCount ?? this.dramasCount,
    isFollowed: isFollowed ?? this.isFollowed,
    officialFollowing: officialFollowing ?? this.officialFollowing,
    canFollow: canFollow ?? this.canFollow,
    relativeType: relativeType ?? this.relativeType,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'bio': bio,
    'fansCount': fansCount,
    'dramasCount': dramasCount,
    'isFollowed': isFollowed,
  };

  factory Anchor.fromJson(Map<String, dynamic> row) => Anchor(
    id: row['id'] as String? ?? '',
    name: row['name'] as String? ?? '',
    avatar: row['avatar'] as String? ?? '',
    bio: row['bio'] as String? ?? '',
    fansCount: (row['fansCount'] as num?)?.toInt(),
    dramasCount: (row['dramasCount'] as num?)?.toInt(),
    isFollowed: row['isFollowed'] == true,
  );

  factory Anchor.fromOfficial(Map<String, dynamic> row) => Anchor(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    avatar: row['avatar'] as String? ?? '',
    bio: row['description'] as String? ?? '',
    dramasCount: (row['worksCount'] as num?)?.toInt(),
    officialFollowing: row['following'] as bool?,
    isFollowed: row['following'] == true,
    canFollow: row['canFollow'] == true,
    relativeType: (row['relativeType'] as num?)?.toInt() ?? 2,
  );
}
