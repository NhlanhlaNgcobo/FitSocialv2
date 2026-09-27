import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/progress_models.dart';
import 'package:fitsocial_app/features/main/presentation/home_screen.dart';
import 'package:fitsocial_app/features/pulse/application/pulse_providers.dart';

import 'shot_data.dart';
import 'shot_harness.dart';

class _Content extends UnconfiguredContentRepository {
  const _Content();

  @override
  Future<HomeFeed> getFeedPosts(UserProfileDraft? profile) async =>
      HomeFeed(posts: homeFeedPosts, source: FeedSource.following);

  @override
  Future<List<ActivitySession>> getActivitySessions() async => thisWeekSessions();
}

void main() {
  testWidgets('home feed', (tester) async {
    await shoot(
      tester,
      'home_feed',
      shotApp(inShell(const HomeScreen()), overrides: [
        contentRepositoryProvider.overrideWithValue(const _Content()),
        feedPostsProvider.overrideWith(
            (ref) => FeedPostsNotifier(const _Content(), null)),
        currentUserIdProvider.overrideWithValue('u-me'),
        activePulsesProvider.overrideWith((ref) => Stream.value(trayPulses)),
        pulseSeenMarkersProvider
            .overrideWith((ref) => Stream.value(const <String, DateTime>{})),
      ]),
    );
  });
  testWidgets('home feed long', (tester) async {
    await shoot(
      tester,
      'home_feed_long',
      shotApp(inShell(const HomeScreen()), overrides: [
        contentRepositoryProvider.overrideWithValue(const _Content()),
        feedPostsProvider.overrideWith(
            (ref) => FeedPostsNotifier(const _Content(), null)),
        currentUserIdProvider.overrideWithValue('u-me'),
        activePulsesProvider.overrideWith((ref) => Stream.value(trayPulses)),
        pulseSeenMarkersProvider
            .overrideWith((ref) => Stream.value(const <String, DateTime>{})),
      ]),
      height: 2300,
    );
  });
}
