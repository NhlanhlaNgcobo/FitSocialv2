class FirestoreUserRecord {
  const FirestoreUserRecord({
    required this.id,
    required this.displayName,
    required this.handle,
    required this.bio,
    required this.location,
    required this.avatarUrl,
    required this.followersCount,
    required this.followingCount,
    required this.postsCount,
    required this.workoutsCount,
    required this.mealsCount,
  });

  final String id;
  final String displayName;
  final String handle;
  final String bio;
  final String location;
  final String? avatarUrl;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final int workoutsCount;
  final int mealsCount;

  factory FirestoreUserRecord.fromMap(String id, Map<String, dynamic> data) {
    return FirestoreUserRecord(
      id: id,
      displayName: (data['displayName'] as String?) ?? 'FitSocial User',
      handle: (data['handle'] as String?) ?? '@fitsocial',
      bio: (data['bio'] as String?) ?? '',
      location: (data['location'] as String?) ?? '',
      avatarUrl: data['avatarUrl'] as String?,
      followersCount: (data['followersCount'] as num?)?.toInt() ?? 0,
      followingCount: (data['followingCount'] as num?)?.toInt() ?? 0,
      postsCount: (data['postsCount'] as num?)?.toInt() ?? 0,
      workoutsCount: (data['workoutsCount'] as num?)?.toInt() ?? 0,
      mealsCount: (data['mealsCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class FirestorePostRecord {
  const FirestorePostRecord({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.activity,
    required this.caption,
    required this.metricLabels,
    required this.likesCount,
    required this.commentsCount,
    required this.timestampLabel,
    required this.themeKey,
    required this.likedBy,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String activity;
  final String caption;
  final List<String> metricLabels;
  final int likesCount;
  final int commentsCount;
  final String timestampLabel;
  final String themeKey;
  final List<String> likedBy;

  factory FirestorePostRecord.fromMap(String id, Map<String, dynamic> data) {
    final metrics = (data['metricLabels'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();

    final likedByList = (data['likedBy'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();

    return FirestorePostRecord(
      id: id,
      authorId: (data['authorId'] as String?) ?? '',
      authorName: (data['authorName'] as String?) ?? 'FitSocial User',
      activity: (data['activity'] as String?) ?? 'Activity',
      caption: (data['caption'] as String?) ?? '',
      metricLabels: metrics,
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
      timestampLabel: (data['timestampLabel'] as String?) ?? 'now',
      themeKey: (data['themeKey'] as String?) ?? 'sunset',
      likedBy: likedByList,
    );
  }
}

class FirestoreProgressRecord {
  const FirestoreProgressRecord({
    required this.label,
    required this.value,
    required this.delta,
    required this.chartBars,
  });

  final String label;
  final String value;
  final String delta;
  final List<double> chartBars;

  factory FirestoreProgressRecord.fromMap(Map<String, dynamic> data) {
    final bars = (data['chartBars'] as List<dynamic>? ?? const [])
        .map((item) => (item as num).toDouble())
        .toList();

    return FirestoreProgressRecord(
      label: (data['label'] as String?) ?? 'Metric',
      value: (data['value'] as String?) ?? '0',
      delta: (data['delta'] as String?) ?? '',
      chartBars: bars,
    );
  }
}

class FirestoreCommentRecord {
  const FirestoreCommentRecord({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  factory FirestoreCommentRecord.fromMap(String id, Map<String, dynamic> data) {
    DateTime? timestamp;
    final raw = data['createdAt'];
    if (raw != null) {
      // cloud_firestore Timestamp
      timestamp = (raw as dynamic).toDate() as DateTime;
    }

    return FirestoreCommentRecord(
      id: id,
      authorId: (data['authorId'] as String?) ?? '',
      authorName: (data['authorName'] as String?) ?? 'FitSocial User',
      text: (data['text'] as String?) ?? '',
      createdAt: timestamp,
    );
  }
}
