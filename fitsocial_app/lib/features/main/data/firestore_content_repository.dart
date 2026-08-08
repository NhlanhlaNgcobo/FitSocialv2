import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../auth/domain/auth_models.dart';
import '../../notifications/data/firestore_notification_repository.dart';
import '../../notifications/domain/notification_models.dart';
import '../domain/app_models.dart';
import '../domain/explore_models.dart';
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

  /// Notifications are raised from here rather than from a screen, because the
  /// action and the notification have to commit together — see
  /// [NotificationWrites].
  late final NotificationWrites _notifications = NotificationWrites(_firestore);

  @override
  Future<HomeFeed> getFeedPosts(UserProfileDraft? profile) async {
    final userId = _firebaseAuth.currentUser?.uid;
    // Signed out there is no follow graph to read, so the community's best
    // stands in rather than an empty page.
    if (userId == null) return _suggestedFeed();

    final following = await _followingIds(userId);
    // Nobody followed yet: a strictly personal feed would be blank on a new
    // account, which reads as a broken app rather than an empty one.
    if (following.isEmpty) return _suggestedFeed();

    final posts = await _postsByAuthors({...following, userId});
    // Everyone they follow has been quiet — or has only posted from before
    // createdAt was recorded. Either way, an empty screen is the worst answer.
    if (posts.isEmpty) return _suggestedFeed();

    return HomeFeed(posts: posts, source: FeedSource.following);
  }

  Future<HomeFeed> _suggestedFeed() async {
    return HomeFeed(
      posts: await fetchTrendingPosts(),
      source: FeedSource.suggested,
    );
  }

  /// Who [userId] follows.
  ///
  /// Capped: past a few hundred followed accounts the chunked query below
  /// stops being the right shape and the feed wants a fan-out inbox written
  /// server-side. This ceiling keeps the read bounded until that day comes.
  Query<Map<String, dynamic>> _followingQuery(String userId) {
    return usersCollection
        .doc(userId)
        .collection('following')
        .limit(_maxFollowedAuthors);
  }

  /// The followed uid is the document id — the body only records when.
  static Set<String> _idsOf(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs.map((doc) => doc.id).toSet();

  Future<Set<String>> _followingIds(String userId) async =>
      _idsOf(await _followingQuery(userId).get());

  @override
  Stream<Set<String>> watchFollowingIds(String userId) =>
      _followingQuery(userId).snapshots().map(_idsOf);

  /// The newest posts by any of [authorIds], newest first.
  ///
  /// Firestore's `whereIn` takes at most [_authorChunkSize] values, so the
  /// authors are split into chunks and queried in parallel. Each chunk asks
  /// for [_feedLimit] posts, which is what makes the merge below correct: the
  /// newest [_feedLimit] posts overall cannot fall outside the newest
  /// [_feedLimit] of every chunk they could have come from.
  Future<List<FeedPost>> _postsByAuthors(Set<String> authorIds) async {
    final ids = authorIds.toList(growable: false);

    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < ids.length; i += _authorChunkSize) {
      futures.add(
        postsCollection
            .where('authorId', whereIn: ids.skip(i).take(_authorChunkSize).toList())
            .orderBy('createdAt', descending: true)
            .limit(_feedLimit)
            .get(),
      );
    }

    final snapshots = await Future.wait(futures);
    final records = <FirestorePostRecord>[
      for (final snapshot in snapshots)
        for (final doc in snapshot.docs)
          FirestorePostRecord.fromMap(doc.id, doc.data()),
    ];

    return newestFirst(records, limit: _feedLimit)
        .map(FirestoreMapper.toFeedPost)
        .toList(growable: false);
  }

  /// The [limit] newest of [records].
  ///
  /// Each chunk query comes back ordered, but their union does not — this is
  /// where several queries become one feed. Anything without a timestamp sorts
  /// last rather than jumping to the top of someone's feed.
  static List<FirestorePostRecord> newestFirst(
    List<FirestorePostRecord> records, {
    required int limit,
  }) {
    final sorted = [...records]..sort((a, b) {
        final left = a.createdAt;
        final right = b.createdAt;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });

    return sorted.take(limit).toList(growable: false);
  }

  /// How many posts the home feed holds.
  static const int _feedLimit = 30;

  /// Firestore's ceiling on the number of values in a `whereIn` filter.
  static const int _authorChunkSize = 30;

  /// Upper bound on followed accounts a single feed load will consider.
  static const int _maxFollowedAuthors = 300;

  @override
  Future<FeedPost?> fetchPost(String postId) async {
    final snapshot = await postsCollection.doc(postId).get();
    if (!snapshot.exists) return null;
    return FirestoreMapper.toFeedPost(
      FirestorePostRecord.fromMap(snapshot.id, snapshot.data() ?? const {}),
    );
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
    // Ordered by recency rather than by likes. The scoring below needs a
    // candidate pool that actually contains recent posts, and `likesCount desc`
    // would only ever hand back the all-time winners — the very thing that made
    // this grid static. Posts written before `createdAt` was recorded are
    // dropped by the orderBy, exactly as they already are from the main feed.
    final snapshot = await postsCollection
        .orderBy('createdAt', descending: true)
        .limit(_trendingCandidatePool)
        .get();

    final now = DateTime.now();
    final scored = snapshot.docs
        .map((doc) => FirestorePostRecord.fromMap(doc.id, doc.data()))
        .map(
          (record) => (
            record: record,
            score: TrendingScore.of(
              likes: record.likesCount,
              comments: record.commentsCount,
              createdAt: record.createdAt,
              now: now,
            ),
          ),
        )
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored
        .take(_trendingLimit)
        .map((entry) => FirestoreMapper.toFeedPost(entry.record))
        .toList(growable: false);
  }

  /// How many recent posts are scored to fill the grid. Ranking happens on
  /// device, so the pool has to be wide enough that a well-received post from
  /// last week can still beat today's quiet ones — but it is one query either
  /// way, and 120 covers a small community's fortnight.
  static const int _trendingCandidatePool = 120;

  /// How many of the scored posts reach the grid.
  static const int _trendingLimit = 30;

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
  Future<void> followUser(
    String currentUserId,
    String targetUserId, {
    UserProfileDraft? profile,
  }) async {
    if (currentUserId == targetUserId) {
      throw ArgumentError("You can't follow your own profile.");
    }

    final followingRef = _followingRef(currentUserId, targetUserId);

    // Bail if the edge is already there — a double tap would otherwise
    // increment the counters twice for a single relationship.
    final existing = await followingRef.get();
    if (existing.exists) return;

    // Resolved before the batch opens: it may need a profile read, and a batch
    // is a write set, not a place to go looking things up.
    final actorName = await _resolvePublicAuthorName(profile);
    final actorAvatarUrl = await _resolveAuthorAvatarUrl(profile);

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
    // In the same batch as the edges themselves. A follow that moved the
    // counters but never reached the other person's inbox is a follow they
    // have no way of finding out about.
    batch.set(
      _notifications.ref(targetUserId, NotificationIds.follow(currentUserId)),
      _notifications.followPayload(
        actorId: currentUserId,
        actorName: actorName,
        actorAvatarUrl: actorAvatarUrl,
      ),
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
    // Withdraw the notification the follow raised, so the inbox stops
    // announcing a relationship that no longer exists. Deleting a document
    // that was never there — a follow made before notifications existed — is
    // a no-op, which is why this needs no existence check.
    batch.delete(
      _notifications.ref(targetUserId, NotificationIds.follow(currentUserId)),
    );
    await batch.commit();
  }

  @override
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId) {
    return _followingRef(currentUserId, targetUserId)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  /// The caller's "notify me about this person" marker. Presence is the whole
  /// state, so the document body carries no flag to contradict it.
  DocumentReference<Map<String, dynamic>> _notifyRef(
    String currentUserId,
    String targetUserId,
  ) {
    return usersCollection
        .doc(currentUserId)
        .collection('notifyFor')
        .doc(targetUserId);
  }

  @override
  Stream<bool> watchUserNotifications(
    String currentUserId,
    String targetUserId,
  ) {
    return _notifyRef(currentUserId, targetUserId)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  @override
  Future<void> setUserNotifications(
    String currentUserId,
    String targetUserId, {
    required bool enabled,
  }) {
    final ref = _notifyRef(currentUserId, targetUserId);
    if (!enabled) return ref.delete();
    return ref.set({
      'userId': targetUserId,
      'createdAt': FieldValue.serverTimestamp(),
    });
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
  Future<List<ProfileStat>> getProfileStats(String userId) async {
    // Both reads are started before either is awaited, so they overlap.
    final profileRead = usersCollection.doc(userId).get();
    final photosRead = _countPhotoPosts(userId);

    final snapshot = await profileRead;
    final record =
        FirestoreUserRecord.fromMap(userId, snapshot.data() ?? const {});

    return [
      FirestoreMapper.toProfileStat(
        label: 'Uploads',
        value: await photosRead + record.runsCount + record.workoutsCount,
      ),
      FirestoreMapper.toProfileStat(
          label: 'Followers', value: record.followersCount),
      FirestoreMapper.toProfileStat(
          label: 'Following', value: record.followingCount),
    ];
  }

  /// How many photo posts [userId] has shared.
  ///
  /// Counted by query rather than read off the profile, because no counter
  /// tracks plain photo shares — [_incrementUser] only moves the per-activity
  /// totals. Keys off `postType` so meal shares are left out: a meal carries
  /// an image but is written as a text post, which is what separates the two.
  /// Deliberately unordered, so two equality filters can be served from the
  /// single-field indexes without a composite one.
  Future<int> _countPhotoPosts(String userId) async {
    final snapshot = await postsCollection
        .where('authorId', isEqualTo: userId)
        .where('postType', isEqualTo: 'image')
        .limit(_uploadCountPostLimit)
        .get();

    return snapshot.docs.length;
  }

  /// Ceiling on how many photo posts the upload total counts. Past this the
  /// number under-reports rather than turning one profile view into unbounded
  /// reads.
  static const int _uploadCountPostLimit = 300;

  @override
  Future<UserSearchResult?> fetchUserProfile(String userId) async {
    final snapshot = await usersCollection.doc(userId).get();
    if (!snapshot.exists) return null;
    return FirestoreMapper.toUserSearchResult(
      FirestoreUserRecord.fromMap(snapshot.id, snapshot.data() ?? const {}),
    );
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
  Future<List<ActivityDay>> getActivityDays(DateTime from) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return const [];

    final results = await Future.wait([
      _activityLogs(runsCollection, user.uid),
      _activityLogs(workoutsCollection, user.uid),
    ]);

    // The window is applied here rather than in the query — see _activityLogs.
    //
    // `createdAt` is a server timestamp, so it is the field that is always
    // present and comparable. For bucketing, the client-side stamp is
    // preferred: it carries the moment the session actually happened in the
    // user's own timezone, which is the day the grid should light up.
    final start = ActivityCalendar.dateOnly(from);
    final runsByDay = _countByDay(results[0], ['startedAt', 'createdAt'], start);
    final workoutsByDay =
        _countByDay(results[1], ['loggedAt', 'createdAt'], start);

    final dates = {...runsByDay.keys, ...workoutsByDay.keys}.toList()..sort();
    return [
      for (final date in dates)
        ActivityDay(
          date: date,
          runs: runsByDay[date] ?? 0,
          workouts: workoutsByDay[date] ?? 0,
        ),
    ];
  }

  /// Every log [userId] owns in [collection], or an empty list if that read
  /// could not be served.
  ///
  /// Filtered by author alone, with the date window applied client-side.
  /// Pairing the equality with a `createdAt` range would need a composite
  /// index per collection, and Firestore rejects the query outright until that
  /// index finishes building — so a grid that has to wait on a deploy before
  /// it renders anything. One user's own training history is small enough to
  /// narrow in Dart, and this form runs on the single-field index Firestore
  /// maintains for free.
  ///
  /// Failures are swallowed per collection so that one unreadable collection
  /// costs its own squares rather than the whole grid.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _activityLogs(
    CollectionReference<Map<String, dynamic>> collection,
    String userId,
  ) async {
    try {
      final snapshot =
          await collection.where('authorId', isEqualTo: userId).get();
      return snapshot.docs;
    } on FirebaseException catch (error) {
      debugPrint(
        'Activity grid: could not read ${collection.id} '
        '(${error.code}) — those days will show as empty.',
      );
      return const [];
    }
  }

  /// Tallies [docs] dated on or after [start] into local calendar days, reading
  /// the first of [timestampFields] that holds a usable `Timestamp`.
  static Map<DateTime, int> _countByDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<String> timestampFields,
    DateTime start,
  ) {
    final counts = <DateTime, int>{};
    for (final doc in docs) {
      final data = doc.data();
      for (final field in timestampFields) {
        final value = data[field];
        if (value is! Timestamp) continue;
        // Timestamp.toDate() returns local time, so the day boundary is the
        // user's own midnight rather than UTC's.
        final day = ActivityCalendar.dateOnly(value.toDate());
        if (day.isBefore(start)) break;
        counts.update(day, (running) => running + 1, ifAbsent: () => 1);
        break;
      }
    }
    return counts;
  }

  CollectionReference<Map<String, dynamic>> get usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get postsCollection =>
      _firestore.collection('posts');

  CollectionReference<Map<String, dynamic>> get progressCollection =>
      _firestore.collection('progress');

  CollectionReference<Map<String, dynamic>> get runsCollection =>
      _firestore.collection('runs');

  CollectionReference<Map<String, dynamic>> get workoutsCollection =>
      _firestore.collection('workouts');

  CollectionReference<Map<String, dynamic>> get mealsCollection =>
      _firestore.collection('meals');

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
    // Written whether or not the workout is shared, mirroring saveRun: the log
    // is the canonical record, and the activity grid reads from it. Sharing
    // only decides whether a post is created alongside it.
    await _writeWorkoutLog(draft);

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
      // Stamped so a run is identifiable without inspecting its contents. A
      // manually entered run carries no route, which is why the route alone
      // was never enough to tell one apart.
      postType: 'run',
      // Denormalised onto the post so the feed renders the route from the
      // documents it already streams, with no extra read per card.
      routePoints: route,
    );
    await _incrementUser(runsDelta: 1, runDistanceKm: draft.distanceKm);
    return ActivitySaveResult(
        message: 'Run saved and shared.', createdPost: post);
  }

  /// Persists the workout to `workouts/{id}` — what was done and when.
  ///
  /// `loggedAt` is stamped client-side so the day bucket reflects the user's
  /// own clock; `createdAt` stays a server timestamp for ordering and for the
  /// range filter the activity query runs.
  Future<void> _writeWorkoutLog(WorkoutLogDraft draft) async {
    final user = _requireCurrentUser();
    final title = draft.title.trim();
    await workoutsCollection.doc().set({
      'authorId': user.uid,
      'title': title.isEmpty ? 'Workout' : title,
      'duration': draft.duration,
      'calories': draft.calories,
      'exerciseCount': draft.exercises.length,
      'sharedToFeed': draft.shareToFeed,
      'loggedAt': Timestamp.now(),
      'createdAt': FieldValue.serverTimestamp(),
    });
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
    await _writeMealLog(draft);

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
      // Same reason as runs: without this a meal is just a text post that
      // happens to carry a photo, and nothing downstream can tell.
      postType: 'meal',
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
      // The author's own subtitle when they wrote one. Empty is kept empty —
      // the header renders as a single line rather than showing a label the
      // user never asked for.
      activity: draft.activity.trim(),
      caption: caption.isEmpty ? 'Shared a FitSocial update.' : caption,
      // A plain share has no metrics. The overlay is for posts that measured
      // something — a run's distance, a meal's macros — so a photo post leaves
      // it empty rather than stamping filler words across the picture.
      metricLabels: const [],
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
      // Every post write lands here, so this is the one place that decides
      // what may be printed over a photo. Callers pass what they measured;
      // anything that isn't a measurement never reaches Firestore.
      metricLabels: PostMetricLabels.measured(metricLabels),
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
      // Local clock, only for the copy handed straight back to the feed — the
      // stored value is the server timestamp written below.
      createdAt: DateTime.now(),
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
      totalWorkouts: workouts,
      totalMeals: meals,
      totalRuns: runs,
      longestRunKm: maxRunKm,
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
  Future<void> toggleLike(
    String postId,
    String userId, {
    UserProfileDraft? profile,
  }) async {
    final postRef = postsCollection.doc(postId);
    final likeRef = _firestore
        .collection('likes')
        .doc(postId)
        .collection('users')
        .doc(userId);

    // Resolved up front, for the same reason as in [followUser] — and, when
    // the session profile is passed in, off no reads at all. The author is not
    // known until the post is read inside the transaction, so this is prepared
    // whether or not it ends up being used.
    final actorName = await _resolvePublicAuthorName(profile);
    final actorAvatarUrl = await _resolveAuthorAvatarUrl(profile);

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      final likeSnapshot = await transaction.get(likeRef);

      if (!postSnapshot.exists) return;

      // Read the legacy likedBy array for backward compatibility.
      final data = postSnapshot.data() ?? {};
      final likedBy = List<String>.from(
        (data['likedBy'] as List<dynamic>?) ?? [],
      );

      // Nobody is told about their own like.
      final authorId = (data['authorId'] as String?) ?? '';
      final notificationRef = (authorId.isEmpty || authorId == userId)
          ? null
          : _notifications.ref(
              authorId,
              NotificationIds.like(postId, userId),
            );

      if (likeSnapshot.exists) {
        // ── Unlike ──
        transaction.delete(likeRef);
        likedBy.remove(userId);
        transaction.update(postRef, {
          'likedBy': likedBy,
          'likesCount': FieldValue.increment(-1),
        });
        // Taking the like back takes the notification with it.
        if (notificationRef != null) transaction.delete(notificationRef);
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
        if (notificationRef != null) {
          transaction.set(
            notificationRef,
            _notifications.likePayload(
              actorId: userId,
              actorName: actorName,
              actorAvatarUrl: actorAvatarUrl,
              postId: postId,
              // Carried onto the notification so the row can show what was
              // liked without reading the post back.
              postImageUrl: data['imageUrl'] as String?,
              postType: data['postType'] as String?,
            ),
          );
        }
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
    final authorAvatarUrl = await _resolveAuthorAvatarUrl(profile);
    final commentRef = postsCollection.doc(postId).collection('comments').doc();

    final now = DateTime.now();

    // Write the comment and bump the post's counter atomically. Done as two
    // separate awaits, a failure on the counter would leave an orphaned
    // comment behind and the caller would retry, creating duplicates.
    final batch = _firestore.batch();
    batch.set(commentRef, {
      'authorId': user.uid,
      'authorName': authorName,
      if (authorAvatarUrl != null) 'authorAvatarUrl': authorAvatarUrl,
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
      authorAvatarUrl: authorAvatarUrl,
    );
  }

  @override
  Future<void> deletePost(String postId) async {
    final user = _requireCurrentUser();
    final postRef = postsCollection.doc(postId);

    final snapshot = await postRef.get();
    if (!snapshot.exists) return;

    final data = snapshot.data() ?? const <String, dynamic>{};
    // Checked here as well as in the rules so the user gets a readable message
    // rather than a raw permission-denied from the server.
    if (data['authorId'] != user.uid) {
      throw StateError('You can only delete your own posts.');
    }

    // Firestore does not cascade: deleting a document leaves its subcollections
    // in place, billable and unreachable. Comments must go first — the security
    // rule that lets a post owner remove someone else's comment checks the
    // parent post, which has to still exist for that check to pass.
    final comments = await postRef.collection('comments').get();
    for (var i = 0; i < comments.docs.length; i += 500) {
      final batch = _firestore.batch();
      for (final doc in comments.docs.skip(i).take(500)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    await postRef.delete();

    // Adjust the counter directly rather than through _incrementUser, which
    // also advances the daily streak — deleting a post must not count as
    // activity.
    await usersCollection.doc(user.uid).update({
      'postsCount': FieldValue.increment(-1),
    });

    // Best effort: the image is orphaned the moment the post is gone and keeps
    // costing storage. A failure here shouldn't report the delete as failed,
    // since the post itself is already removed.
    final imageUrl = data['imageUrl'] as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(imageUrl).delete();
      } catch (_) {
        // Already deleted, or a URL we can't resolve — nothing to recover.
      }
    }
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

  @override
  Future<List<FoodSearchResult>> searchFoods(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final callable = FirebaseFunctions.instance.httpsCallable(
      'searchFoods',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );

    final result = await callable.call<Map<String, dynamic>>({
      'query': trimmed,
    });

    final foods = result.data['foods'];
    if (foods is! List) return const [];
    return foods
        .map(FoodSearchResult.fromMap)
        .whereType<FoodSearchResult>()
        .toList(growable: false);
  }

  /// Persists the meal to `meals/{id}` — the totals plus the itemised
  /// breakdown behind them.
  ///
  /// Kept whether or not the meal was shared, for the same reason as runs and
  /// workouts: this is the user's nutrition history. The feed post carries only
  /// the three headline numbers, so without this the analysis is lost the
  /// moment the screen closes.
  Future<void> _writeMealLog(MealLogDraft draft) async {
    final user = _requireCurrentUser();
    int macro(String value) =>
        int.tryParse(value.trim()) ?? double.tryParse(value.trim())?.round() ?? 0;

    await mealsCollection.doc().set({
      'authorId': user.uid,
      'name': draft.name.trim(),
      'calories': macro(draft.calories),
      'protein': macro(draft.protein),
      'carbs': macro(draft.carbs),
      'fat': macro(draft.fat),
      'notes': draft.notes.trim(),
      'items': draft.items.map((item) => item.toMap()).toList(),
      'itemCount': draft.items.length,
      'sharedToFeed': draft.shareToFeed,
      if (draft.imageUrl != null) 'imageUrl': draft.imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
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
