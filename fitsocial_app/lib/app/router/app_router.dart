import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/app_session.dart';
import '../../features/main/domain/activity_kind.dart';
import '../../features/main/domain/app_models.dart';
import '../../features/main/domain/shared_post.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/edit_profile_screen.dart';
import '../../features/auth/presentation/profile_setup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/challenges/domain/challenge_models.dart';
import '../../features/challenges/presentation/challenge_detail_screen.dart';
import '../../features/challenges/presentation/challenge_board_screen.dart';
import '../../features/challenges/presentation/challenge_hub_screen.dart';
import '../../features/challenges/presentation/create_challenge_screen.dart';
import '../../features/challenges/presentation/live_challenges_screen.dart';
import '../../features/challenges/presentation/challenge_outcome_screen.dart';
import '../../features/challenges/presentation/challenge_tracker_screen.dart';
import '../../features/main/presentation/activity_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/insights/presentation/weekly_insight_screen.dart';
import '../../features/leaderboards/presentation/leaderboard_screen.dart';
import '../../features/main/presentation/achievements_screen.dart';
import '../../features/main/presentation/bmi_screen.dart';
import '../../features/main/presentation/connections_screen.dart';
import '../../features/main/presentation/create_screen.dart';
import '../../features/main/presentation/explore_screen.dart';
import '../../features/main/presentation/home_screen.dart';
import '../../features/main/presentation/manual_run_entry_screen.dart';
import '../../features/main/presentation/meal_review_screen.dart';
import '../../features/main/presentation/meal_tracking_screen.dart';
import '../../features/main/presentation/meal_upload_screen.dart';
import '../../features/main/presentation/post_compose_screen.dart';
import '../../features/main/presentation/prompt_answers_screen.dart';
import '../../features/main/presentation/social_compose_screens.dart';
import '../../features/main/domain/daily_prompts.dart';
import '../../features/main/presentation/post_detail_screen.dart';
import '../../features/main/presentation/profile_screen.dart';
import '../../features/main/presentation/run_log_screen.dart';
import '../../features/main/presentation/user_profile_screen.dart';
import '../../features/main/presentation/workout_log_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/races/presentation/race_detail_screen.dart';
import '../../features/races/presentation/races_screen.dart';
import '../../features/races/presentation/saved_races_screen.dart';
import '../../features/races/presentation/submit_race_screen.dart';
import '../../features/safety/presentation/panic_alert_screen.dart';
import '../../features/safety/presentation/panic_screen.dart';
import '../../features/safety/presentation/pin_setup_screen.dart';
import '../../features/safety/presentation/safety_contacts_screen.dart';
import '../../features/safety/presentation/safety_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/pulse/domain/pulse_music.dart';
import '../../features/pulse/presentation/pulse_composer_screen.dart';
import '../../features/pulse/presentation/pulse_viewer_screen.dart';
import '../../features/pulse/presentation/share_music_to_pulse_screen.dart';
import '../../features/pulse/presentation/share_post_to_pulse_screen.dart';
import '../../features/tracking/presentation/health_dashboard_screen.dart';
import '../../features/tracking/presentation/live_activity_viewer_screen.dart';
import '../../features/tracking/presentation/live_run_screen.dart';
import '../../features/tracking/presentation/treadmill_run_screen.dart';
import '../../features/weather/presentation/weather_forecast_screen.dart';
import '../../shared/layout/app_shell.dart';
import '../../shared/layout/branch_transition.dart';
import 'pending_deep_link.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  // `.notifier`, NOT the provider itself. Watching a ChangeNotifierProvider
  // rebuilds on every notifyListeners(), which would build a whole new
  // GoRouter — and a new router starts at initialLocation, throwing away the
  // navigation stack. Saving the profile notifies twice, which is why it used
  // to land on /home instead of popping back to /profile. Watching the
  // notifier rebuilds only if the AppSession instance itself is replaced;
  // refreshListenable below is what re-runs `redirect` when its state changes.
  final session = ref.watch(appSessionProvider.notifier);
  // Shared links can arrive before the app is in any state to show them — on a
  // cold start, or with nobody signed in. Each branch below that turns such a
  // link away parks it here first, and the branches that land somebody in the
  // app redeem it in place of /home.
  final pendingLink = ref.watch(pendingDeepLinkProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: session,
    initialLocation: '/splash',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final stage = session.stage;
      const authRoutes = {'/welcome', '/login'};

      // While restoring a persisted session, stay on the splash screen. A deep
      // link is the usual reason to be anywhere else this early — the platform
      // hands the app its initial route before the session has resolved — so
      // it is kept rather than dropped on the way to the splash.
      if (stage == AuthStage.initializing) {
        if (location != '/splash') pendingLink.remember(location);
        return location == '/splash' ? null : '/splash';
      }

      // Bootstrap finished: move off the splash to the right destination.
      if (location == '/splash') {
        if (stage == AuthStage.unauthenticated) return '/welcome';
        if (stage == AuthStage.profileSetup) return '/profile-setup';
        return pendingLink.take() ?? '/home';
      }

      if (stage == AuthStage.unauthenticated) {
        if (!authRoutes.contains(location)) {
          pendingLink.remember(location);
          return '/welcome';
        }
        return null;
      }

      if (stage == AuthStage.profileSetup) {
        if (location != '/profile-setup') {
          pendingLink.remember(location);
          return '/profile-setup';
        }
        return null;
      }

      // Just signed in, or just finished setting up. Someone who got here by
      // tapping a shared post lands on the post rather than the feed.
      if (authRoutes.contains(location) || location == '/profile-setup') {
        return pendingLink.take() ?? '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final isLogin = state.uri.queryParameters['mode'] != 'signup';
          return LoginScreen(isLoginMode: isLogin);
        },
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/log-workout',
        builder: (context, state) => const WorkoutLogScreen(),
      ),
      GoRoute(
        path: '/log-run',
        builder: (context, state) => const RunLogScreen(),
      ),
      GoRoute(
        path: '/log-run-manual',
        builder: (context, state) => const ManualRunEntryScreen(),
      ),
      GoRoute(
        path: '/compose-post',
        // An answer to the day's question arrives with the question as extra.
        builder: (context, state) =>
            PostComposeScreen(prompt: state.extra as PostPrompt?),
      ),
      GoRoute(
        path: '/compose-poll',
        builder: (context, state) => const PollComposeScreen(),
      ),
      GoRoute(
        path: '/compose-meetup',
        builder: (context, state) => const MeetupComposeScreen(),
      ),
      // Everyone's answers to one day's question. The id is the day, so a
      // link that arrives without the question still knows which one it was.
      GoRoute(
        path: '/prompt/:promptId',
        builder: (context, state) {
          final id = state.pathParameters['promptId']!;
          final prompt =
              state.extra as PostPrompt? ??
              PostPrompt(
                id: id,
                text: DailyPrompts.forDay(
                  DateTime.tryParse(id) ?? DateTime.now(),
                ).text,
              );
          return PromptAnswersScreen(prompt: prompt);
        },
      ),
      // Legacy path kept so older links/back-stack entries don't 404. The
      // real capture + AI analysis flow lives at /meal-upload.
      GoRoute(
        path: '/meal-camera',
        redirect: (context, state) => '/meal-upload',
      ),
      GoRoute(
        path: '/meal-upload',
        builder: (context, state) => const MealUploadScreen(),
      ),
      GoRoute(
        path: '/meal-review',
        builder: (context, state) => const MealReviewScreen(),
      ),
      GoRoute(
        path: '/achievements',
        builder: (context, state) => const AchievementsScreen(),
      ),
      GoRoute(path: '/bmi', builder: (context, state) => const BmiScreen()),
      GoRoute(
        path: '/meal-tracking',
        builder: (context, state) => const MealTrackingScreen(),
      ),
      GoRoute(
        path: '/weather',
        builder: (context, state) => const WeatherForecastScreen(),
      ),
      // One post, opened from a profile grid. The tapped post rides along as
      // `extra` so the screen draws immediately; arriving without it (a deep
      // link, or a restart) falls back to fetching by id.
      GoRoute(
        path: '/post/:postId',
        builder: (context, state) => PostDetailScreen(
          postId: state.pathParameters['postId']!,
          initialPost: state.extra as FeedPost?,
        ),
      ),
      // Outside the shell: it is opened from the bell and returned from, not
      // one of the five tabs.
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Safety. Outside the shell: destinations you come back from. The panic
      // screen in particular must cover the tab bar, so nothing on screen can
      // navigate away from an active alert.
      GoRoute(
        path: '/safety',
        builder: (context, state) => const SafetyScreen(),
      ),
      GoRoute(
        path: '/safety/contacts',
        builder: (context, state) => const SafetyContactsScreen(),
      ),
      GoRoute(
        path: '/safety/pins',
        builder: (context, state) => const PinSetupScreen(),
      ),
      GoRoute(
        path: '/safety/panic',
        builder: (context, state) => const PanicScreen(),
      ),
      // An alert somebody else raised, opened from its push notification.
      GoRoute(
        path: '/safety/alert/:eventId',
        builder: (context, state) =>
            PanicAlertScreen(eventId: state.pathParameters['eventId']!),
      ),
      // Your followers and the people you follow.
      //
      // No user id in the path, deliberately: this page only ever shows the
      // signed-in user's own two lists, and a route that took an id would be
      // an invitation to open somebody else's. Which tab opens first is a
      // presentation detail, so it rides in the query string.
      GoRoute(
        path: '/connections',
        builder: (context, state) => ConnectionsScreen(
          initialKind: FollowListKindX.fromRouteTab(
            state.uri.queryParameters['tab'],
          ),
        ),
      ),
      // Someone else's profile. Outside the shell on purpose: it is a
      // destination you come back from, not one of the five tabs.
      GoRoute(
        path: '/user/:userId',
        builder: (context, state) =>
            UserProfileScreen(userId: state.pathParameters['userId']!),
      ),
      // Challenges. Outside the shell, like the log flows: these are
      // destinations you come back from, not one of the five tabs.
      GoRoute(
        path: '/challenges',
        builder: (context, state) => const ChallengeHubScreen(),
      ),
      // Personal goals. Reachable only from the home card, which is hidden
      // while goals are switched off in Remote Config.
      GoRoute(path: '/goals', builder: (context, state) => const GoalsScreen()),
      // The friends leaderboard. Reachable only from the Progress card, which
      // is hidden while leaderboards are switched off in Remote Config.
      // Last week's Weekly Insight in full. Reached from the home card, which
      // draws nothing while the feature is off or hidden.
      GoRoute(
        path: '/insights',
        builder: (context, state) => const WeeklyInsightScreen(),
      ),
      GoRoute(
        path: '/leaderboard',
        builder: (context, state) => const LeaderboardScreen(),
      ),
      // User-created running challenges.
      //
      // Declared before /challenge/:challengeKey, though nothing depends on
      // that: these carry three path segments and the fixed-challenge route
      // carries two, so go_router cannot confuse them. Ordering them anyway
      // keeps the challenge routes readable as one group.
      GoRoute(
        path: '/challenges/live',
        builder: (context, state) => const LiveChallengesScreen(),
      ),
      GoRoute(
        path: '/challenges/create',
        builder: (context, state) => const CreateChallengeScreen(),
      ),
      // Also the deep link a shared private challenge resolves to. The screen
      // handles the unreadable case itself: a challenge the viewer is not on
      // reports "not available" rather than distinguishing "private" from
      // "does not exist", because saying which is most of what privacy is for.
      GoRoute(
        path: '/challenge/board/:challengeId',
        builder: (context, state) => ChallengeBoardScreen(
          challengeId: state.pathParameters['challengeId']!,
        ),
      ),
      // An unknown challenge key goes to the hub rather than rendering an
      // empty screen — a stale share link should land somewhere useful.
      GoRoute(
        path: '/challenge/track/:enrollmentId',
        builder: (context, state) => ChallengeTrackerScreen(
          enrollmentId: state.pathParameters['enrollmentId']!,
        ),
      ),
      GoRoute(
        path: '/challenge/outcome/:enrollmentId',
        builder: (context, state) => ChallengeOutcomeScreen(
          enrollmentId: state.pathParameters['enrollmentId']!,
        ),
      ),
      GoRoute(
        path: '/challenge/:challengeKey',
        redirect: (context, state) =>
            ChallengeKey.byKey(state.pathParameters['challengeKey'] ?? '') ==
                null
            ? '/challenges'
            : null,
        builder: (context, state) => ChallengeDetailScreen(
          challengeKey: ChallengeKey.byKey(
            state.pathParameters['challengeKey']!,
          )!,
        ),
      ),
      // The running calendar. Outside the shell like the challenge screens:
      // you come back from a race listing, you do not live in it.
      //
      // /races/saved and /races/submit are declared before /race/:eventId so a
      // path never has to be disambiguated by ordering luck — the two literal
      // sub-paths sit under /races and the parameterised one under /race, which
      // cannot collide with either.
      GoRoute(path: '/races', builder: (context, state) => const RacesScreen()),
      GoRoute(
        path: '/races/saved',
        builder: (context, state) => const SavedRacesScreen(),
      ),
      GoRoute(
        path: '/races/submit',
        builder: (context, state) => const SubmitRaceScreen(),
      ),
      GoRoute(
        path: '/race/:eventId',
        builder: (context, state) =>
            RaceDetailScreen(eventId: state.pathParameters['eventId']!),
      ),
      GoRoute(
        path: '/live-run',
        // The activity comes through `extra` rather than the path: it is a
        // choice made on the way in, not an addressable thing, and a deep link
        // straight to /live-run should still open a run.
        builder: (context, state) => LiveRunScreen(
          kind: state.extra is ActivityKind
              ? state.extra! as ActivityKind
              : ActivityKind.run,
        ),
      ),
      GoRoute(
        path: '/treadmill-run',
        builder: (context, state) => const TreadmillRunScreen(),
      ),
      // Somebody else's activity in progress, reached through a shared link.
      // Outside the shell for the same reason a post is: you arrive from a
      // chat, watch, and leave. The id is the whole credential — see
      // FitSocialLinks.live.
      GoRoute(
        path: '/live/:shareId',
        builder: (context, state) =>
            LiveActivityViewerScreen(shareId: state.pathParameters['shareId']!),
      ),
      GoRoute(
        path: '/health',
        builder: (context, state) => const HealthDashboardScreen(),
      ),
      GoRoute(
        path: '/pulse-compose',
        builder: (context, state) => const PulseComposerScreen(),
      ),
      // Putting somebody's post on your own Pulse. The post rides along as
      // `extra` rather than as a path id: it is a snapshot taken from the card
      // the user tapped, not something to be re-fetched — and there is nothing
      // to show if you arrive here without one, so a bare visit goes home.
      GoRoute(
        path: '/share-to-pulse',
        redirect: (context, state) =>
            state.extra is SharedPostRef ? null : '/home',
        builder: (context, state) =>
            SharePostToPulseScreen(post: state.extra! as SharedPostRef),
      ),
      // The track rides along as `extra` for the same reason a post does: it is
      // a snapshot of what was playing when the button was pressed, not
      // something to be re-read on arrival.
      GoRoute(
        path: '/share-music-to-pulse',
        redirect: (context, state) =>
            state.extra is PulseMusic ? null : '/home',
        builder: (context, state) =>
            ShareMusicToPulseScreen(music: state.extra! as PulseMusic),
      ),
      // Playback opens on one author's ring and can then be swiped across the
      // rest of the tray, which the viewer reads from the provider itself —
      // so the route carries an id rather than a payload.
      GoRoute(
        path: '/pulse/:authorId',
        builder: (context, state) => PulseViewerScreen(
          initialAuthorId: state.pathParameters['authorId']!,
        ),
      ),
      // Not `.indexedStack`: that swaps branches on a single frame, which is
      // the one screen change in the app with no motion. The container builder
      // hands the branch navigators to BranchTransition instead, which keeps
      // every one of them alive and fades between them.
      StatefulShellRoute(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        navigatorContainerBuilder: (context, navigationShell, children) {
          return BranchTransition(
            currentIndex: navigationShell.currentIndex,
            children: children,
          );
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (context, state) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/create',
                builder: (context, state) => const CreateScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activity',
                builder: (context, state) => const ActivityScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
