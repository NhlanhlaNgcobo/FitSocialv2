import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../auth/domain/auth_models.dart';
import '../domain/app_models.dart';
import 'content_repository_contract.dart';
import 'firestore_mappers.dart';
import 'firestore_models.dart';

class FirestoreContentRepository implements ContentRepository {
  FirestoreContentRepository(
    this._firestore, {
    FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;

  @override
  Future<List<FeedPost>> getFeedPosts(UserProfileDraft? profile) async {
    final snapshot = await postsCollection
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();

    return snapshot.docs
        .map((doc) => FirestorePostRecord.fromMap(doc.id, doc.data()))
        .map(FirestoreMapper.toFeedPost)
        .toList();
  }

  @override
  Future<List<FeedPost>> fetchUserPosts(String userId) async {
    final snapshot = await postsCollection
        .where('authorId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(120)
        .get();

    return snapshot.docs
        .map((doc) => FirestorePostRecord.fromMap(doc.id, doc.data()))
        .map(FirestoreMapper.toFeedPost)
        .toList();
  }

  @override
  Future<List<FeedPost>> fetchUserMediaPosts(String userId) async {
    // Firestore requires the first orderBy to match an inequality field, so
    // filtering `imageUrl != null` server-side would force ordering by
    // imageUrl and lose the newest-first ordering. Filtering in Dart keeps the
    // createdAt ordering and costs one query either way.
    final posts = await fetchUserPosts(userId);
    return posts
        .where((post) => post.imageUrl != null && post.imageUrl!.isNotEmpty)
        .toList();
  }

  @override
  Future<List<FeedPost>> fetchTrendingPosts() async {
    final snapshot = await postsCollection
        .orderBy('likesCount', descending: true)
        .limit(30)
        .get();

    return snapshot.docs
        .map((doc) => FirestorePostRecord.fromMap(doc.id, doc.data()))
        .map(FirestoreMapper.toFeedPost)
        .toList();
  }

  DocumentReference<Map<String, dynamic>> _followingRef(
    String currentUserId,
    String targetUserId,
  ) {
    return usersCollection
        .doc(currentUserId)
        .collection('following')
        .doc(targetUserId);
  }

  DocumentReference<Map<String, dynamic>> _followerRef(
    String currentUserId,
    String targetUserId,
  ) {
    return usersCollection
        .doc(targetUserId)
        .collection('followers')
        .doc(currentUserId);
  }

  @override
  Future<void> followUser(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) {
      throw ArgumentError("You can't follow your own profile.");
    }

    final followingRef = _followingRef(currentUserId, targetUserId);

    // Bail if the edge is already there — a double tap would otherwise
    // increment the counters twice for a single relationship.
    final existing = await followingRef.get();
    if (existing.exists) return;

    final batch = _firestore.batch();
    batch.set(followingRef, {
      'userId': targetUserId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_followerRef(currentUserId, targetUserId), {
      'userId': currentUserId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      usersCollection.doc(currentUserId),
      {'followingCount': FieldValue.increment(1)},
      SetOptions(merge: true),
    );
    // followersCount must be the ONLY key written to someone else's profile:
    // the security rule permits a ±1 change to that single field and nothing
    // more, so adding e.g. updatedAt here would make the write fail.
    batch.set(
      usersCollection.doc(targetUserId),
      {'followersCount': FieldValue.increment(1)},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  @override
  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) return;

    final followingRef = _followingRef(currentUserId, targetUserId);

    final existing = await followingRef.get();
    if (!existing.exists) return;

    final batch = _firestore.batch();
    batch.delete(followingRef);
    batch.delete(_followerRef(currentUserId, targetUserId));
    batch.set(
      usersCollection.doc(currentUserId),
      {'followingCount': FieldValue.increment(-1)},
      SetOptions(merge: true),
    );
    batch.set(
      usersCollection.doc(targetUserId),
      {'followersCount': FieldValue.increment(-1)},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  @override
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId) {
    return _followingRef(currentUserId, targetUserId)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  @override
  Future<List<UserSearchResult>> searchUsers(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];

    // Firestore has no case-insensitive or OR-across-fields search, so this
    // runs prefix ranges per field and merges. Display names are almost always
    // capitalised, so a capitalised variant is probed alongside the raw term
    // to make lowercase typing ("bear") match "Bear".
    final variants = <String>{term, _capitalize(term)};

    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (final variant in variants) {
      futures
        ..add(_prefixQuery('displayName', variant))
        ..add(_prefixQuery('handle', variant))
        // Handles are conventionally lowercase and '@'-prefixed.
        ..add(_prefixQuery('handle', '@${variant.toLowerCase()}'));
    }

    final snapshots = await Future.wait(futures);

    final byId = <String, UserSearchResult>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        byId.putIfAbsent(
          doc.id,
          () => FirestoreMapper.toUserSearchResult(
            FirestoreUserRecord.fromMap(doc.id, doc.data()),
          ),
        );
      }
    }

    // Don't offer the signed-in user their own profile as a search result.
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId != null) byId.remove(currentUserId);

    final results = byId.values.toList()
      ..sort((a, b) => a.displayName
          .toLowerCase()
          .compareTo(b.displayName.toLowerCase()));
    return results;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _prefixQuery(
    String field,
    String prefix,
  ) {
    // U+F8FF sorts above any ordinary character, so the range covers every
    // string starting with `prefix`.
    return usersCollection
        .where(field, isGreaterThanOrEqualTo: prefix)
        .where(field, isLessThanOrEqualTo: '$prefix')
        .limit(20)
        .get();
  }

  @override
  Future<List<ProfileStat>> getProfileStats() async {
    final user = await _loadUserRecord();
    return [
      FirestoreMapper.toProfileStat(label: 'Posts', value: user.postsCount),
      FirestoreMapper.toProfileStat(
          label: 'Followers', value: user.followersCount),
      FirestoreMapper.toProfileStat(
          label: 'Following', value: user.followingCount),
    ];
  }

  @override
  Future<List<ProgressMetric>> getProgressMetrics() async {
    final snapshot = await progressCollection.get();

    return snapshot.docs
        .map((doc) => FirestoreProgressRecord.fromMap(doc.data()))
        .map(FirestoreMapper.toProgressMetric)
        .toList();
  }

  @override
  Future<List<WorkoutPlaylist>> getWorkoutPlaylists(
      WorkoutType workoutType) async {
    return const [];
  }

  @override
  Future<List<PodcastRecommendation>> getPodcastRecommendations() async {
    return const [];
  }

  @override
  Future<List<StoryItem>> getStories(UserProfileDraft? profile) async {
    final currentUser = await _loadUserRecord();
    return [
      FirestoreMapper.toStoryItem(currentUser, isOwnStory: true),
    ];
  }

  @override
  Future<List<SummaryMetric>> getSummaryMetrics() async {
    final user = await _loadUserRecord();
    return [
      FirestoreMapper.toSummaryMetric(
        label: 'This week',
        value: '${user.workoutsCount} workouts',
      ),
      SummaryMetric(label: 'Meals logged', value: '${user.mealsCount} meals'),
    ];
  }

  CollectionReference<Map<String, dynamic>> get usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get postsCollection =>
      _firestore.collection('posts');

  CollectionReference<Map<String, dynamic>> get progressCollection =>
      _firestore.collection('progress');

  CollectionReference<Map<String, dynamic>> get runsCollection =>
      _firestore.collection('runs');

  /// Hard ceiling on stored route points.
  ///
  /// A Firestore document is capped at 1 MiB. At ~45 bytes per `{lat, lng}`
  /// entry a long run sampled at 1 Hz would approach that limit, so routes are
  /// decimated before they are written. 1500 points is far more than a map
  /// preview can resolve while leaving the document comfortably small.
  static const _maxStoredRoutePoints = 1500;

  /// Evenly thins [route] to at most [_maxStoredRoutePoints], always keeping the
  /// first and last fix so the start marker and finish marker stay put.
  static List<Map<String, double>> _serializeRoute(List<RoutePoint> route) {
    if (route.length <= _maxStoredRoutePoints) {
      return route.map((point) => point.toMap()).toList(growable: false);
    }

    final step = route.length / _maxStoredRoutePoints;
    final indices = <int>[
      for (var i = 0; i < _maxStoredRoutePoints; i++) (i * step).floor(),
    ];
    // Decimation lands short of the final fix, so append it — otherwise the
    // finish marker sits somewhere before the actual end of the route.
    final lastIndex = route.length - 1;
    if (indices.last != lastIndex) indices.add(lastIndex);

    return indices.map((i) => route[i].toMap()).toList(growable: false);
  }

  @override
  Future<ActivitySaveResult> saveWorkout(
    UserProfileDraft? profile,
    WorkoutLogDraft draft,
  ) async {
    if (!draft.shareToFeed) {
      await _incrementUser(workoutsDelta: 1);
      return const ActivitySaveResult(message: 'Workout saved.');
    }

    // Create the post first, then increment. Incrementing up front means a
    // failed post write still inflates the user's workout count.
    final post = await _createPost(
      profile: profile,
      activity: draft.title.trim().isEmpty ? 'Workout' : draft.title.trim(),
      caption: draft.notes.trim().isEmpty
          ? 'Logged ${draft.exercises.length} exercises.'
          : draft.notes.trim(),
      metricLabels: [
        draft.duration,
        draft.calories,
        '${draft.exercises.length} moves'
      ],
      themeKey: 'burn',
      postType: 'workout',
      workoutData: {
        'title': draft.title.trim().isEmpty ? 'Workout' : draft.title.trim(),
        'duration': draft.duration,
        'calories': draft.calories,
        'exercises': draft.exercises.map((e) => e.toMap()).toList(),
      },
    );
    await _incrementUser(workoutsDelta: 1);
    return ActivitySaveResult(
        message: 'Workout saved and shared.', createdPost: post);
  }

  @override
  Future<ActivitySaveResult> saveRun(
    UserProfileDraft? profile,
    RunLogDraft draft,
  ) async {
    // The run log is the canonical record and is written whether or not the
    // run is shared, so an unshared GPS run still keeps its route.
    final route = _serializeRoute(draft.routePoints);
    await _writeRunLog(draft, route);

    if (!draft.shareToFeed) {
      await _incrementUser(runsDelta: 1, runDistanceKm: draft.distanceKm);
      return const ActivitySaveResult(message: 'Run saved.');
    }

    final post = await _createPost(
      profile: profile,
      activity: 'Run',
      caption: 'Finished a ${draft.distanceKm.toStringAsFixed(2)} km run.',
      metricLabels: [
        '${draft.distanceKm.toStringAsFixed(2)} km',
        _formatDuration(draft.elapsed),
        draft.averagePace,
      ],
      themeKey: 'sunset',
      // Denormalised onto the post so the feed renders the route from the
      // documents it already streams, with no extra read per card.
      routePoints: route,
    );
    await _incrementUser(runsDelta: 1, runDistanceKm: draft.distanceKm);
    return ActivitySaveResult(
        message: 'Run saved and shared.', createdPost: post);
  }

  /// Persists the run to `runs/{id}` — distance, timings and the GPS trace.
  Future<void> _writeRunLog(
    RunLogDraft draft,
    List<Map<String, double>> route,
  ) async {
    final user = _requireCurrentUser();
    await runsCollection.doc().set({
      'authorId': user.uid,
      'distanceKm': draft.distanceKm,
      'durationSeconds': draft.elapsed.inSeconds,
      'averagePace': draft.averagePace,
      'routePoints': route,
      'pointCount': route.length,
      'sharedToFeed': draft.shareToFeed,
      if (draft.startedAt != null)
        'startedAt': Timestamp.fromDate(draft.startedAt!),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<ActivitySaveResult> saveMeal(
    UserProfileDraft? profile,
    MealLogDraft draft,
  ) async {
    if (!draft.shareToFeed) {
      await _incrementUser(mealsDelta: 1);
      return const ActivitySaveResult(message: 'Meal saved.');
    }

    final post = await _createPost(
      profile: profile,
      activity: draft.name.trim().isEmpty ? 'Meal' : draft.name.trim(),
      caption: draft.notes.trim().isEmpty ? 'Meal logged.' : draft.notes.trim(),
      metricLabels: [
        '${draft.calories.trim()} kcal',
        '${draft.protein.trim()}g protein',
        '${draft.fat.trim()}g fat',
      ],
      themeKey: 'graphite',
      imageUrl: draft.imageUrl,
    );
    await _incrementUser(mealsDelta: 1);
    return ActivitySaveResult(
        message: 'Meal saved and shared.', createdPost: post);
  }

  @override
  Future<ActivitySaveResult> sharePost(
    UserProfileDraft? profile,
    PostDraft draft,
  ) async {
    final caption = draft.caption.trim();
    final post = await _createPost(
      profile: profile,
      activity: 'Status Update',
      caption: caption.isEmpty ? 'Shared a FitSocial update.' : caption,
      metricLabels: const ['Post', 'Community', 'Now'],
      themeKey: 'sunset',
      imageUrl: draft.imageUrl,
      postType: draft.imageUrl != null ? 'image' : 'text',
      imageAspectRatio: draft.imageAspectRatio,
    );
    return ActivitySaveResult(message: 'Post shared.', createdPost: post);
  }

  Future<FirestoreUserRecord> _loadUserRecord() async {
    final user = _requireCurrentUser();
    final userId = user.uid;
    final snapshot = await usersCollection.doc(userId).get();
    if (!snapshot.exists) {
      return FirestoreUserRecord(
        id: user.uid,
        // No email fallback: this record feeds story items and post
        // attribution, both of which are shown to other users.
        displayName: PublicAuthorName.sanitize(user.displayName),
        handle: '@fitsocial',
        bio: '',
        location: '',
        avatarUrl: user.photoURL,
        followersCount: 0,
        followingCount: 0,
        postsCount: 0,
        workoutsCount: 0,
        mealsCount: 0,
      );
    }
    return FirestoreUserRecord.fromMap(
        snapshot.id, snapshot.data() ?? const {});
  }

  /// Public name to attribute the signed-in user's content to.
  ///
  /// Deliberately never consults the auth email. Posts and comments are
  /// readable by every signed-in user, so an email here would leak it
  /// community-wide. Prefers the session profile, falls back to the stored
  /// profile document, then to a safe generic name.
  Future<String> _resolvePublicAuthorName(UserProfileDraft? profile) async {
    final fromSession = PublicAuthorName.firstSafe([
      profile?.displayName,
      profile?.handle,
    ]);
    if (fromSession != PublicAuthorName.fallback) return fromSession;

    // The session profile can be null when cold-start bootstrap couldn't load
    // it (offline, transient permission error) — read the stored profile
    // rather than reaching for anything on the auth record.
    try {
      final record = await _loadUserRecord();
      return PublicAuthorName.firstSafe([record.displayName, record.handle]);
    } catch (_) {
      return PublicAuthorName.fallback;
    }
  }

  /// The author's profile photo for denormalising onto a new post.
  ///
  /// Mirrors [_resolvePublicAuthorName]: prefer the in-memory session profile,
  /// and only fall back to a stored read when the session has nothing. Returns
  /// null rather than throwing — a missing avatar must never block a post.
  Future<String?> _resolveAuthorAvatarUrl(UserProfileDraft? profile) async {
    final fromSession = profile?.avatarUrl;
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;

    try {
      final stored = (await _loadUserRecord()).avatarUrl;
      return (stored != null && stored.isNotEmpty) ? stored : null;
    } catch (_) {
      return null;
    }
  }

  Future<FeedPost> _createPost({
    required UserProfileDraft? profile,
    required String activity,
    required String caption,
    required List<String> metricLabels,
    required String themeKey,
    String postType = 'text',
    String? imageUrl,
    Map<String, dynamic>? workoutData,
    List<Map<String, double>> routePoints = const [],
    double? imageAspectRatio,
  }) async {
    final user = _requireCurrentUser();
    final userId = user.uid;
    final authorName = await _resolvePublicAuthorName(profile);
    final authorAvatarUrl = await _resolveAuthorAvatarUrl(profile);
    final document = postsCollection.doc();

    final record = FirestorePostRecord(
      id: document.id,
      authorId: userId,
      authorName: authorName,
      activity: activity,
      caption: caption,
      metricLabels: metricLabels,
      likesCount: 0,
      commentsCount: 0,
      timestampLabel: 'now',
      themeKey: themeKey,
      likedBy: const [],
      postType: postType,
      imageUrl: imageUrl,
      workoutData: workoutData,
      routePoints: RoutePoint.listFromFirestore(routePoints),
      authorAvatarUrl: authorAvatarUrl,
      imageAspectRatio: imageAspectRatio,
    );

    await document.set({
      'authorId': record.authorId,
      'authorName': record.authorName,
      'activity': record.activity,
      'caption': record.caption,
      'metricLabels': record.metricLabels,
      'likesCount': record.likesCount,
      'commentsCount': record.commentsCount,
      'timestampLabel': record.timestampLabel,
      'themeKey': record.themeKey,
      'likedBy': record.likedBy,
      'postType': record.postType,
      if (record.authorAvatarUrl != null)
        'authorAvatarUrl': record.authorAvatarUrl,
      if (record.imageUrl != null) 'imageUrl': record.imageUrl,
      if (record.imageAspectRatio != null)
        'imageAspectRatio': record.imageAspectRatio,
      if (record.workoutData != null) 'workoutData': record.workoutData,
      if (routePoints.isNotEmpty) 'routePoints': routePoints,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _incrementUser(postsDelta: 1);

    return FirestoreMapper.toFeedPost(record);
  }

  /// Applies activity counters and advances the daily streak.
  ///
  /// Runs inside a transaction because the streak has to be read before it can
  /// be extended, and a blind write would clobber a concurrent log.
  Future<void> _incrementUser({
    int postsDelta = 0,
    int workoutsDelta = 0,
    int mealsDelta = 0,
    int runsDelta = 0,
    double? runDistanceKm,
  }) async {
    final user = _requireCurrentUser();
    final documentRef = usersCollection.doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(documentRef);
      final data = snapshot.data() ?? const <String, dynamic>{};

      final now = DateTime.now();
      final today = _dayStamp(now);
      final yesterday = _dayStamp(now.subtract(const Duration(days: 1)));
      final lastActivityDay = data['lastActivityDay'] as String?;
      final storedStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;

      // Same-day logs don't extend the streak; a gap of more than one day
      // resets it to today's single day.
      final int streak;
      if (lastActivityDay == today) {
        streak = storedStreak < 1 ? 1 : storedStreak;
      } else if (lastActivityDay == yesterday) {
        streak = storedStreak + 1;
      } else {
        streak = 1;
      }

      final storedMaxRunKm =
          (data['maxRunDistanceKm'] as num?)?.toDouble() ?? 0;

      transaction.set(documentRef, {
        if (postsDelta != 0) 'postsCount': FieldValue.increment(postsDelta),
        if (workoutsDelta != 0)
          'workoutsCount': FieldValue.increment(workoutsDelta),
        if (mealsDelta != 0) 'mealsCount': FieldValue.increment(mealsDelta),
        if (runsDelta != 0) 'runsCount': FieldValue.increment(runsDelta),
        if (runDistanceKm != null && runDistanceKm > storedMaxRunKm)
          'maxRunDistanceKm': runDistanceKm,
        'currentStreak': streak,
        'lastActivityDay': today,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  @override
  Future<AchievementsData> fetchUserAchievements(String userId) async {
    final snapshot = await usersCollection.doc(userId).get();
    final data = snapshot.data() ?? const <String, dynamic>{};

    final workouts = (data['workoutsCount'] as num?)?.toInt() ?? 0;
    final meals = (data['mealsCount'] as num?)?.toInt() ?? 0;
    final runs = (data['runsCount'] as num?)?.toInt() ?? 0;
    final maxRunKm = (data['maxRunDistanceKm'] as num?)?.toDouble() ?? 0;

    final totalXp = workouts * AchievementXp.perWorkout +
        meals * AchievementXp.perMeal +
        runs * AchievementXp.perRun;
    final level = (totalXp / AchievementXp.perLevel).floor() + 1;

    // A stored streak is only live while the last log was today or yesterday —
    // otherwise the chain is broken and the streak has lapsed to zero.
    final now = DateTime.now();
    final lastActivityDay = data['lastActivityDay'] as String?;
    final isStreakLive = lastActivityDay == _dayStamp(now) ||
        lastActivityDay == _dayStamp(now.subtract(const Duration(days: 1)));
    final currentStreak =
        isStreakLive ? (data['currentStreak'] as num?)?.toInt() ?? 0 : 0;

    return AchievementsData(
      currentXp: totalXp,
      nextLevelXp: level * AchievementXp.perLevel,
      level: level,
      currentStreak: currentStreak,
      badges: [
        BadgeProgress(
          id: 'first_workout',
          title: 'First Workout',
          description: 'Log your first workout',
          iconName: 'workout',
          currentProgress: workouts,
          targetGoal: 1,
        ),
        BadgeProgress(
          id: 'first_meal',
          title: 'First Meal Logged',
          description: 'Log your first meal',
          iconName: 'meal',
          currentProgress: meals,
          targetGoal: 1,
        ),
        BadgeProgress(
          id: 'ten_workouts',
          title: '10 Workouts Club',
          description: 'Log 10 workouts',
          iconName: 'trophy',
          currentProgress: workouts,
          targetGoal: 10,
        ),
        BadgeProgress(
          id: 'five_k_runner',
          title: '5K Runner',
          description: 'Finish a single 5 km run',
          iconName: 'run',
          // Measured against the longest run on record, in whole km.
          currentProgress: maxRunKm.floor(),
          targetGoal: 5,
        ),
      ],
    );
  }

  User _requireCurrentUser() {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('A Firebase user must be signed in for this action.');
    }
    return user;
  }

  @override
  Future<void> toggleLike(String postId, String userId) async {
    final postRef = postsCollection.doc(postId);
    final likeRef = _firestore
        .collection('likes')
        .doc(postId)
        .collection('users')
        .doc(userId);

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      final likeSnapshot = await transaction.get(likeRef);

      if (!postSnapshot.exists) return;

      // Read the legacy likedBy array for backward compatibility.
      final data = postSnapshot.data() ?? {};
      final likedBy = List<String>.from(
        (data['likedBy'] as List<dynamic>?) ?? [],
      );

      if (likeSnapshot.exists) {
        // ── Unlike ──
        transaction.delete(likeRef);
        likedBy.remove(userId);
        transaction.update(postRef, {
          'likedBy': likedBy,
          'likesCount': FieldValue.increment(-1),
        });
      } else {
        // ── Like ──
        transaction.set(likeRef, {
          'likedAt': FieldValue.serverTimestamp(),
        });
        if (!likedBy.contains(userId)) likedBy.add(userId);
        transaction.update(postRef, {
          'likedBy': likedBy,
          'likesCount': FieldValue.increment(1),
        });
      }
    });
  }

  @override
  Future<List<Comment>> getComments(String postId) async {
    final snapshot = await postsCollection
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .get();

    return snapshot.docs
        .map((doc) => FirestoreCommentRecord.fromMap(doc.id, doc.data()))
        .map(FirestoreMapper.toComment)
        .toList();
  }

  @override
  Future<Comment> addComment(
    UserProfileDraft? profile,
    String postId,
    String text,
  ) async {
    final user = _requireCurrentUser();
    final authorName = await _resolvePublicAuthorName(profile);
    final commentRef = postsCollection.doc(postId).collection('comments').doc();

    final now = DateTime.now();

    // Write the comment and bump the post's counter atomically. Done as two
    // separate awaits, a failure on the counter would leave an orphaned
    // comment behind and the caller would retry, creating duplicates.
    final batch = _firestore.batch();
    batch.set(commentRef, {
      'authorId': user.uid,
      'authorName': authorName,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(postsCollection.doc(postId), {
      'commentsCount': FieldValue.increment(1),
    });
    await batch.commit();

    return Comment(
      id: commentRef.id,
      authorId: user.uid,
      authorName: authorName,
      text: text,
      createdAt: now,
    );
  }

  // ── NEW: Social action streams & toggles ──────────────────────────────────

  @override
  Future<void> toggleBookmark(String postId, String userId) async {
    final bookmarkRef = usersCollection
        .doc(userId)
        .collection('bookmarks')
        .doc(postId);

    final snapshot = await bookmarkRef.get();
    if (snapshot.exists) {
      await bookmarkRef.delete();
    } else {
      await bookmarkRef.set({
        'postId': postId,
        'savedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Stream<bool> watchPostLikeStatus(String postId, String userId) {
    return _firestore
        .collection('likes')
        .doc(postId)
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  @override
  Stream<bool> watchBookmarkStatus(String postId, String userId) {
    return usersCollection
        .doc(userId)
        .collection('bookmarks')
        .doc(postId)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  @override
  Stream<List<Comment>> watchComments(String postId) {
    return postsCollection
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                FirestoreCommentRecord.fromMap(doc.id, doc.data()))
            .map(FirestoreMapper.toComment)
            .toList());
  }

  @override
  Future<String> uploadMealImage(String localFilePath) async {
    final user = _requireCurrentUser();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance
        .ref()
        .child('meals/${user.uid}/$timestamp.jpg');

    // Bytes rather than a dart:io File, so this works on every platform: on
    // mobile XFile reads the picked file, on web it fetches the blob: URL that
    // image_picker returns instead of a real path.
    final bytes = await XFile(localFilePath).readAsBytes();
    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final snapshot = await uploadTask.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw const TimeoutException(
        'Image upload timed out after 60 seconds.',
      ),
    );
    return await snapshot.ref.getDownloadURL();
  }

  @override
  Future<String> uploadPostImage(String localFilePath) async {
    final user = _requireCurrentUser();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance
        .ref()
        .child('posts/${user.uid}/$timestamp.jpg');

    // See uploadMealImage: bytes keep this working on mobile and web alike.
    final bytes = await XFile(localFilePath).readAsBytes();
    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final snapshot = await uploadTask.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw const TimeoutException(
        'Image upload timed out after 60 seconds.',
      ),
    );
    return await snapshot.ref.getDownloadURL();
  }

  @override
  Future<Map<String, dynamic>> analyzeMealImage(String imageUrl) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'analyzeMeal',
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 60),
      ),
    );

    final result = await callable.call<Map<String, dynamic>>({
      'imageUrl': imageUrl,
    });

    final data = Map<String, dynamic>.from(result.data);
    return data;
  }
}

class TimeoutException implements Exception {
  const TimeoutException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 'bear mdlalose' -> 'Bear mdlalose'. Only the first character is touched:
/// display names are stored as typed, and this exists purely to build a second
/// prefix-range probe for lowercase search input.
String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

/// Local calendar day as `YYYY-MM-DD`, used as the streak's day key so
/// comparisons ignore the time of day.
String _dayStamp(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
