import 'dart:typed_data';

import '../../../shared/reactions/fit_reaction.dart';

import '../../auth/domain/auth_models.dart';
import '../domain/app_models.dart';
import '../domain/meal_tracking.dart';
import '../domain/progress_models.dart';

abstract class ContentRepository {
  /// The home feed: posts by the people the signed-in user follows, plus
  /// their own, newest first.
  ///
  /// Falls back to the community's trending posts — flagged as such on the
  /// returned [HomeFeed] — when the user follows nobody or the people they
  /// follow have posted nothing. A blank home screen is never the answer.
  Future<HomeFeed> getFeedPosts(UserProfileDraft? profile);
  Future<List<ProgressMetric>> getProgressMetrics();

  /// Every run and workout the signed-in user has logged, newest first.
  ///
  /// Unwindowed on purpose. The Progress tab reads the same history four
  /// different ways at once — the streak grid, the overview totals, that
  /// period's deltas, and the session list — and one user's own training
  /// history is small enough that fetching it once beats a query per view.
  Future<List<ActivitySession>> getActivitySessions();

  /// The signed-in user's most recent workouts, newest first, one per title.
  ///
  /// Feeds the log screen's "Repeat" chips, so it is deduplicated by title:
  /// somebody who trains the same four splits has four templates, not twenty
  /// copies of the newest one.
  ///
  /// Only workouts logged after exercises were recorded on the log document
  /// carry any; older ones come back with an empty list and repeat only the
  /// title, duration and calories.
  Future<List<RecentWorkout>> getRecentWorkouts({int limit});

  /// Every meal the signed-in user has logged.
  ///
  /// Unwindowed for the same reason as [getActivitySessions]: the meal
  /// tracking page reads one history through a day, a week and a month picker,
  /// and paging between them should not cost a query each time.
  Future<List<LoggedMeal>> getLoggedMeals();

  /// The user's daily macro targets, or the defaults when they have set none.
  Future<MacroGoals> getMacroGoals();

  Future<void> setMacroGoals(MacroGoals goals);

  /// Removes a logged meal. The log only — a shared meal keeps its post, the
  /// same way [deleteActivitySession] leaves a session's post alone.
  Future<void> deleteLoggedMeal(String id);

  /// Days a week the user is aiming to train — the consistency denominator.
  /// Falls back to the default when they have never set one.
  Future<int> getWeeklyGoalDays();

  /// Sets the weekly training-days goal, clamped to 1-7.
  Future<void> setWeeklyGoalDays(int days);

  /// Removes a logged run or workout.
  ///
  /// The log only. A session that was shared keeps its post — deleting the
  /// record of a session is not the same as retracting what you told people
  /// about it, and the post has its own delete.
  Future<void> deleteActivitySession(String id, ActivityKind kind);

  /// Followers / Following for [userId].
  Future<List<ProfileStat>> getProfileStats(String userId);

  /// The people behind one side of [userId]'s follow graph, newest edge first.
  ///
  /// Only ever called for the signed-in user — who follows whom in detail is
  /// the owner's business, and the security rules say the same thing. The
  /// counts on a profile header stay public; this is the list behind them.
  ///
  /// Bounded rather than paged: the same ceiling the home feed reads the
  /// follow graph under, which is what keeps one screen to a handful of reads.
  Future<List<UserSearchResult>> fetchFollowList(
    String userId,
    FollowListKind kind,
  );

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

  /// Candidates for the `@` being typed in a composer.
  ///
  /// Narrower than [searchUsers] on purpose: a mention has to resolve to a
  /// username, so the handle is what is matched and the signed-in user is
  /// included — quoting your own handle is a normal thing to write. An empty
  /// [prefix] is the moment just after the '@' and returns the people most
  /// worth offering first rather than nothing.
  Future<List<UserSearchResult>> suggestMentions(String prefix);

  /// The uid behind `@username`, or null when nobody holds that name.
  ///
  /// Reads the reservation collection rather than searching profiles: the
  /// document id there *is* the normalized username, so this is one get and it
  /// agrees with whatever the uniqueness rules allowed.
  Future<String?> resolveUsername(String username);

  /// The community's posts ranked by engagement against age, newest-weighted,
  /// for the Explore grid. Ordering is a live judgement rather than a stored
  /// one — see `TrendingScore` — so results change as posts age.
  Future<List<FeedPost>> fetchTrendingPosts();

  /// Creates the follow edges between the two users, adjusts both profile
  /// counters and drops a notification in the target's inbox. No-op when the
  /// edge already exists.
  ///
  /// [profile] supplies the follower's public name and photo for that
  /// notification, following the same rule as posts: attribution comes from
  /// the user's profile and never from their credentials. Passing it is an
  /// optimisation — omitted, the stored profile is read instead.
  Future<void> followUser(
    String currentUserId,
    String targetUserId, {
    UserProfileDraft? profile,
  });

  /// Removes the follow edges, adjusts both profile counters and withdraws the
  /// notification the follow raised. No-op when there is no edge to remove.
  Future<void> unfollowUser(String currentUserId, String targetUserId);

  /// Watches whether [currentUserId] currently follows [targetUserId].
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId);

  /// Everyone [userId] follows, by uid, live.
  ///
  /// A stream rather than a read because it is what audiences are built from:
  /// following someone should light up their Pulse ring there and then, not on
  /// the next cold start.
  Stream<Set<String>> watchFollowingIds(String userId);

  /// Watches whether [currentUserId] has asked to be notified about
  /// [targetUserId]'s activity.
  Stream<bool> watchUserNotifications(
      String currentUserId, String targetUserId);

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

  /// Sets, changes, or clears [userId]'s reaction to a post. Null takes it
  /// back.
  ///
  /// One reaction per person: picking a second replaces the first rather than
  /// adding to it, so `likesCount` counts people and not taps. Re-picking what
  /// is already held does nothing at all.
  ///
  /// Reacting to someone else's post notifies them, changing your reaction
  /// updates that notification, and clearing it withdraws it. [profile] names
  /// the reactor on it, on the same terms as [followUser].
  Future<void> setPostReaction(
    String postId,
    String userId,
    FitReaction? reaction, {
    UserProfileDraft? profile,
  });
  Future<void> toggleBookmark(String postId, String userId);
  Future<List<Comment>> getComments(String postId);

  /// Adds a comment attributed to [profile]. The profile is passed in (rather
  /// than read from auth) so the stored author name comes from the user's
  /// public profile and never from their credentials.
  ///
  /// [parentCommentId] makes it a reply to that comment rather than a new
  /// thread, and decides who is told about it — see
  /// `commentNotificationAudience` in domain/comment_threads.dart.
  Future<Comment> addComment(
    UserProfileDraft? profile,
    String postId,
    String text, {
    String? parentCommentId,
  });

  /// Watches which reaction [userId] has given a post, null when none.
  ///
  /// Reads from `likes/{postId}/users/{userId}` — the same document the single
  /// Like button always wrote, now carrying which of the seven it was. One
  /// written before reactions has no key on it and reads as the default.
  Stream<FitReaction?> watchPostReaction(String postId, String userId);

  /// Watches whether the current user has bookmarked a specific post.
  /// Reads from `users/{userId}/bookmarks/{postId}`.
  Stream<bool> watchBookmarkStatus(String postId, String userId);

  /// Real-time stream of comments for a post, ordered by createdAt ascending.
  Stream<List<Comment>> watchComments(String postId);

  /// The newest [limit] comments that start a thread, oldest of them first —
  /// what a feed card shows under the post. Replies are left out: one line
  /// answering a comment the card doesn't show reads as a non sequitur.
  Future<List<Comment>> fetchCommentPreview(String postId, {int limit = 2});

  /// Current public names for [userIds]. Anyone who can't be read is absent
  /// from the result rather than named with a placeholder.
  Future<Map<String, String>> displayNamesOf(Iterable<String> userIds);

  /// Whether [userId]'s streaks, badges and personal bests are posted to the
  /// feed for them. On unless they have turned it off.
  Stream<bool> watchShareMilestones(String userId);

  /// Turns milestone posts on or off for [userId]. Affects only what is earned
  /// from now on; milestones already posted stay until deleted.
  Future<void> setShareMilestones(String userId, {required bool enabled});

  /// Uploads a meal photo to Firebase Storage and returns the download URL.
  Future<String> uploadMealImage(String localFilePath);

  /// Uploads already-loaded JPEG bytes as a meal photo.
  ///
  /// Screens that hold the user's photo while they fill in a form use this so
  /// the upload never depends on a file still existing on disk.
  Future<String> uploadMealImageBytes(Uint8List bytes);

  /// Uploads a post image to Firebase Storage and returns the download URL.
  Future<String> uploadPostImage(String localFilePath);

  /// Byte-based twin of [uploadPostImage]; see [uploadMealImageBytes].
  Future<String> uploadPostImageBytes(Uint8List bytes);

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
