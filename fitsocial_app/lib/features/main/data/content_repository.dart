import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../../../shared/reactions/fit_reaction.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/app_models.dart';
import '../domain/meal_tracking.dart';
import '../domain/progress_models.dart';
import 'content_repository_contract.dart';
import 'firestore_content_repository.dart';
import 'firestore_models.dart';

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
  Future<List<ActivitySession>> getActivitySessions() async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<LoggedMeal>> getLoggedMeals() async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<RecentWorkout>> getRecentWorkouts({int limit = 6}) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<MacroGoals> getMacroGoals() async => const MacroGoals();

  @override
  Future<void> setMacroGoals(MacroGoals goals) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> deleteLoggedMeal(String id) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<int> getWeeklyGoalDays() async =>
      FirestoreUserRecord.defaultWeeklyGoalDays;

  @override
  Future<void> setWeeklyGoalDays(int days) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> deleteActivitySession(String id, ActivityKind kind) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<ProfileStat>> getProfileStats(String userId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<UserSearchResult>> fetchFollowList(
    String userId,
    FollowListKind kind,
  ) async {
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
  Future<List<UserSearchResult>> suggestMentions(String prefix) async {
    // An empty list rather than a throw: the suggestion list is an affordance
    // on top of typing, and a composer that explodes because Firebase is
    // unconfigured would take the whole caption field with it.
    return const [];
  }

  @override
  Future<String?> resolveUsername(String username) async => null;

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
  Future<void> setPostReaction(
    String postId,
    String userId,
    FitReaction? reaction, {
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
    String text, {
    String? parentCommentId,
  }) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<String> uploadMealImage(String localFilePath) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<String> uploadMealImageBytes(Uint8List bytes) async {
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
  Future<String> uploadPostImageBytes(Uint8List bytes) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> toggleBookmark(String postId, String userId) {
    return Future.value();
  }

  @override
  Stream<FitReaction?> watchPostReaction(String postId, String userId) {
    return Stream.value(null);
  }

  @override
  Stream<bool> watchBookmarkStatus(String postId, String userId) {
    return Stream.value(false);
  }

  @override
  Stream<List<Comment>> watchComments(String postId) {
    return const Stream.empty();
  }

  @override
  Future<ActivitySaveResult> createPoll(
    UserProfileDraft? profile,
    PollDraft draft,
  ) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<ActivitySaveResult> createMeetup(
    UserProfileDraft? profile,
    MeetupDraft draft,
  ) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> setPollVote(String postId, String userId, int? option) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> setMeetupRsvp(
    String postId,
    String userId, {
    required bool going,
  }) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Stream<FeedPost?> watchPost(String postId) => const Stream.empty();

  @override
  Future<List<FeedPost>> fetchPromptAnswers(String promptId) async =>
      const [];

  @override
  Future<List<Comment>> fetchCommentPreview(String postId, {int limit = 2}) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<Map<String, String>> displayNamesOf(Iterable<String> userIds) async =>
      const {};

  @override
  Stream<bool> watchShareMilestones(String userId) => Stream.value(true);

  @override
  Future<void> setShareMilestones(String userId, {required bool enabled}) {
    throw StateError(_firebaseSetupMessage);
  }
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';
