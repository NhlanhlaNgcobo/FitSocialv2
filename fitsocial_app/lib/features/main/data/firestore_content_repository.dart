import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
    if (snapshot.docs.isEmpty) {
      return _seedPosts.map(FirestoreMapper.toFeedPost).toList();
    }

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
    if (snapshot.docs.isEmpty) {
      return _seedProgress.map(FirestoreMapper.toProgressMetric).toList();
    }

    return snapshot.docs
        .map((doc) => FirestoreProgressRecord.fromMap(doc.data()))
        .map(FirestoreMapper.toProgressMetric)
        .toList();
  }

  @override
  Future<List<WorkoutPlaylist>> getWorkoutPlaylists(
      WorkoutType workoutType) async {
    switch (workoutType) {
      case WorkoutType.strength:
        return const [
          WorkoutPlaylist(
            title: 'Heavy Sets SA',
            subtitle: 'Gym-ready energy for strength blocks',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.strength,
            durationLabel: '1h 18m',
            trackCount: 22,
            backgroundColors: [Color(0xFF53260C), Color(0xFF0F0F0F)],
          ),
          WorkoutPlaylist(
            title: 'Iron Focus',
            subtitle: 'Apple Music picks for controlled power output',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.strength,
            durationLabel: '56m',
            trackCount: 16,
            backgroundColors: [Color(0xFF2D1D1A), Color(0xFF090909)],
          ),
        ];
      case WorkoutType.cardio:
        return const [
          WorkoutPlaylist(
            title: 'Cardio Burn Loop',
            subtitle: 'High-engagement cardio momentum',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.cardio,
            durationLabel: '48m',
            trackCount: 14,
            backgroundColors: [Color(0xFF1F3540), Color(0xFF0B0B0B)],
          ),
          WorkoutPlaylist(
            title: 'Move Without Ads',
            subtitle: 'Apple Music mix for uninterrupted cardio',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.cardio,
            durationLabel: '1h 02m',
            trackCount: 19,
            backgroundColors: [Color(0xFF40301E), Color(0xFF0D0D0D)],
          ),
        ];
      case WorkoutType.hiit:
        return const [
          WorkoutPlaylist(
            title: 'HIIT Ignition',
            subtitle: 'Explosive interval music with fast transitions',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.hiit,
            durationLabel: '37m',
            trackCount: 12,
            backgroundColors: [Color(0xFF4C1C16), Color(0xFF111111)],
          ),
          WorkoutPlaylist(
            title: 'No-Skip Intervals',
            subtitle: 'Apple Music mix built for hard rounds',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.hiit,
            durationLabel: '43m',
            trackCount: 13,
            backgroundColors: [Color(0xFF4E2C12), Color(0xFF090909)],
          ),
        ];
      case WorkoutType.run:
        return const [
          WorkoutPlaylist(
            title: 'Sunrise Run Cape Town',
            subtitle: 'Consistent pacing for road and coastal runs',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.run,
            durationLabel: '1h 09m',
            trackCount: 21,
            backgroundColors: [Color(0xFF3F2C1A), Color(0xFF101010)],
          ),
          WorkoutPlaylist(
            title: 'Runners Flow',
            subtitle: 'Apple Music endurance blend for long sessions',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.run,
            durationLabel: '54m',
            trackCount: 17,
            backgroundColors: [Color(0xFF1F2F34), Color(0xFF0C0C0C)],
          ),
        ];
      case WorkoutType.yoga:
        return const [
          WorkoutPlaylist(
            title: 'Reset & Recover',
            subtitle: 'Calm recovery music for flexibility work',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.yoga,
            durationLabel: '42m',
            trackCount: 11,
            backgroundColors: [Color(0xFF213126), Color(0xFF0B0B0B)],
          ),
          WorkoutPlaylist(
            title: 'Deep Stretch',
            subtitle: 'Apple Music recovery set for slower sessions',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.yoga,
            durationLabel: '39m',
            trackCount: 10,
            backgroundColors: [Color(0xFF2B271E), Color(0xFF0A0A0A)],
          ),
        ];
    }
  }

  @override
  Future<List<PodcastRecommendation>> getPodcastRecommendations() async {
    return const [
      PodcastRecommendation(
        title: 'Mindset Reset',
        host: 'Lebo M.',
        provider: MusicProviderService.spotify,
        category: PodcastCategory.mindset,
        episodeTitle: 'How to stay consistent when motivation dips',
        durationLabel: '28m',
        backgroundColors: [Color(0xFF24322C), Color(0xFF0D0D0D)],
      ),
      PodcastRecommendation(
        title: 'Built With Discipline',
        host: 'Chris van Wyk',
        provider: MusicProviderService.appleMusic,
        category: PodcastCategory.discipline,
        episodeTitle: 'Training your habits before your body',
        durationLabel: '34m',
        backgroundColors: [Color(0xFF3E2A1E), Color(0xFF0D0D0D)],
      ),
      PodcastRecommendation(
        title: 'Recover Better',
        host: 'Dr. Naledi K.',
        provider: MusicProviderService.spotify,
        category: PodcastCategory.recovery,
        episodeTitle: 'Sleep, stress, and real progress',
        durationLabel: '22m',
        backgroundColors: [Color(0xFF22313D), Color(0xFF0C0C0C)],
      ),
      PodcastRecommendation(
        title: 'Growth Playbook',
        host: 'Aiden Rossouw',
        provider: MusicProviderService.appleMusic,
        category: PodcastCategory.business,
        episodeTitle: 'What self-improvement looks like off the gym floor',
        durationLabel: '31m',
        backgroundColors: [Color(0xFF3D241E), Color(0xFF0B0B0B)],
      ),
    ];
  }

  @override
  Future<List<StoryItem>> getStories(UserProfileDraft? profile) async {
    final currentUser = await _loadUserRecord();
    return [
      FirestoreMapper.toStoryItem(currentUser, isOwnStory: true),
      FirestoreMapper.toStoryItem(currentUser),
      FirestoreMapper.toStoryItem(
        const FirestoreUserRecord(
          id: 'lerato',
          displayName: 'Lerato K.',
          handle: '@leratok',
          bio: '',
          location: '',
          avatarUrl: null,
          followersCount: 0,
          followingCount: 0,
          postsCount: 0,
          workoutsCount: 0,
          mealsCount: 0,
        ),
      ),
      FirestoreMapper.toStoryItem(
        const FirestoreUserRecord(
          id: 'mike',
          displayName: 'Mike J.',
          handle: '@mikej',
          bio: '',
          location: '',
          avatarUrl: null,
          followersCount: 0,
          followingCount: 0,
          postsCount: 0,
          workoutsCount: 0,
          mealsCount: 0,
        ),
      ),
      FirestoreMapper.toStoryItem(
        const FirestoreUserRecord(
          id: 'zan',
          displayName: 'Zan N.',
          handle: '@zann',
          bio: '',
          location: '',
          avatarUrl: null,
          followersCount: 0,
          followingCount: 0,
          postsCount: 0,
          workoutsCount: 0,
          mealsCount: 0,
        ),
      ),
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
    final user = _firebaseAuth.currentUser;
    final userId = user?.uid ?? _seedUser.id;
    final snapshot = await usersCollection.doc(userId).get();
    if (!snapshot.exists) {
      if (user == null) return _seedUser;
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
    final user = _firebaseAuth.currentUser;
    final userId = user?.uid ?? _seedUser.id;
    final authorName = profile?.displayName ??
        user?.displayName ??
        user?.email ??
        _seedUser.displayName;
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
    final user = _firebaseAuth.currentUser;
    if (user == null) return;

    await usersCollection.doc(user.uid).set({
      if (postsDelta != 0) 'postsCount': FieldValue.increment(postsDelta),
      if (workoutsDelta != 0)
        'workoutsCount': FieldValue.increment(workoutsDelta),
      if (mealsDelta != 0) 'mealsCount': FieldValue.increment(mealsDelta),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static const FirestoreUserRecord _seedUser = FirestoreUserRecord(
    id: 'neo',
    displayName: 'Neo M.',
    handle: '@neomotion',
    bio: 'Running, lifting, and good food.',
    location: 'Johannesburg, SA',
    avatarUrl: null,
    followersCount: 256,
    followingCount: 180,
    postsCount: 32,
    workoutsCount: 4,
    mealsCount: 11,
  );

  static const List<FirestorePostRecord> _seedPosts = [
    FirestorePostRecord(
      id: 'post_1',
      authorId: 'neo',
      authorName: 'Neo M.',
      activity: 'Morning Run',
      caption: 'Great way to start the day.',
      metricLabels: ['5.02 km', '28:16', '05:37 /km'],
      likesCount: 124,
      commentsCount: 12,
      timestampLabel: '2h ago',
      themeKey: 'sunset',
    ),
    FirestorePostRecord(
      id: 'post_2',
      authorId: 'lerato',
      authorName: 'Lerato K.',
      activity: 'Push Day',
      caption: 'Consistency stacking up one session at a time.',
      metricLabels: ['52 min', '6 moves', '520 kcal'],
      likesCount: 87,
      commentsCount: 9,
      timestampLabel: '3h ago',
      themeKey: 'burn',
    ),
  ];

  static const List<FirestoreProgressRecord> _seedProgress = [
    FirestoreProgressRecord(
      label: 'Workouts',
      value: '12',
      delta: '+20% vs last 30 days',
      chartBars: [0.28, 0.55, 0.7, 0.48, 0.82, 0.62, 0.9, 0.58, 0.74],
    ),
    FirestoreProgressRecord(
      label: 'Calories Burned',
      value: '4,560 kcal',
      delta: '+15% vs last 30 days',
      chartBars: [0.2, 0.25, 0.4, 0.52, 0.45, 0.63, 0.78, 0.7, 0.88],
    ),
    FirestoreProgressRecord(
      label: 'Active Minutes',
      value: '1,980 min',
      delta: '+18% vs last 30 days',
      chartBars: [0.15, 0.34, 0.44, 0.39, 0.57, 0.52, 0.71, 0.69, 0.87],
    ),
  ];
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
