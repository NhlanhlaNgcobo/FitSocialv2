import '../../auth/domain/auth_models.dart';
import '../domain/app_models.dart';

abstract class ContentRepository {
  Future<List<FeedPost>> getFeedPosts(UserProfileDraft? profile);
  Future<List<ProgressMetric>> getProgressMetrics();

  /// The signed-in user's runs and workouts bucketed per calendar day, from
  /// [from] (local midnight) to now.
  ///
  /// Sparse by design: only days with at least one logged session come back.
  /// [ActivityCalendar.fromLoggedDays] fills in the empty cells.
  Future<List<ActivityDay>> getActivityDays(DateTime from);
  /// Uploads / Followers / Following for [userId].
  ///
  /// "Uploads" is how much of the app the user has actually used: every run
  /// and workout they have logged, shared or not, plus every photo they have
  /// posted. Meals are excluded on purpose.
  Future<List<ProfileStat>> getProfileStats(String userId);

  /// A single public profile, or null when no such user exists.
  Future<UserSearchResult?> fetchUserProfile(String userId);

  /// Aggregates the user's logged activity into XP, level, streak and badge
  /// progress.
  Future<AchievementsData> fetchUserAchievements(String userId);

  /// A single post by id, or null when it no longer exists. Used when a post
  /// is opened by route rather than tapped in a list that already holds it.
  Future<FeedPost?> fetchPost(String postId);

  /// All posts authored by [userId], newest first.
  Future<List<FeedPost>> fetchUserPosts(String userId);

  /// Posts authored by [userId] that carry an uploaded photo, newest first.
  Future<List<FeedPost>> fetchUserMediaPosts(String userId);

  /// Profiles whose display name or handle starts with [query].
  Future<List<UserSearchResult>> searchUsers(String query);

  /// The community's posts ranked by engagement against age, newest-weighted,
  /// for the Explore grid. Ordering is a live judgement rather than a stored
  /// one — see `TrendingScore` — so results change as posts age.
  Future<List<FeedPost>> fetchTrendingPosts();

  /// Creates the follow edges between the two users and adjusts both profile
  /// counters. No-op when the edge already exists.
  Future<void> followUser(String currentUserId, String targetUserId);

  /// Removes the follow edges and adjusts both profile counters. No-op when
  /// there is no edge to remove.
  Future<void> unfollowUser(String currentUserId, String targetUserId);

  /// Watches whether [currentUserId] currently follows [targetUserId].
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId);

  /// Watches whether [currentUserId] has asked to be notified about
  /// [targetUserId]'s activity.
  Stream<bool> watchUserNotifications(String currentUserId, String targetUserId);

  /// Turns notifications about [targetUserId] on or off for [currentUserId].
  Future<void> setUserNotifications(
    String currentUserId,
    String targetUserId, {
    required bool enabled,
  });
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
  /// Permanently removes a post the caller authored, along with its comments
  /// and its uploaded image. Throws if the caller is not the author.
  Future<void> deletePost(String postId);

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
  /// structured nutritional data.
  ///
  /// Shape: { name, calories, protein, carbs, fat, confidence, notes,
  /// databaseCoverage, foodItems: [...] }. The macros come from the nutrition
  /// database wherever the identified food could be resolved; `foodItems`
  /// carries the per-item breakdown and each item's `source`.
  Future<Map<String, dynamic>> analyzeMealImage(String imageUrl);

  /// Searches the nutrition database by name, for correcting or adding a food
  /// by hand. Returns entries with their per-100 g composition.
  Future<List<FoodSearchResult>> searchFoods(String query);
}
