import '../domain/app_models.dart';

class FirestoreUserRecord {

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
      runsCount: (data['runsCount'] as num?)?.toInt() ?? 0,
    );
  }
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
    this.runsCount = 0,
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
  final int runsCount;
}

class FirestorePostRecord {

  factory FirestorePostRecord.fromMap(String id, Map<String, dynamic> data) {
    final metrics = (data['metricLabels'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();

    final likedByList = (data['likedBy'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();

    // Kept dynamic rather than importing cloud_firestore's Timestamp, matching
    // FirestoreCommentRecord below — this file stays free of plugin types.
    final rawCreatedAt = data['createdAt'];

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
      postType: (data['postType'] as String?) ?? 'text',
      imageUrl: data['imageUrl'] as String?,
      workoutData: (data['workoutData'] as Map<String, dynamic>?),
      routePoints: RoutePoint.listFromFirestore(data['routePoints']),
      authorAvatarUrl: data['authorAvatarUrl'] as String?,
      imageAspectRatio: (data['imageAspectRatio'] as num?)?.toDouble(),
      createdAt:
          rawCreatedAt == null ? null : (rawCreatedAt as dynamic).toDate() as DateTime,
    );
  }
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
    this.postType = 'text',
    this.imageUrl,
    this.workoutData,
    this.routePoints = const [],
    this.authorAvatarUrl,
    this.imageAspectRatio,
    this.createdAt,
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
  final String postType;
  final String? imageUrl;
  final Map<String, dynamic>? workoutData;

  /// GPS route for run posts; empty for everything else.
  final List<RoutePoint> routePoints;

  /// Author's profile photo at the time of posting.
  ///
  /// Denormalised alongside [authorName] so the feed renders from the post
  /// documents it already streams — resolving it per card would mean an extra
  /// user read for every post on screen.
  final String? authorAvatarUrl;

  /// width / height of [imageUrl], recorded at upload so the feed renders the
  /// user's chosen crop rather than forcing a shape.
  final double? imageAspectRatio;

  /// When the post was written, per the server clock.
  ///
  /// This — not [timestampLabel] — is what the feed's "2 hours ago" line is
  /// derived from. The stored label is frozen at write time ("now") and would
  /// otherwise still read "now" a week later. Null for the brief window before
  /// the server timestamp resolves, and on posts written before it was
  /// recorded; [timestampLabel] is the fallback in both cases.
  final DateTime? createdAt;
}

class FirestoreProgressRecord {

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
}

class FirestoreCommentRecord {

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
      authorAvatarUrl: data['authorAvatarUrl'] as String?,
    );
  }
  const FirestoreCommentRecord({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.createdAt,
    this.authorAvatarUrl,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  /// Author's profile photo, denormalised alongside [authorName].
  final String? authorAvatarUrl;
}
