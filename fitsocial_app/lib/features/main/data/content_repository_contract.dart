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

  /// Aggregates the user's logged activity into XP, level, streak and badge
  /// progress.
  Future<AchievementsData> fetchUserAchievements(String userId);

  /// All posts authored by [userId], newest first.
  Future<List<FeedPost>> fetchUserPosts(String userId);

  /// Posts authored by [userId] that carry an uploaded photo, newest first.
  Future<List<FeedPost>> fetchUserMediaPosts(String userId);

  /// Profiles whose display name or handle starts with [query].
  Future<List<UserSearchResult>> searchUsers(String query);

  /// Most-liked posts across the community.
  Future<List<FeedPost>> fetchTrendingPosts();

  /// Creates the follow edges between the two users and adjusts both profile
  /// counters. No-op when the edge already exists.
  Future<void> followUser(String currentUserId, String targetUserId);

  /// Removes the follow edges and adjusts both profile counters. No-op when
  /// there is no edge to remove.
  Future<void> unfollowUser(String currentUserId, String targetUserId);

  /// Watches whether [currentUserId] currently follows [targetUserId].
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId);
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
  Future<void> toggleBookmark(String postId, String userId);
  Future<List<Comment>> getComments(String postId);
  /// Adds a comment attributed to [profile]. The profile is passed in (rather
  /// than read from auth) so the stored author name comes from the user's
  /// public profile and never from their credentials.
  Future<Comment> addComment(
    UserProfileDraft? profile,
    String postId,
    String text,
  );

  /// Watches whether the current user has liked a specific post.
  /// Reads from `likes/{postId}/users/{userId}`.
  Stream<bool> watchPostLikeStatus(String postId, String userId);

  /// Watches whether the current user has bookmarked a specific post.
  /// Reads from `users/{userId}/bookmarks/{postId}`.
  Stream<bool> watchBookmarkStatus(String postId, String userId);

  /// Real-time stream of comments for a post, ordered by createdAt ascending.
  Stream<List<Comment>> watchComments(String postId);

  /// Uploads a meal photo to Firebase Storage and returns the download URL.
  Future<String> uploadMealImage(String localFilePath);

  /// Uploads a post image to Firebase Storage and returns the download URL.
  Future<String> uploadPostImage(String localFilePath);

  /// Calls the analyzeMeal Cloud Function with the image URL and returns
  /// structured nutritional data: { name, calories, protein, carbs, fat }.
  Future<Map<String, dynamic>> analyzeMealImage(String imageUrl);
}
