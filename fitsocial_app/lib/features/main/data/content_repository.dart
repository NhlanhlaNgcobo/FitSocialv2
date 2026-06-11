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
  Future<List<StoryItem>> getStories(UserProfileDraft? profile) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<FeedPost>> getFeedPosts(UserProfileDraft? profile) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<SummaryMetric>> getSummaryMetrics() async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<ProgressMetric>> getProgressMetrics() async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<WorkoutPlaylist>> getWorkoutPlaylists(
    WorkoutType workoutType,
  ) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<PodcastRecommendation>> getPodcastRecommendations() async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<ProfileStat>> getProfileStats() async {
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
  Future<void> toggleLike(String postId, String userId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<List<Comment>> getComments(String postId) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<Comment> addComment(String postId, String text) async {
    throw StateError(_firebaseSetupMessage);
  }
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';
