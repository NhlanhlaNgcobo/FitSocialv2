import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  @override
  Future<ActivitySaveResult> saveWorkout(
    UserProfileDraft? profile,
    WorkoutLogDraft draft,
  ) async {
    await _incrementUser(workoutsDelta: 1);
    if (!draft.shareToFeed) {
      return const ActivitySaveResult(message: 'Workout saved.');
    }

    final post = await _createPost(
      profile: profile,
      activity: draft.title.trim().isEmpty ? 'Workout' : draft.title.trim(),
      caption: 'Logged ${draft.exercises.length} exercises.',
      metricLabels: [
        draft.duration,
        draft.calories,
        '${draft.exercises.length} moves'
      ],
      themeKey: 'burn',
    );
    return ActivitySaveResult(
        message: 'Workout saved and shared.', createdPost: post);
  }

  @override
  Future<ActivitySaveResult> saveRun(
    UserProfileDraft? profile,
    RunLogDraft draft,
  ) async {
    await _incrementUser(workoutsDelta: 1);
    if (!draft.shareToFeed) {
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
    );
    return ActivitySaveResult(
        message: 'Run saved and shared.', createdPost: post);
  }

  @override
  Future<ActivitySaveResult> saveMeal(
    UserProfileDraft? profile,
    MealLogDraft draft,
  ) async {
    await _incrementUser(mealsDelta: 1);
    if (!draft.shareToFeed) {
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
    );
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
        displayName: user.displayName ?? user.email ?? 'FitSocial User',
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

  Future<FeedPost> _createPost({
    required UserProfileDraft? profile,
    required String activity,
    required String caption,
    required List<String> metricLabels,
    required String themeKey,
  }) async {
    final user = _requireCurrentUser();
    final userId = user.uid;
    final authorName = profile?.displayName ??
        user.displayName ??
        user.email ??
        'FitSocial User';
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
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _incrementUser(postsDelta: 1);

    return FirestoreMapper.toFeedPost(record);
  }

  Future<void> _incrementUser({
    int postsDelta = 0,
    int workoutsDelta = 0,
    int mealsDelta = 0,
  }) async {
    final user = _requireCurrentUser();

    await usersCollection.doc(user.uid).set({
      if (postsDelta != 0) 'postsCount': FieldValue.increment(postsDelta),
      if (workoutsDelta != 0)
        'workoutsCount': FieldValue.increment(workoutsDelta),
      if (mealsDelta != 0) 'mealsCount': FieldValue.increment(mealsDelta),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(postRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? {};
      final likedBy = List<String>.from(
        (data['likedBy'] as List<dynamic>?) ?? [],
      );

      if (likedBy.contains(userId)) {
        likedBy.remove(userId);
        transaction.update(postRef, {
          'likedBy': likedBy,
          'likesCount': FieldValue.increment(-1),
        });
      } else {
        likedBy.add(userId);
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
  Future<Comment> addComment(String postId, String text) async {
    final user = _requireCurrentUser();
    final authorName = user.displayName ?? user.email ?? 'FitSocial User';
    final commentRef = postsCollection.doc(postId).collection('comments').doc();

    final now = DateTime.now();
    await commentRef.set({
      'authorId': user.uid,
      'authorName': authorName,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Increment comment count on the post
    await postsCollection.doc(postId).update({
      'commentsCount': FieldValue.increment(1),
    });

    return Comment(
      id: commentRef.id,
      authorId: user.uid,
      authorName: authorName,
      text: text,
      createdAt: now,
    );
  }
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
