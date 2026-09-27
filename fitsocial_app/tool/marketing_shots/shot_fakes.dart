// Stand-ins for hardware and plugins the shots never touch.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fitsocial_app/features/auth/data/auth_repository.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/content_repository_contract.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/progress_models.dart';
import 'package:fitsocial_app/shared/reactions/fit_reaction.dart';

import 'package:fitsocial_app/features/tracking/application/tracking_providers.dart';
import 'package:fitsocial_app/features/tracking/data/ble_heart_rate_service.dart';
import 'package:fitsocial_app/features/tracking/domain/heart_rate_models.dart';

import 'shot_data.dart';

class FakeHeartRateLink implements HeartRateLink {
  @override
  Stream<int> get heartRateStream => const Stream.empty();
  @override
  Stream<bool> get adapterOn => Stream.value(false);
  @override
  Stream<bool> connectedChanges(String remoteId) => const Stream.empty();
  @override
  Future<bool> isSupported() async => false;
  @override
  Future<bool> requestPermissions() async => false;
  @override
  Stream<List<DiscoveredHeartRateDevice>> scan({Duration? timeout}) =>
      const Stream.empty();
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connectById(String remoteId, {bool autoConnect = false}) async {}
  @override
  Future<void> subscribeNotifications(String remoteId) async {}
  @override
  Future<void> disconnect() async {}
  @override
  void dispose() {}
}

/// Overrides every shot needs so nothing reaches for a plugin.
List<Override> get baseFakes => [
      bleHeartRateServiceProvider.overrideWithValue(FakeHeartRateLink()),
    ];

/// The content backend, answering from shot_data.
class ShotContent extends UnconfiguredContentRepository {
  const ShotContent();

  @override
  Future<HomeFeed> getFeedPosts(UserProfileDraft? profile) async =>
      HomeFeed(posts: homeFeedPosts, source: FeedSource.following);

  @override
  Future<List<ActivitySession>> getActivitySessions() async =>
      thisWeekSessions();

  @override
  Future<UserSearchResult?> fetchUserProfile(String userId) async =>
      people[userId];

  @override
  Future<List<UserSearchResult>> searchUsers(String query) async {
    final q = query.toLowerCase();
    return people.values
        .where((p) =>
            p.displayName.toLowerCase().contains(q) ||
            p.handle.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<Comment>> getComments(String postId) async => runComments();

  @override
  Future<List<ProfileStat>> getProfileStats(String userId) async => const [
        ProfileStat(label: 'Posts', value: '214'),
        ProfileStat(label: 'Followers', value: '1.2K'),
        ProfileStat(label: 'Following', value: '386'),
      ];

  @override
  Future<List<UserSearchResult>> fetchFollowList(
          String userId, FollowListKind kind) async =>
      people.values.where((p) => p.id != userId).toList();

  @override
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId) =>
      Stream.value(const {'u-lerato', 'u-thandi', 'u-ayanda'}.contains(targetUserId));

  @override
  Future<List<FeedPost>> fetchUserPosts(String userId) async =>
      userId == 'u-sipho'
          ? siphoRuns()
          : homeFeedPosts.where((p) => p.authorId == userId).toList();

  @override
  Future<List<FeedPost>> fetchUserMediaPosts(String userId) async =>
      homeFeedPosts.where((p) => p.authorId == userId).toList();

  @override
  Future<List<RecentWorkout>> getRecentWorkouts({int limit = 6}) async =>
      recentWorkouts();

  @override
  Stream<List<Comment>> watchComments(String postId) =>
      Stream.value(runComments());

  @override
  Stream<FitReaction?> watchPostReaction(String postId, String userId) =>
      Stream.value(null);

  @override
  Stream<bool> watchBookmarkStatus(String postId, String userId) =>
      Stream.value(false);

  @override
  Future<void> setPostReaction(String postId, String userId, FitReaction? reaction,
      {UserProfileDraft? profile}) async {}
}

/// Signed in as [me], with the shot content behind every read.
const siphoProfile = UserProfileDraft(
  displayName: 'Sipho Ndlovu',
  handle: 'sipho.runs',
  bio: 'Durban. Comrades 2027. 5am club.',
  location: 'Durban, South Africa',
);

List<Override> signedIn(
        {String me = 'u-sipho', ContentRepository content = const ShotContent()}) =>
    [
      ...baseFakes,
      authRepositoryProvider.overrideWithValue(ShotAuth(email: 'sipho@example.com')),
      userProfileRepositoryProvider
          .overrideWithValue(ShotProfiles(profile: siphoProfile)),
      contentRepositoryProvider.overrideWithValue(content),
      currentUserIdProvider.overrideWithValue(me),
      // These two read FirebaseAuth directly; answer as the signed-in user.
      postReactionProvider.overrideWith((ref, postId) => Stream.value(null)),
      postBookmarkStatusProvider.overrideWith((ref, postId) => Stream.value(false)),
    ];

/// Signed in, nothing saved yet: the state a new account lands in.
class ShotAuth implements AuthRepository {
  ShotAuth({this.email});

  /// Null for a fresh install; set for a restored, signed-in session.
  final String? email;

  @override
  bool canAddPassword() => false;
  @override
  Future<void> addPassword(String password) async {}
  @override
  String? currentUserId() => 'u-sipho';
  @override
  Future<void> deleteAccount() async {}
  @override
  String? currentUserEmail() => email;
  @override
  Future<bool> hasValidSession() async => email != null;
  @override
  Future<void> signOut() async {}
  @override
  Future<String> signInWithEmail(
          {required String email, required String password}) async =>
      email;
  @override
  Future<String> signInWithUsername(
          {required String username, required String password}) async =>
      username;
  @override
  Future<String> signUpWithEmail(
          {required String email, required String password}) async =>
      email;
  @override
  Future<String> continueWithProvider(String providerName) async => 'provider';
  @override
  Future<void> sendPasswordResetEmail(String email) async {}
}

class ShotProfiles implements UserProfileRepository {
  ShotProfiles({this.profile});

  final UserProfileDraft? profile;

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => profile;
  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
    String pronouns = '',
    String links = '',
  }) async =>
      UserProfileDraft(
          displayName: displayName, handle: handle, bio: bio, location: location);
  @override
  Future<BodyMetrics> loadBodyMetrics() async => const BodyMetrics();
  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async {}
}

List<Override> get newAccount => [
      ...baseFakes,
      authRepositoryProvider.overrideWithValue(ShotAuth()),
      userProfileRepositoryProvider.overrideWithValue(ShotProfiles()),
    ];
