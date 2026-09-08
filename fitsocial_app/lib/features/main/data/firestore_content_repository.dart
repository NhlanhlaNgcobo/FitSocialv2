import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/functions_region.dart';
import '../../../shared/reactions/fit_reaction.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/domain/username.dart';
import '../../notifications/data/firestore_notification_repository.dart';
import '../../notifications/domain/notification_models.dart';
import '../domain/app_models.dart';
import '../domain/comment_threads.dart';
import '../domain/explore_models.dart';
import '../domain/meal_tracking.dart';
import '../domain/mentions.dart';
import '../domain/progress_models.dart';
import 'activity_session_parsing.dart';
import 'author_identity_cache.dart';
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

  /// Current author names and photos, for laying over the copies frozen onto
  /// posts and comments. Lives on the repository so a session's lookups
  /// accumulate across the feed, profiles and post details.
  late final AuthorIdentityCache _authorIdentities =
      AuthorIdentityCache(_readAuthorIdentities);

  /// Reads profile documents by uid, [_authorChunkSize] at a time — Firestore
  /// caps a `whereIn` at that many values, and the feed's own author queries
  /// are already chunked the same way.
  ///
  /// Absent documents are simply left out of the result, which is what tells
  /// the cache to keep whatever the post stored.
  Future<Map<String, AuthorIdentity>> _readAuthorIdentities(
    List<String> userIds,
  ) async {
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < userIds.length; i += _authorChunkSize) {
      futures.add(
        usersCollection
            .where(
              FieldPath.documentId,
              whereIn: userIds.skip(i).take(_authorChunkSize).toList(),
            )
            .get(),
      );
    }

    final snapshots = await Future.wait(futures);
    return {
      for (final snapshot in snapshots)
        for (final doc in snapshot.docs)
          doc.id: AuthorIdentity(
            displayName: doc.data()['displayName'] as String?,
            avatarUrl: doc.data()['avatarUrl'] as String?,
          ),
    };
  }

  /// [posts] with every author's current name and photo overlaid.
  ///
  /// One extra query per 30 distinct authors on the page, and none at all once
  /// they are cached — which is what makes this affordable where resolving a
  /// profile per card was not.
  Future<List<FeedPost>> _withLiveAuthors(List<FeedPost> posts) async {
    if (posts.isEmpty) return posts;
    final identities =
        await _authorIdentities.resolve(posts.map((post) => post.authorId));
    if (identities.isEmpty) return posts;
    return [
      for (final post in posts)
        FirestoreMapper.withLiveAuthor(post, identities[post.authorId]),
    ];
  }

  /// [comments] with every author's current name and photo overlaid.
  Future<List<Comment>> _withLiveCommentAuthors(List<Comment> comments) async {
    if (comments.isEmpty) return comments;
    final identities = await _authorIdentities
        .resolve(comments.map((comment) => comment.authorId));
    if (identities.isEmpty) return comments;
    return [
      for (final comment in comments)
        FirestoreMapper.commentWithLiveAuthor(
          comment,
          identities[comment.authorId],
        ),
    ];
  }

  /// Puts the signed-in user's own profile into the cache without a read.
  ///
  /// Their rename is already in hand here, and their own old posts are where a
  /// stale name is most visible. Without this they would wait out the cache's
  /// TTL to see the change they just made.
  void _seedOwnIdentity(UserProfileDraft? profile) {
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null || profile == null) return;
    _authorIdentities.seed(
      userId,
      AuthorIdentity(
        displayName: PublicAuthorName.firstSafe([
          profile.displayName,
          profile.handle,
        ]),
        avatarUrl: profile.avatarUrl,
      ),
    );
  }

  @override
  Future<HomeFeed> getFeedPosts(UserProfileDraft? profile) async {
    _seedOwnIdentity(profile);
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

    // Enough to stand on its own: this is their feed, and nothing is added.
    if (posts.length >= _feedFloor) {
      return HomeFeed(posts: posts, source: FeedSource.following);
    }

    return _blendedFeed(posts);
  }

  Future<HomeFeed> _suggestedFeed() async {
    return HomeFeed(
      posts: await fetchTrendingPosts(),
      source: FeedSource.suggested,
    );
  }

  /// A thin following feed, topped up with suggestions underneath.
  ///
  /// The followed posts stay at the top and in their own order. That ordering
  /// is the point: the people you chose come first, and a merge by recency
  /// would bury a training partner's post under strangers' — which is the
  /// opposite of what following is for.
  Future<HomeFeed> _blendedFeed(List<FeedPost> followed) async {
    final alreadyShown = followed.map((post) => post.id).toSet();
    final topUp = (await fetchTrendingPosts())
        .where((post) => !alreadyShown.contains(post.id))
        .toList(growable: false);

    // A small community where everything trending is already in the feed. No
    // header, because there is nothing underneath it to introduce.
    if (topUp.isEmpty) {
      return HomeFeed(posts: followed, source: FeedSource.following);
    }

    return HomeFeed(
      posts: [...followed, ...topUp],
      source: FeedSource.blended,
      followedIds: alreadyShown,
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
            .where('authorId',
                whereIn: ids.skip(i).take(_authorChunkSize).toList())
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

    return _withLiveAuthors(
      newestFirst(records, limit: _feedLimit)
          .map(FirestoreMapper.toFeedPost)
          .toList(growable: false),
    );
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

  /// How many followed posts a feed needs before it stands on its own.
  ///
  /// Below this the feed is topped up with suggestions — see [_blendedFeed].
  /// Eight is roughly a screen and a half on a phone: enough that scrolling
  /// finds something, and low enough that somebody with a healthy follow list
  /// never sees a stranger's post on their feed at all.
  static const int _feedFloor = 8;

  /// Firestore's ceiling on the number of values in a `whereIn` filter.
  static const int _authorChunkSize = 30;

  /// Upper bound on followed accounts a single feed load will consider.
  static const int _maxFollowedAuthors = 300;

  @override
  Future<FeedPost?> fetchPost(String postId) async {
    final snapshot = await postsCollection.doc(postId).get();
    if (!snapshot.exists) return null;
    final post = FirestoreMapper.toFeedPost(
      FirestorePostRecord.fromMap(snapshot.id, snapshot.data() ?? const {}),
    );
    return (await _withLiveAuthors([post])).single;
  }

  @override
  Future<List<FeedPost>> fetchUserPosts(String userId) async {
    final snapshot = await postsCollection
        .where('authorId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(120)
        .get();

    return _withLiveAuthors(
      snapshot.docs
          .map((doc) => FirestorePostRecord.fromMap(doc.id, doc.data()))
          .map(FirestoreMapper.toFeedPost)
          .toList(),
    );
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

    return _withLiveAuthors(
      scored
          .take(_trendingLimit)
          .map((entry) => FirestoreMapper.toFeedPost(entry.record))
          .toList(growable: false),
    );
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
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
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

  /// How many names a composer offers at once. Long enough to be useful,
  /// short enough that the list never covers the text being written.
  static const int _mentionSuggestionLimit = 8;

  @override
  Future<List<UserSearchResult>> suggestMentions(String prefix) async {
    final term = normalizeUsername(prefix);

    // Just after the '@' there is nothing to match on, so the list opens on
    // the people the user follows — who they mean is far more often someone
    // they already have a relationship with than a stranger.
    if (term.isEmpty) return _mentionableFollowing();

    // Handles are stored normalized, but accounts predating that carry a
    // leading '@' in the field. Both forms are probed so neither generation of
    // profile is invisible to the composer.
    final snapshots = await Future.wait([
      _prefixQuery('handle', term),
      _prefixQuery('handle', '@$term'),
    ]);

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

    // Unlike searchUsers, the signed-in user is left in: writing your own
    // handle into a caption is ordinary, and dropping yourself from the list
    // makes the composer look broken rather than tactful.
    final results = byId.values.toList()
      ..sort((a, b) =>
          normalizeUsername(a.handle).compareTo(normalizeUsername(b.handle)));
    return results.take(_mentionSuggestionLimit).toList(growable: false);
  }

  /// The opening suggestion list: people the user follows, alphabetically.
  Future<List<UserSearchResult>> _mentionableFollowing() async {
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null) return const [];

    final edges = await usersCollection
        .doc(userId)
        .collection('following')
        .limit(_mentionSuggestionLimit)
        .get();
    if (edges.docs.isEmpty) return const [];

    final profiles = await Future.wait(
      edges.docs.map((doc) => usersCollection.doc(doc.id).get()),
    );

    final results = <UserSearchResult>[];
    for (final profile in profiles) {
      final data = profile.data();
      if (data == null) continue;
      results.add(
        FirestoreMapper.toUserSearchResult(
          FirestoreUserRecord.fromMap(profile.id, data),
        ),
      );
    }
    results.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return results;
  }

  /// The accounts that should be told about the `@handles` in [text].
  ///
  /// Silently drops names nobody holds — a typo'd handle still renders as a
  /// link, it just has nothing to notify — and drops [actorId], because being
  /// told you mentioned yourself is noise.
  Future<List<String>> _resolveMentionRecipients(
    String text,
    String actorId,
  ) async {
    final names = mentionedUsernames(text);
    if (names.isEmpty) return const [];

    final resolved = await Future.wait(names.map(resolveUsername));

    final recipients = <String>{};
    for (final uid in resolved) {
      if (uid == null || uid.isEmpty || uid == actorId) continue;
      recipients.add(uid);
    }
    return recipients.toList(growable: false);
  }

  @override
  Future<String?> resolveUsername(String username) async {
    final name = normalizeUsername(username);
    if (name.isEmpty) return null;

    final snapshot = await usernamesCollection.doc(name).get();
    final data = snapshot.data();
    if (data == null) return null;

    // A vacated name still has a document — it is held, not deleted — so a
    // reservation past its release date belongs to nobody.
    final releaseAt = data['releaseAt'];
    if (releaseAt is Timestamp && releaseAt.toDate().isBefore(DateTime.now())) {
      return null;
    }

    final uid = (data['uid'] as String?) ?? '';
    return uid.isEmpty ? null : uid;
  }

  @override
  Future<List<ProfileStat>> getProfileStats(String userId) async {
    final snapshot = await usersCollection.doc(userId).get();
    final record =
        FirestoreUserRecord.fromMap(userId, snapshot.data() ?? const {});

    return [
      FirestoreMapper.toProfileStat(
          label: 'Followers', value: record.followersCount),
      FirestoreMapper.toProfileStat(
          label: 'Following', value: record.followingCount),
    ];
  }

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
  Future<List<ActivitySession>> getActivitySessions() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return const [];

    final results = await Future.wait([
      _activityLogs(runsCollection, user.uid),
      _activityLogs(workoutsCollection, user.uid),
    ]);

    final logged = <ActivitySession>[
      ..._mapDocs(results[0], _toRunSession),
      ..._mapDocs(results[1], _toWorkoutSession),
    ];

    // Sessions from before the log collections existed survive only as the
    // posts they were shared as. Those posts are the record for that period,
    // so they are read back as sessions too — otherwise the grid and the
    // totals start on the day the log collections were added and everything
    // earlier looks like rest days.
    return mergeSessions(
      logged: logged,
      fromPosts: await _postSessions(user.uid),
    );
  }

  @override
  Future<List<LoggedMeal>> getLoggedMeals() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return const [];

    // Same shape as the activity logs: an `authorId` equality filter runs on
    // the single-field index Firestore maintains for free, and the ordering is
    // done in Dart. One user's own meal history is small.
    final docs = await _activityLogs(mealsCollection, user.uid);

    final meals = _mapDocs(docs, _toLoggedMeal);
    // Newest first, matching every other history the app hands back. The
    // tracking page re-sorts the window it shows into the order the meals
    // happened.
    meals.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    return meals;
  }

  /// One `meals` document as a [LoggedMeal], or null when it has no usable
  /// date.
  ///
  /// `loggedAt` is the client stamp written since meal tracking existed;
  /// `createdAt` is the server timestamp every meal has carried from the
  /// start. Older meals have only the latter, and a meal still in flight has
  /// only the former — so both are consulted before giving up.
  static LoggedMeal? _toLoggedMeal(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final loggedAt = (data['loggedAt'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate();
    // No date, no place in a day's totals.
    if (loggedAt == null) return null;

    return LoggedMeal(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      loggedAt: loggedAt,
      // intFromStoredValue rather than a cast: the macro fields have been
      // written as numbers throughout, but the same defensive read the
      // sessions use costs nothing and cannot throw on a stray string.
      calories: intFromStoredValue(data['calories']),
      protein: intFromStoredValue(data['protein']),
      carbs: intFromStoredValue(data['carbs']),
      fat: intFromStoredValue(data['fat']),
      imageUrl: data['imageUrl'] as String?,
      itemCount: intFromStoredValue(data['itemCount']),
      sharedToFeed: boolFromStoredValue(data['sharedToFeed']),
      postId: data['postId'] as String?,
    );
  }

  /// Macro goals live beside the body metrics, in the owner-only part of the
  /// account: what someone is aiming to eat is nobody else's business, and the
  /// profile document is readable by every signed-in user.
  DocumentReference<Map<String, dynamic>> _nutritionRef(String userId) =>
      usersCollection.doc(userId).collection('private').doc('nutrition');

  @override
  Future<MacroGoals> getMacroGoals() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return const MacroGoals();

    try {
      final snapshot = await _nutritionRef(user.uid).get();
      return MacroGoals.fromMap(snapshot.data());
    } catch (error) {
      // The defaults are a usable page; an error here is not worth one.
      debugPrint('Meal tracking: goals unreadable ($error) — using defaults.');
      return const MacroGoals();
    }
  }

  @override
  Future<void> setMacroGoals(MacroGoals goals) async {
    final user = _requireCurrentUser();
    await _settleWrite(
      _nutritionRef(user.uid).set(
        {...goals.toMap(), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      ),
    );
  }

  @override
  Future<void> deleteLoggedMeal(String id) async {
    _requireCurrentUser();
    await _settleWrite(mealsCollection.doc(id).delete());
  }

  /// The user's runs and workouts as recorded on their posts.
  ///
  /// Recognition goes through [ExploreFilterX], which already knows every form
  /// a run or workout post has taken — including the ones written before the
  /// `run` and `workout` post types existed, where the route or the activity
  /// label is the only tell.
  Future<List<ActivitySession>> _postSessions(String userId) async {
    try {
      final snapshot =
          await postsCollection.where('authorId', isEqualTo: userId).get();

      final sessions = <ActivitySession>[];
      for (final doc in snapshot.docs) {
        final record = FirestorePostRecord.fromMap(doc.id, doc.data());
        final createdAt = record.createdAt;
        // No date, no place on a calendar.
        if (createdAt == null) continue;

        final post = FirestoreMapper.toFeedPost(record);
        // Runs first: a run post carries no workoutData, but checking in this
        // order means a post that somehow has both is read as the run it says
        // it is rather than as a workout.
        if (ExploreFilterX.isRun(post)) {
          sessions.add(_runSessionFromPost(post, createdAt));
        } else if (ExploreFilterX.isWorkout(post)) {
          sessions.add(_workoutSessionFromPost(post, createdAt));
        }
      }
      return sessions;
    } catch (error) {
      debugPrint(
        'Progress: could not read posts for older sessions ($error) — '
        'anything logged before the run and workout collections will be '
        'missing.',
      );
      return const [];
    }
  }

  /// A run post as a session. Distance and elapsed time come back off the
  /// metric strip, which is the only place a legacy run post recorded them.
  static ActivitySession _runSessionFromPost(FeedPost post, DateTime when) {
    final distanceKm = distanceFromMetricLabels(post.metricLabels);
    final duration =
        durationFromMetricLabels(post.metricLabels) ?? Duration.zero;
    // These posts predate the runs collection, so there is no activityType to
    // read — only the display label the share flow wrote. A legacy post says
    // 'Run', and anything unrecognised falls back to a run, which is what every
    // one of them is.
    final kind = _kindFromActivityLabel(post.activity);
    return ActivitySession(
      id: post.id,
      kind: kind,
      title: kind.descriptor.singular,
      startedAt: when,
      duration: duration,
      calories: estimatedActivityCalories(
        kind: kind,
        distanceKm: distanceKm,
        duration: duration,
      ),
      caloriesAreEstimated: true,
      distanceKm: distanceKm,
      sharedToFeed: true,
      postId: post.id,
    );
  }

  /// The activity kind behind a post's display label, e.g. "Hike" -> hike.
  ///
  /// Posts carry a human label rather than a wire value, because every reader
  /// of a post renders it directly. Unknown labels read as a run.
  static ActivityKind _kindFromActivityLabel(String? activity) {
    final label = activity?.trim().toLowerCase();
    if (label == null || label.isEmpty) return ActivityKind.run;
    for (final kind in ActivityKind.values) {
      if (kind.descriptor.singular.toLowerCase() == label) return kind;
    }
    return ActivityKind.run;
  }

  /// A workout post as a session, read out of the workoutData map the share
  /// flow denormalised onto it.
  static ActivitySession _workoutSessionFromPost(FeedPost post, DateTime when) {
    final data = post.workoutData ?? const <String, dynamic>{};
    final exercises = data['exercises'];

    return ActivitySession(
      id: post.id,
      kind: ActivityKind.workout,
      title: _text(data['title']) ?? _text(post.activity) ?? 'Workout',
      startedAt: when,
      duration: Duration(
        minutes: minutesFromDurationLabel(data['duration'] as String?),
      ),
      calories: kcalFromLabel(data['calories'] as String?),
      exerciseCount: exercises is List ? exercises.length : null,
      sharedToFeed: true,
      postId: post.id,
    );
  }

  /// A run document as a session, or null when it carries no usable date.
  ///
  /// `startedAt` is preferred over `createdAt`: it is the client-side stamp
  /// for when the run actually happened, in the user's own timezone, which is
  /// the day it should count towards. `createdAt` is the server's write time
  /// and only stands in when there is no better answer.
  static ActivitySession? _toRunSession(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final startedAt = _firstTimestamp(data, const ['startedAt', 'createdAt']);
    if (startedAt == null) return null;

    final distanceKm = doubleFromStoredValue(data['distanceKm']);
    final duration =
        Duration(seconds: intFromStoredValue(data['durationSeconds']));
    // Absent means run: every document written before the field existed.
    final kind = ActivityKindX.fromWire(data['activityType']);
    return ActivitySession(
      id: doc.id,
      kind: kind,
      title: kind.descriptor.singular,
      startedAt: startedAt,
      duration: duration,
      calories: estimatedActivityCalories(
        kind: kind,
        distanceKm: distanceKm,
        duration: duration,
      ),
      caloriesAreEstimated: true,
      distanceKm: distanceKm,
      sharedToFeed: boolFromStoredValue(data['sharedToFeed']),
      postId: _text(data['postId']),
      heartRate: HeartRateSummary.fromMap(data['heartRate']),
    );
  }

  /// A workout document as a session, or null when it carries no usable date.
  ///
  /// Duration falls back to parsing the "45 min" label for workouts logged
  /// before the numeric field existed; calories simply read as zero on those,
  /// because nothing was ever captured to recover.
  static ActivitySession? _toWorkoutSession(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final startedAt = _firstTimestamp(data, const ['loggedAt', 'createdAt']);
    if (startedAt == null) return null;

    // Both fields have lived as numbers and as display strings ("45 min",
    // "0 kcal"), and both shapes are still in the collection — see
    // [intFromStoredValue]. `durationMinutes` is preferred where it exists
    // because it is the exact figure; `duration` is the label to fall back to.
    final minutes = data.containsKey('durationMinutes')
        ? intFromStoredValue(data['durationMinutes'])
        : intFromStoredValue(data['duration']);

    return ActivitySession(
      id: doc.id,
      kind: ActivityKind.workout,
      title: _text(data['title']) ?? 'Workout',
      startedAt: startedAt,
      duration: Duration(minutes: minutes),
      calories: intFromStoredValue(data['calories']),
      exerciseCount: data.containsKey('exerciseCount')
          ? intFromStoredValue(data['exerciseCount'])
          : null,
      sharedToFeed: boolFromStoredValue(data['sharedToFeed']),
      postId: _text(data['postId']),
      // Always null today — nothing writes it. Read anyway so a session carries
      // one meaning whichever collection it came out of, and any display code
      // is written once.
      heartRate: HeartRateSummary.fromMap(data['heartRate']),
    );
  }

  @override
  Future<int> getWeeklyGoalDays() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return FirestoreUserRecord.defaultWeeklyGoalDays;
    try {
      return (await _loadUserRecord()).weeklyGoalDays;
    } catch (error) {
      // The goal is only a denominator; falling back to the default beats
      // failing the whole overview card over an unreadable profile.
      debugPrint('Weekly goal unavailable ($error) — using default.');
      return FirestoreUserRecord.defaultWeeklyGoalDays;
    }
  }

  @override
  Future<void> deleteActivitySession(String id, ActivityKind kind) async {
    _requireCurrentUser();
    // Keyed on workout, not on run. Every GPS kind — run, hike and ride — lives
    // in `runs`, so a `== run ? runs : workouts` test would send a hike to the
    // workouts collection and delete nothing at all: the row would vanish from
    // the list and the document would still be there on the next read.
    final collection = kind == ActivityKind.workout
        ? workoutsCollection
        : runsCollection;
    await collection.doc(id).delete();
  }

  @override
  Future<void> setWeeklyGoalDays(int days) async {
    final user = _requireCurrentUser();
    await usersCollection.doc(user.uid).set(
      {'weeklyGoalDays': days.clamp(1, 7)},
      SetOptions(merge: true),
    );
  }

  /// Maps [docs] with [toSession], dropping any that cannot be read.
  ///
  /// Per document rather than per collection: these documents span every
  /// schema this app has ever written, and one that does not parse must cost
  /// its own row and nothing else. Mapping the list as a whole is what let a
  /// single stale document fail the entire Progress tab.
  /// Maps documents one at a time, dropping any that cannot be read.
  ///
  /// Generic over what it produces so meals go through the same isolation the
  /// sessions do. The isolation is the point: a single malformed document
  /// costs its own row rather than failing the whole read, which is what used
  /// to take the grid, the streak and the Progress tab down together.
  static List<T> _mapDocs<T extends Object>(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    T? Function(QueryDocumentSnapshot<Map<String, dynamic>>) toItem,
  ) {
    final items = <T>[];
    for (final doc in docs) {
      try {
        final item = toItem(doc);
        if (item != null) items.add(item);
      } catch (error) {
        debugPrint('Progress: skipping ${doc.reference.path} — $error');
      }
    }
    return items;
  }

  /// A trimmed string field, or null when it is absent or blank.
  ///
  /// A stored empty string and a missing key mean the same thing here — no
  /// title, no linked post — and callers should not have to tell them apart.
  static String? _text(Object? value) {
    final text = (value as String?)?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// The first of [fields] holding a `Timestamp`, as local time.
  static DateTime? _firstTimestamp(
    Map<String, dynamic> data,
    List<String> fields,
  ) {
    for (final field in fields) {
      final value = data[field];
      // Timestamp.toDate() returns local time, so the day boundary is the
      // user's own midnight rather than UTC's.
      if (value is Timestamp) return value.toDate();
    }
    return null;
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
    } catch (error) {
      // Every failure, not just FirebaseException: a read that throws anything
      // at all should cost this collection's rows and nothing else.
      debugPrint(
        'Progress: could not read ${collection.id} ($error) — those sessions '
        'will be missing.',
      );
      return const [];
    }
  }

  CollectionReference<Map<String, dynamic>> get usersCollection =>
      _firestore.collection('users');

  /// Username reservations, keyed by the normalized name itself. This is the
  /// only mapping from `@handle` to a uid — see domain/username.dart.
  CollectionReference<Map<String, dynamic>> get usernamesCollection =>
      _firestore.collection('usernames');

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
    // Uploaded before anything is written, so both the log and the post can
    // carry the same URL. A failed upload costs the backdrop and nothing else —
    // the workout still saves, and the card falls back to its gradient.
    final backgroundUrl = await _tryUploadBackground(draft.backgroundImagePath);

    // Written whether or not the workout is shared, mirroring saveRun: the log
    // is the canonical record, and the Progress tab reads from it. Sharing
    // only decides whether a post is created alongside it.
    final logRef = await _tryWriteLog(
      'workout',
      () => _writeWorkoutLog(draft, backgroundUrl),
    );

    if (!draft.shareToFeed) {
      await _incrementUser(workoutsDelta: 1);
      return const ActivitySaveResult(message: 'Workout saved.');
    }

    // Create the post first, then increment. Incrementing up front means a
    // failed post write still inflates the user's workout count.
    final result = await _createPost(
      profile: profile,
      activity: draft.title.trim().isEmpty ? 'Workout' : draft.title.trim(),
      caption: draft.notes.trim().isEmpty
          ? 'Logged ${draft.exercises.length} exercises.'
          : draft.notes.trim(),
      metricLabels: [
        draft.durationLabel,
        draft.caloriesLabel,
        '${draft.exercises.length} moves'
      ],
      themeKey: 'burn',
      postType: 'workout',
      imageUrl: backgroundUrl,
      workoutData: {
        'title': draft.title.trim().isEmpty ? 'Workout' : draft.title.trim(),
        'duration': draft.durationLabel,
        'calories': draft.caloriesLabel,
        'exercises': draft.exercises.map((e) => e.toMap()).toList(),
      },
    );
    await _linkLogToPost(logRef, result.post.id);
    await _incrementUser(workoutsDelta: 1);
    return ActivitySaveResult(
      message: _sharedMessage('Workout', synced: result.synced),
      createdPost: result.post,
    );
  }

  /// What to tell the user after a share.
  ///
  /// A post that has not reached the server yet is still saved — it is in the
  /// local cache and the SDK will send it. Saying "shared" outright would be a
  /// small lie to anyone who logged a session out of signal and then wondered
  /// why nobody saw it.
  static String _sharedMessage(String noun, {required bool synced}) {
    return synced
        ? '$noun saved and shared.'
        : "$noun saved. It'll share once you're back online.";
  }

  /// How long to wait for a write to be acknowledged by the server before
  /// carrying on without it.
  ///
  /// Long enough that a slow-but-working connection is simply waited out, short
  /// enough that a user with no signal is not left staring at a spinner.
  static const Duration _writeSettleTimeout = Duration(seconds: 6);

  /// Awaits [write] up to [_writeSettleTimeout], reporting whether it landed.
  ///
  /// Firestore write futures complete on *server* acknowledgement, not on the
  /// local one — offline they never complete at all. That is the whole reason
  /// this exists: every save in here awaited its write, so logging a workout
  /// out of signal spun forever and the session appeared to be lost.
  ///
  /// Giving up on the wait does not give up on the write. The document is
  /// already in the local cache, reads see it immediately, and the SDK sends it
  /// when the connection returns. A false return means "not yet", not "failed"
  /// — which is why the caller changes its wording rather than its behaviour.
  ///
  /// Real failures still throw: only the waiting is bounded, never the error.
  Future<bool> _settleWrite(Future<void> write) async {
    try {
      await write.timeout(_writeSettleTimeout);
      return true;
    } on TimeoutException {
      // Nothing is awaiting the original future any more, so an error arriving
      // on it later would surface as an unhandled async error and crash debug
      // builds. Observe and drop it — there is no longer anyone to tell.
      unawaited(write.catchError((Object _) {}));
      return false;
    }
  }

  /// Runs [write], returning null rather than throwing if it fails.
  ///
  /// A log is a secondary record. What the user actually asked for is the
  /// session saved, the counter moved and — if they said so — the post
  /// shared. An unwritable log collection (undeployed security rules being
  /// the usual cause) must cost the Progress tab a row, never the save
  /// itself. Awaiting these unguarded is what took every workout, run and
  /// meal down with it.
  Future<DocumentReference<Map<String, dynamic>>?> _tryWriteLog(
    String label,
    Future<DocumentReference<Map<String, dynamic>>> Function() write,
  ) async {
    try {
      return await write();
    } catch (error) {
      debugPrint(
        'Could not write the $label log ($error). The save itself went '
        'through — deploy firestore.rules so sessions are recorded for '
        'Progress.',
      );
      return null;
    }
  }

  /// Points a saved log at the post it produced.
  ///
  /// A separate write rather than part of the original set: the log has to
  /// exist whether or not the post does, so it is written first and the id is
  /// added once there is one. A null ref means the log was never written; a
  /// failure here costs the Progress tab's link through to the post, not the
  /// record of the session.
  Future<void> _linkLogToPost(
    DocumentReference<Map<String, dynamic>>? logRef,
    String postId,
  ) async {
    if (logRef == null) return;
    try {
      // Bounded for the same reason every other write here is: an update
      // completes on *server* acknowledgement, so offline this never returns
      // and never throws either. Awaiting it unguarded hung the whole save
      // after the post had already been created — spinner on screen, no toast,
      // no navigation, and the run looking lost when it was only unsent.
      await _settleWrite(logRef.update({'postId': postId}));
    } on FirebaseException catch (error) {
      debugPrint('Could not link ${logRef.path} to post $postId: '
          '${error.code}');
    }
  }

  @override
  Future<ActivitySaveResult> saveRun(
    UserProfileDraft? profile,
    RunLogDraft draft,
  ) async {
    // Uploaded before anything is written, so both the log and the post can
    // carry the same URL — same order, and the same reasoning, as saveWorkout.
    final backgroundUrl = await _tryUploadBackground(draft.backgroundImagePath);
    final noun = draft.activityKind.descriptor.singular;

    // Only a run may move the longest-run record. maxRunDistanceKm is a
    // monotone max — written when it is greater and never otherwise — so one
    // 60 km ride would claim "Longest Run: 60 km" permanently, and no amount
    // of running afterwards could take it back.
    final recordDistanceKm =
        draft.activityKind == ActivityKind.run ? draft.distanceKm : null;

    // The run log is the canonical record and is written whether or not the
    // run is shared, so an unshared GPS run still keeps its route.
    final route = _serializeRoute(draft.routePoints);
    final logRef = await _tryWriteLog(
      'run',
      () => _writeRunLog(draft, route, backgroundUrl),
    );

    if (!draft.shareToFeed) {
      await _incrementUser(runsDelta: 1, runDistanceKm: recordDistanceKm);
      return ActivitySaveResult(message: '$noun saved.');
    }

    final result = await _createPost(
      profile: profile,
      // The post's one record of which activity this was. Every renderer
      // already prints this field, so naming it correctly here is what makes a
      // hike read as a hike everywhere it appears — and it is what
      // _kindFromActivityLabel reads back when a post is the only trace left.
      activity: noun,
      caption: 'Finished a ${draft.distanceKm.toStringAsFixed(2)} km '
          '${noun.toLowerCase()}.',
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
      // The backdrop the run card draws its line and its numbers on. Like a
      // workout's, it is decoration on the session rather than a photo post —
      // the renderers decide that from the post type, not from this field.
      imageUrl: backgroundUrl,
      // Denormalised onto the post so the feed renders the route from the
      // documents it already streams, with no extra read per card.
      routePoints: route,
    );
    await _linkLogToPost(logRef, result.post.id);
    await _incrementUser(runsDelta: 1, runDistanceKm: recordDistanceKm);
    return ActivitySaveResult(
      message: _sharedMessage(noun, synced: result.synced),
      createdPost: result.post,
    );
  }

  /// Persists the workout to `workouts/{id}` — what was done and when.
  ///
  /// `loggedAt` is stamped client-side so the day bucket reflects the user's
  /// own clock; `createdAt` stays a server timestamp for ordering.
  ///
  /// Duration and calories are written as numbers. They are also written as
  /// the labels the feed shows, because the post carries those strings and the
  /// two should not be re-derived differently in two places.
  /// Uploads a session's chosen backdrop, or returns null if there isn't one
  /// or it didn't make it.
  ///
  /// Swallowing the error is deliberate, and matches [_tryWriteLog]: the user
  /// asked for a session to be saved. Losing the whole thing because a photo
  /// upload timed out on bad signal is the wrong trade — the session is the
  /// thing, the picture is decoration.
  Future<String?> _tryUploadBackground(String? path) async {
    if (path == null) return null;

    try {
      final user = _requireCurrentUser();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return await _uploadJpeg(
        'posts/${user.uid}/$timestamp.jpg',
        path,
        // Its own, shorter bound rather than uploadPostImage's: the result is
        // discarded on failure, so there is nothing to be gained by waiting a
        // full minute for it.
        timeout: _backgroundUploadTimeout,
      );
    } catch (error, stackTrace) {
      debugPrint('Background upload failed: $error\n$stackTrace');
      return null;
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> _writeWorkoutLog(
    WorkoutLogDraft draft,
    String? backgroundUrl,
  ) async {
    final user = _requireCurrentUser();
    final title = draft.title.trim();
    final ref = workoutsCollection.doc();
    await _settleWrite(ref.set({
      'authorId': user.uid,
      'title': title.isEmpty ? 'Workout' : title,
      'durationMinutes': draft.durationMinutes,
      'calories': draft.calories,
      'duration': draft.durationLabel,
      'caloriesLabel': draft.caloriesLabel,
      'exerciseCount': draft.exercises.length,
      'sharedToFeed': draft.shareToFeed,
      if (backgroundUrl != null) 'imageUrl': backgroundUrl,
      'loggedAt': Timestamp.now(),
      'createdAt': FieldValue.serverTimestamp(),
    }));
    return ref;
  }

  /// Persists the run to `runs/{id}` — distance, timings and the GPS trace.
  ///
  /// No calories field: a run's energy cost is worked out from its distance on
  /// read (see [estimatedRunCalories]), so it is not frozen into the document
  /// and every run already logged gets one too.
  Future<DocumentReference<Map<String, dynamic>>> _writeRunLog(
    RunLogDraft draft,
    List<Map<String, double>> route,
    String? backgroundUrl,
  ) async {
    final user = _requireCurrentUser();
    final ref = runsCollection.doc();
    await _settleWrite(ref.set({
      'authorId': user.uid,
      'distanceKm': draft.distanceKm,
      'durationSeconds': draft.elapsed.inSeconds,
      'averagePace': draft.averagePace,
      'routePoints': route,
      'pointCount': route.length,
      'sharedToFeed': draft.shareToFeed,
      // Omitted for a run, so a run document written today is shaped exactly
      // like every run written before hikes and rides existed. That is what
      // lets "no activityType" mean "run" everywhere it is read — on the
      // client, and in the two Cloud Functions that score challenges — with
      // nothing backfilled and no historical document touched.
      if (draft.activityKind != ActivityKind.run)
        'activityType': draft.activityKind.wireName,
      // Omitted when nothing measured it, so a manually entered session is not
      // recorded as a flat one. Purely additive: no index, no rules change, and
      // nothing in the challenge functions reads it.
      if (draft.elevationGainMeters case final gain?)
        'elevationGainMeters': gain,
      if (backgroundUrl != null) 'imageUrl': backgroundUrl,
      // Omitted rather than written as zeros when no strap was connected, so a
      // run without one is shaped exactly like every run logged before straps
      // were recorded and nothing needs migrating.
      if (draft.heartRate case final hr? when hr.hasData) 'heartRate': hr.toMap(),
      if (draft.startedAt != null)
        'startedAt': Timestamp.fromDate(draft.startedAt!),
      'createdAt': FieldValue.serverTimestamp(),
    }));
    return ref;
  }

  @override
  Future<ActivitySaveResult> saveMeal(
    UserProfileDraft? profile,
    MealLogDraft draft,
  ) async {
    // The ref is kept now, where runs and workouts always kept theirs. Meals
    // were the one log type whose post was never linked back, so a shared meal
    // had no way to reach the post it created — which the tracking list needs
    // to make its rows openable.
    final logRef = await _tryWriteLog('meal', () => _writeMealLog(draft));

    if (!draft.shareToFeed) {
      await _incrementUser(mealsDelta: 1);
      return const ActivitySaveResult(message: 'Meal saved.');
    }

    final result = await _createPost(
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
    await _linkLogToPost(logRef, result.post.id);
    await _incrementUser(mealsDelta: 1);
    return ActivitySaveResult(
      message: _sharedMessage('Meal', synced: result.synced),
      createdPost: result.post,
    );
  }

  @override
  Future<ActivitySaveResult> sharePost(
    UserProfileDraft? profile,
    PostDraft draft,
  ) async {
    final caption = draft.caption.trim();
    final result = await _createPost(
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
      taggedUsers: draft.taggedUsers,
    );
    return ActivitySaveResult(
      message: result.synced
          ? 'Post shared.'
          : "Post saved. It'll share once you're back online.",
      createdPost: result.post,
    );
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

  /// Creates the post document and returns it, along with whether the write
  /// reached the server before [_settleWrite] stopped waiting.
  ///
  /// `synced: false` is not a failure — the post is in the local cache, shows
  /// in the feed, and uploads itself when the connection returns. It only
  /// changes what the user is told.
  Future<({FeedPost post, bool synced})> _createPost({
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
    List<TaggedUser> taggedUsers = const [],
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
      // The author can't tag themselves — their name is already on the post —
      // and a duplicate entry would draw the same chip twice.
      taggedUsers: _dedupeTags(taggedUsers, userId),
      // Local clock, only for the copy handed straight back to the feed — the
      // stored value is the server timestamp written below.
      createdAt: DateTime.now(),
    );

    final taggedIds =
        record.taggedUsers.map((tagged) => tagged.id).toList(growable: false);
    // Anyone already tagged is skipped: being tagged and named in the same
    // caption is one event to the person on the other end, and the tag is the
    // more deliberate of the two.
    final mentioned = (await _resolveMentionRecipients(caption, userId))
        .where((uid) => !taggedIds.contains(uid))
        .toList(growable: false);

    final synced = await _settleWrite(document.set({
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
      if (record.taggedUsers.isNotEmpty)
        'taggedUsers': record.taggedUsers
            .map((tagged) => tagged.toMap())
            .toList(growable: false),
      // The flat uid list is the queryable half of the same fact — "posts I am
      // tagged in" is an array-contains away, which a list of maps is not.
      if (taggedIds.isNotEmpty) 'taggedUserIds': taggedIds,
      if (mentioned.isNotEmpty) 'mentionedUserIds': mentioned,
      'createdAt': FieldValue.serverTimestamp(),
    }));
    await _incrementUser(postsDelta: 1);
    await _notifyPostAudience(
      postId: document.id,
      actorId: userId,
      actorName: authorName,
      actorAvatarUrl: authorAvatarUrl,
      postImageUrl: imageUrl,
      postType: postType,
      taggedIds: taggedIds,
      mentionedIds: mentioned,
    );

    return (post: FirestoreMapper.toFeedPost(record), synced: synced);
  }

  /// [tags] with the author and any repeats removed.
  static List<TaggedUser> _dedupeTags(List<TaggedUser> tags, String authorId) {
    final seen = <String>{authorId};
    final kept = <TaggedUser>[];
    for (final tagged in tags) {
      if (!seen.add(tagged.id)) continue;
      kept.add(tagged);
      if (kept.length >= maxMentionsPerItem) break;
    }
    return kept;
  }

  /// Tells the people a new post names that it names them.
  ///
  /// Deliberately after the post itself rather than batched with it: the post
  /// is the thing the user asked for, and a notification that fails must not
  /// take the post down with it. A swallowed failure costs an alert, which is
  /// recoverable — the post is on the tagged user's feed either way.
  Future<void> _notifyPostAudience({
    required String postId,
    required String actorId,
    required String actorName,
    required List<String> taggedIds,
    required List<String> mentionedIds,
    String? actorAvatarUrl,
    String? postImageUrl,
    String? postType,
  }) async {
    if (taggedIds.isEmpty && mentionedIds.isEmpty) return;

    try {
      final batch = _firestore.batch();
      for (final recipientId in taggedIds) {
        batch.set(
          _notifications.ref(recipientId, NotificationIds.tag(postId, actorId)),
          _notifications.tagPayload(
            actorId: actorId,
            actorName: actorName,
            actorAvatarUrl: actorAvatarUrl,
            postId: postId,
            postImageUrl: postImageUrl,
            postType: postType,
          ),
        );
      }
      for (final recipientId in mentionedIds) {
        batch.set(
          _notifications.ref(
            recipientId,
            NotificationIds.mention(postId, actorId),
          ),
          _notifications.mentionPayload(
            actorId: actorId,
            actorName: actorName,
            actorAvatarUrl: actorAvatarUrl,
            postId: postId,
            postImageUrl: postImageUrl,
            postType: postType,
          ),
        );
      }
      // Bounded like every other write: a commit lands on server
      // acknowledgement, so offline it neither completes nor errors and this
      // catch never runs. The batch is in the cache and goes out with
      // everything else — waiting on it only held the post up.
      await _settleWrite(batch.commit());
    } catch (error) {
      debugPrint('Post $postId saved, but its mentions were not sent: $error');
    }
  }

  /// Works out the streak that follows [data]'s stored one.
  ///
  /// Same-day logs don't extend the streak; a gap of more than one day resets
  /// it to today's single day.
  static int _nextStreak(Map<String, dynamic> data, DateTime now) {
    final today = _dayStamp(now);
    final yesterday = _dayStamp(ActivityCalendar.addDays(now, -1));
    final lastActivityDay = data['lastActivityDay'] as String?;
    final storedStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;

    if (lastActivityDay == today) return storedStreak < 1 ? 1 : storedStreak;
    if (lastActivityDay == yesterday) return storedStreak + 1;
    return 1;
  }

  /// Applies activity counters and advances the daily streak.
  ///
  /// Runs inside a transaction because the streak has to be read before it can
  /// be extended, and a blind write would clobber a concurrent log.
  ///
  /// Transactions need the server, so this is the one part of a save that
  /// cannot work offline at all — it fails rather than queueing. When that
  /// happens the work falls through to [_incrementUserFromCache], which keeps
  /// the counters correct and settles for a locally-computed streak.
  Future<void> _incrementUser({
    int postsDelta = 0,
    int workoutsDelta = 0,
    int mealsDelta = 0,
    int runsDelta = 0,
    double? runDistanceKm,
  }) async {
    final user = _requireCurrentUser();
    final documentRef = usersCollection.doc(user.uid);

    try {
      await _incrementUserInTransaction(
        documentRef,
        postsDelta: postsDelta,
        workoutsDelta: workoutsDelta,
        mealsDelta: mealsDelta,
        runsDelta: runsDelta,
        runDistanceKm: runDistanceKm,
      ).timeout(_writeSettleTimeout);
    } catch (error) {
      debugPrint('Counter transaction unavailable ($error); writing locally.');
      await _incrementUserFromCache(
        documentRef,
        postsDelta: postsDelta,
        workoutsDelta: workoutsDelta,
        mealsDelta: mealsDelta,
        runsDelta: runsDelta,
        runDistanceKm: runDistanceKm,
      );
    }
  }

  Future<void> _incrementUserInTransaction(
    DocumentReference<Map<String, dynamic>> documentRef, {
    required int postsDelta,
    required int workoutsDelta,
    required int mealsDelta,
    required int runsDelta,
    required double? runDistanceKm,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(documentRef);
      final data = snapshot.data() ?? const <String, dynamic>{};

      final now = DateTime.now();
      final today = _dayStamp(now);
      final streak = _nextStreak(data, now);

      final storedMaxRunKm =
          (data['maxRunDistanceKm'] as num?)?.toDouble() ?? 0;

      transaction.set(
          documentRef,
          {
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
          },
          SetOptions(merge: true));
    });
  }

  /// The offline path for [_incrementUser]: a plain merge write off the cached
  /// profile.
  ///
  /// The counters stay exactly as correct as the transactional path, because
  /// [FieldValue.increment] is applied by the server against whatever the
  /// document holds when the write finally lands — not against the value read
  /// here. Two sessions logged on a flight both count.
  ///
  /// The streak is the part that gives ground: it is derived from the cached
  /// document, which may be stale, and it is a plain value rather than an
  /// atomic op. Worst case it is a day out until the next log made online
  /// recomputes it from the server's copy. A streak that self-corrects beats a
  /// session that was never recorded.
  Future<void> _incrementUserFromCache(
    DocumentReference<Map<String, dynamic>> documentRef, {
    required int postsDelta,
    required int workoutsDelta,
    required int mealsDelta,
    required int runsDelta,
    required double? runDistanceKm,
  }) async {
    Map<String, dynamic> cached;
    try {
      final snapshot =
          await documentRef.get(const GetOptions(source: Source.cache));
      cached = snapshot.data() ?? const <String, dynamic>{};
    } catch (_) {
      // Nothing cached — a first run on a fresh install, offline. Treat it as
      // an empty profile, which starts the streak at one.
      cached = const <String, dynamic>{};
    }

    final now = DateTime.now();
    final storedMaxRunKm =
        (cached['maxRunDistanceKm'] as num?)?.toDouble() ?? 0;

    await _settleWrite(
      documentRef.set(
        {
          if (postsDelta != 0) 'postsCount': FieldValue.increment(postsDelta),
          if (workoutsDelta != 0)
            'workoutsCount': FieldValue.increment(workoutsDelta),
          if (mealsDelta != 0) 'mealsCount': FieldValue.increment(mealsDelta),
          if (runsDelta != 0) 'runsCount': FieldValue.increment(runsDelta),
          if (runDistanceKm != null && runDistanceKm > storedMaxRunKm)
            'maxRunDistanceKm': runDistanceKm,
          'currentStreak': _nextStreak(cached, now),
          'lastActivityDay': _dayStamp(now),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ),
    );
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
        lastActivityDay == _dayStamp(ActivityCalendar.addDays(now, -1));
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
  Future<void> setPostReaction(
    String postId,
    String userId,
    FitReaction? reaction, {
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

      final data = postSnapshot.data() ?? {};
      // likedBy remains the roll of everyone who has reacted — the field kept
      // its name when the Like button became the reaction control, because the
      // people it names did not change.
      final likedBy = List<String>.from(
        (data['likedBy'] as List<dynamic>?) ?? [],
      );

      // What they were holding before this write. A like cast before reactions
      // existed has a like document but no reaction key, and reads as the
      // default — so switching away from it decrements the right counter.
      final storedPrevious = likeSnapshot.exists
          ? FitReaction.fromKey(likeSnapshot.data()?['reaction'] as String?)
          : null;
      final previous = likeSnapshot.exists
          ? (storedPrevious ?? FitReaction.defaultReaction)
          : null;

      // Picking what you already hold is not an event. Bailing here is what
      // makes a double tap harmless rather than a double count.
      if (previous == reaction) return;

      // Nobody is told about their own reaction.
      final authorId = (data['authorId'] as String?) ?? '';
      final notificationRef = (authorId.isEmpty || authorId == userId)
          ? null
          : _notifications.ref(
              authorId,
              NotificationIds.like(postId, userId),
            );

      // The total moves only when someone joins or leaves; swapping one
      // reaction for another leaves it where it is.
      final totalDelta =
          (reaction == null ? 0 : 1) - (previous == null ? 0 : 1);

      if (reaction == null) {
        likedBy.remove(userId);
        transaction.delete(likeRef);
      } else {
        if (!likedBy.contains(userId)) likedBy.add(userId);
        transaction.set(likeRef, {
          'reaction': reaction.key,
          'likedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.update(postRef, {
        'likedBy': likedBy,
        if (totalDelta != 0) 'likesCount': FieldValue.increment(totalDelta),
        // Dotted paths, so the two counters move inside one map without this
        // client having to read and rewrite the whole thing.
        if (previous != null)
          'reactionCounts.${previous.key}': FieldValue.increment(-1),
        if (reaction != null)
          'reactionCounts.${reaction.key}': FieldValue.increment(1),
        if (reaction == null)
          'reactionsBy.$userId': FieldValue.delete()
        else
          'reactionsBy.$userId': reaction.key,
      });

      if (notificationRef != null) {
        if (reaction == null) {
          // Taking the reaction back takes the notification with it.
          transaction.delete(notificationRef);
        } else {
          // Written whole rather than patched, so changing your reaction
          // refreshes the row's timestamp and lifts it back to the top —
          // the author should see the change, not just the first version.
          transaction.set(
            notificationRef,
            _notifications.reactionPayload(
              actorId: userId,
              actorName: actorName,
              actorAvatarUrl: actorAvatarUrl,
              postId: postId,
              reaction: reaction,
              // Carried onto the notification so the row can show what was
              // reacted to without reading the post back.
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

    return _withLiveCommentAuthors(
      snapshot.docs
          .map((doc) => FirestoreCommentRecord.fromMap(doc.id, doc.data()))
          .map(FirestoreMapper.toComment)
          .toList(),
    );
  }

  @override
  Future<Comment> addComment(
    UserProfileDraft? profile,
    String postId,
    String text, {
    String? parentCommentId,
  }) async {
    final user = _requireCurrentUser();
    final authorName = await _resolvePublicAuthorName(profile);
    final authorAvatarUrl = await _resolveAuthorAvatarUrl(profile);
    final comments = postsCollection.doc(postId).collection('comments');
    final commentRef = comments.doc();

    // Resolved before the batch opens, because turning `@handle` into a uid is
    // a read and a batch may not read. The notifications themselves then ride
    // in the same commit as the comment: a mention nobody was told about is a
    // mention that did not happen.
    final mentioned = await _resolveMentionRecipients(text, user.uid);

    // Everyone the comment itself has to tell, for the same reason and read
    // the same way up front: the post's author, and — on a reply — the author
    // of the comment being answered.
    final postSnapshot = await postsCollection.doc(postId).get();
    final postData = postSnapshot.data() ?? const <String, dynamic>{};
    final parentAuthorId = parentCommentId == null
        ? ''
        : await _commentAuthorId(comments, parentCommentId);

    final recipients = commentNotificationAudience(
      actorId: user.uid,
      postAuthorId: (postData['authorId'] as String?) ?? '',
      parentAuthorId: parentAuthorId,
      mentioned: mentioned.toSet(),
    );

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
      // The comment this one answers. Written only when there is one, so a
      // top-level comment stays exactly the document it has always been.
      if (parentCommentId != null && parentCommentId.isNotEmpty)
        'parentCommentId': parentCommentId,
      // Stored as an index for the notifications above, never as the source of
      // truth for what the comment says — the links are re-parsed from `text`
      // on every render, so the two can't drift.
      if (mentioned.isNotEmpty) 'mentionedUserIds': mentioned,
      'createdAt': FieldValue.serverTimestamp(),
    });
    for (final recipientId in mentioned) {
      batch.set(
        _notifications.ref(
          recipientId,
          NotificationIds.mention(commentRef.id, user.uid),
        ),
        _notifications.mentionPayload(
          actorId: user.uid,
          actorName: authorName,
          actorAvatarUrl: authorAvatarUrl,
          postId: postId,
          commentId: commentRef.id,
        ),
      );
    }
    for (final entry in recipients.entries) {
      final isReply = entry.value;
      batch.set(
        _notifications.ref(
          entry.key,
          isReply
              ? NotificationIds.reply(commentRef.id)
              : NotificationIds.comment(commentRef.id),
        ),
        _notifications.commentPayload(
          actorId: user.uid,
          actorName: authorName,
          actorAvatarUrl: authorAvatarUrl,
          postId: postId,
          commentId: commentRef.id,
          isReply: isReply,
          // Carried onto the row so it can show what was commented on without
          // reading the post back, exactly as a reaction does.
          postImageUrl: postData['imageUrl'] as String?,
          postType: postData['postType'] as String?,
        ),
      );
    }
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
      parentId: parentCommentId,
    );
  }

  /// Who wrote [commentId], or empty when the comment has since been removed.
  Future<String> _commentAuthorId(
    CollectionReference<Map<String, dynamic>> comments,
    String commentId,
  ) async {
    if (commentId.isEmpty) return '';
    final snapshot = await comments.doc(commentId).get();
    return (snapshot.data()?['authorId'] as String?) ?? '';
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
    final bookmarkRef =
        usersCollection.doc(userId).collection('bookmarks').doc(postId);

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
  Stream<FitReaction?> watchPostReaction(String postId, String userId) {
    return _firestore
        .collection('likes')
        .doc(postId)
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      // The document existing is what says they reacted; the key says which.
      // A like cast before reactions has no key, and 🧡 is the honest reading
      // of it — falling through to null would make their own like vanish.
      return FitReaction.fromKey(snapshot.data()?['reaction'] as String?) ??
          FitReaction.defaultReaction;
    });
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
        // asyncMap rather than map: the overlay needs the identity cache,
        // which may have to read. Already-cached authors resolve without
        // awaiting anything, so the common case still emits immediately.
        .asyncMap((snapshot) => _withLiveCommentAuthors(
              snapshot.docs
                  .map(
                    (doc) => FirestoreCommentRecord.fromMap(doc.id, doc.data()),
                  )
                  .map(FirestoreMapper.toComment)
                  .toList(),
            ));
  }

  /// How long an image the user is actually posting gets to upload.
  ///
  /// Generous, because in a photo post the photo *is* the content — there is
  /// nothing worth saving without it, so waiting beats failing.
  static const Duration _imageUploadTimeout = Duration(seconds: 60);

  /// How long a session's backdrop gets.
  ///
  /// Much shorter, because the caller is [_tryUploadBackground] and it throws
  /// the result away on failure anyway. A 1080x1350 q80 JPEG is a few hundred
  /// kilobytes; twenty seconds without finishing it means the connection is
  /// not working, and every second past that is a spinner in front of someone
  /// who has already finished their run.
  static const Duration _backgroundUploadTimeout = Duration(seconds: 20);

  /// Uploads [localFilePath] as a JPEG to [path], giving up after [timeout].
  ///
  /// Shared by both public upload entry points so the byte-reading and the
  /// give-up behaviour are written once.
  Future<String> _uploadJpeg(
    String path,
    String localFilePath, {
    required Duration timeout,
  }) async {
    // Bytes rather than a dart:io File, so this works on every platform: on
    // mobile XFile reads the picked file, on web it fetches the blob: URL that
    // image_picker returns instead of a real path.
    final bytes = await XFile(localFilePath).readAsBytes();
    final uploadTask = FirebaseStorage.instance.ref().child(path).putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
    final snapshot = await uploadTask.timeout(
      timeout,
      onTimeout: () {
        // `timeout` abandons the future, it does not stop the work behind it.
        // Without this the Storage SDK keeps retrying an upload nobody is
        // waiting for, holding a connection while the user is on the next
        // screen.
        unawaited(uploadTask.cancel().catchError((Object _) => false));
        throw TimeoutException(
          'Image upload timed out after ${timeout.inSeconds} seconds.',
        );
      },
    );
    return await snapshot.ref.getDownloadURL();
  }

  @override
  Future<String> uploadMealImage(String localFilePath) {
    final user = _requireCurrentUser();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return _uploadJpeg(
      'meals/${user.uid}/$timestamp.jpg',
      localFilePath,
      timeout: _imageUploadTimeout,
    );
  }

  @override
  Future<String> uploadPostImage(String localFilePath) {
    final user = _requireCurrentUser();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return _uploadJpeg(
      'posts/${user.uid}/$timestamp.jpg',
      localFilePath,
      timeout: _imageUploadTimeout,
    );
  }

  @override
  Future<Map<String, dynamic>> analyzeMealImage(String imageUrl) async {
    final callable = appFunctions.httpsCallable(
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

    final callable = appFunctions.httpsCallable(
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
  Future<DocumentReference<Map<String, dynamic>>> _writeMealLog(
    MealLogDraft draft,
  ) async {
    final user = _requireCurrentUser();
    int macro(String value) =>
        int.tryParse(value.trim()) ??
        double.tryParse(value.trim())?.round() ??
        0;

    final ref = mealsCollection.doc();
    await _settleWrite(ref.set({
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
      // Stamped client-side, as workouts already are, so the meal lands in the
      // right day the moment it is written. `createdAt` is a server timestamp
      // and reads back as null until the write reaches the server — offline
      // that is never, which would leave the meal out of today's totals on the
      // very screen the user just logged it from.
      'loggedAt': Timestamp.now(),
      'createdAt': FieldValue.serverTimestamp(),
    }));
    return ref;
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
