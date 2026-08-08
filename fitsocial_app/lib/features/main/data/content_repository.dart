import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/app_models.dart';
import 'content_repository_contract.dart';
import 'firestore_content_repository.dart';

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirestoreContentRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredContentRepository();
});

class UnconfiguredContentRepository implements ContentRepository {
  const UnconfiguredContentRepository();

  @override
  Future<HomeFeed> getFeedPosts(UserProfileDraft? profile) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<ProgressMetric>> getProgressMetrics() async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<ActivityDay>> getActivityDays(DateTime from) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<ProfileStat>> getProfileStats(String userId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<UserSearchResult?> fetchUserProfile(String userId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<AchievementsData> fetchUserAchievements(String userId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<FeedPost?> fetchPost(String postId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<FeedPost>> fetchUserPosts(String userId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<FeedPost>> fetchUserMediaPosts(String userId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<UserSearchResult>> searchUsers(String query) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<FeedPost>> fetchTrendingPosts() async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> followUser(
    String currentUserId,
    String targetUserId, {
    UserProfileDraft? profile,
  }) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId) {
    return Stream.value(false);
  }

  @override
  Stream<Set<String>> watchFollowingIds(String userId) =>
      Stream.value(const {});

  @override
  Stream<bool> watchUserNotifications(
    String currentUserId,
    String targetUserId,
  ) {
    return Stream.value(false);
  }

  @override
  Future<void> setUserNotifications(
    String currentUserId,
    String targetUserId, {
    required bool enabled,
  }) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<ActivitySaveResult> saveWorkout(
    UserProfileDraft? profile,
    WorkoutLogDraft draft,
  ) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<ActivitySaveResult> saveRun(
    UserProfileDraft? profile,
    RunLogDraft draft,
  ) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<ActivitySaveResult> saveMeal(
    UserProfileDraft? profile,
    MealLogDraft draft,
  ) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<ActivitySaveResult> sharePost(
    UserProfileDraft? profile,
    PostDraft draft,
  ) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> deletePost(String postId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> toggleLike(
    String postId,
    String userId, {
    UserProfileDraft? profile,
  }) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<Comment>> getComments(String postId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<Comment> addComment(
    UserProfileDraft? profile,
    String postId,
    String text,
  ) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<String> uploadMealImage(String localFilePath) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<Map<String, dynamic>> analyzeMealImage(String imageUrl) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<FoodSearchResult>> searchFoods(String query) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<String> uploadPostImage(String localFilePath) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> toggleBookmark(String postId, String userId) {
    return Future.value();
  }

  @override
  Stream<bool> watchPostLikeStatus(String postId, String userId) {
    return Stream.value(false);
  }

  @override
  Stream<bool> watchBookmarkStatus(String postId, String userId) {
    return Stream.value(false);
  }

  @override
  Stream<List<Comment>> watchComments(String postId) {
    return const Stream.empty();
  }
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';
