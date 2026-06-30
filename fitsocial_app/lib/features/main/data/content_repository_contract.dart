import '../../auth/domain/auth_models.dart';
import '../domain/app_models.dart';

abstract class ContentRepository {
  Future<List<StoryItem>> getStories(UserProfileDraft? profile);
  Future<List<FeedPost>> getFeedPosts(UserProfileDraft? profile);
  Future<List<SummaryMetric>> getSummaryMetrics();
  Future<List<ProgressMetric>> getProgressMetrics();
  Future<List<WorkoutPlaylist>> getWorkoutPlaylists(WorkoutType workoutType);
  Future<List<PodcastRecommendation>> getPodcastRecommendations();
  Future<List<ProfileStat>> getProfileStats();
  Future<ActivitySaveResult> saveWorkout(
    UserProfileDraft? profile,
    WorkoutLogDraft draft,
  );
  Future<ActivitySaveResult> saveRun(
    UserProfileDraft? profile,
    RunLogDraft draft,
  );
  Future<ActivitySaveResult> saveMeal(
    UserProfileDraft? profile,
    MealLogDraft draft,
  );
  Future<ActivitySaveResult> sharePost(
    UserProfileDraft? profile,
    PostDraft draft,
  );
  Future<void> toggleLike(String postId, String userId);
  Future<List<Comment>> getComments(String postId);
  Future<Comment> addComment(String postId, String text);

  /// Uploads a meal photo to Firebase Storage and returns the download URL.
  Future<String> uploadMealImage(String localFilePath);

  /// Calls the analyzeMeal Cloud Function with the image URL and returns
  /// structured nutritional data: { name, calories, protein, carbs, fat }.
  Future<Map<String, dynamic>> analyzeMealImage(String imageUrl);
}
