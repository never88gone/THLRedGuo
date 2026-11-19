class CommentItem {
  final String id;
  final String text;
  final String userName;
  final String userAvatar;
  final String userId;
  final int createTime;
  final int diggCount;
  final int replyCount;

  const CommentItem({
    required this.id,
    required this.text,
    required this.userName,
    required this.userAvatar,
    required this.userId,
    required this.createTime,
    required this.diggCount,
    required this.replyCount,
  });

  factory CommentItem.fromJson(Map<String, dynamic> json) {
    return CommentItem(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '红果用户',
      userAvatar: json['userAvatar']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      createTime: (json['createTime'] as num?)?.toInt() ?? 0,
      diggCount: (json['diggCount'] as num?)?.toInt() ?? 0,
      replyCount: (json['replyCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CommentPage {
  final int total;
  final bool hasMore;
  final String cursor;
  final List<CommentItem> list;

  const CommentPage({
    required this.total,
    required this.hasMore,
    required this.cursor,
    required this.list,
  });

  factory CommentPage.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'] as List? ?? const [];
    return CommentPage(
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: json['hasMore'] == true,
      cursor: json['cursor']?.toString() ?? '',
      list: rawList
          .map((e) => CommentItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class CommentReplyItem {
  final String id;
  final String text;
  final String userName;
  final String userAvatar;
  final String userId;
  final String replyToUserName;
  final int createTime;
  final int diggCount;

  const CommentReplyItem({
    required this.id,
    required this.text,
    required this.userName,
    required this.userAvatar,
    required this.userId,
    required this.replyToUserName,
    required this.createTime,
    required this.diggCount,
  });

  factory CommentReplyItem.fromJson(Map<String, dynamic> json) {
    return CommentReplyItem(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '红果用户',
      userAvatar: json['userAvatar']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      replyToUserName: json['replyToUserName']?.toString() ?? '',
      createTime: (json['createTime'] as num?)?.toInt() ?? 0,
      diggCount: (json['diggCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CommentReplyPage {
  final int total;
  final bool hasMore;
  final String cursor;
  final List<CommentReplyItem> list;

  const CommentReplyPage({
    required this.total,
    required this.hasMore,
    required this.cursor,
    required this.list,
  });

  factory CommentReplyPage.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'] as List? ?? const [];
    return CommentReplyPage(
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: json['hasMore'] == true,
      cursor: json['cursor']?.toString() ?? '',
      list: rawList
          .map((e) => CommentReplyItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
