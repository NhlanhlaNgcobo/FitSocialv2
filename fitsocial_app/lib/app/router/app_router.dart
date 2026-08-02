import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/app_session.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/edit_profile_screen.dart';
import '../../features/auth/presentation/profile_setup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/main/presentation/activity_screen.dart';
import '../../features/main/presentation/achievements_screen.dart';
import '../../features/main/presentation/create_screen.dart';
import '../../features/main/presentation/explore_screen.dart';
import '../../features/main/presentation/home_screen.dart';
import '../../features/main/presentation/manual_run_entry_screen.dart';
import '../../features/main/presentation/meal_review_screen.dart';
import '../../features/main/presentation/meal_upload_screen.dart';
import '../../features/main/presentation/post_compose_screen.dart';
import '../../features/main/presentation/profile_screen.dart';
import '../../features/main/presentation/run_log_screen.dart';
import '../../features/main/presentation/workout_log_screen.dart';
import '../../features/tracking/presentation/health_dashboard_screen.dart';
import '../../features/tracking/presentation/live_run_screen.dart';
import '../../shared/layout/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(appSessionProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: session,
    initialLocation: '/splash',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final stage = session.stage;
      const authRoutes = {'/welcome', '/login'};

      // While restoring a persisted session, stay on the splash screen.
      if (stage == AuthStage.initializing) {
        return location == '/splash' ? null : '/splash';
      }

      // Bootstrap finished: move off the splash to the right destination.
      if (location == '/splash') {
        if (stage == AuthStage.unauthenticated) return '/welcome';
        if (stage == AuthStage.profileSetup) return '/profile-setup';
        return '/home';
      }

      if (stage == AuthStage.unauthenticated) {
        if (!authRoutes.contains(location)) {
          return '/welcome';
        }
        return null;
      }

      if (stage == AuthStage.profileSetup) {
        if (location != '/profile-setup') {
          return '/profile-setup';
        }
        return null;
      }

      if (authRoutes.contains(location) || location == '/profile-setup') {
        return '/home';
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
        builder: (context, state) => const PostComposeScreen(),
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
      GoRoute(
        path: '/live-run',
        builder: (context, state) => const LiveRunScreen(),
      ),
      GoRoute(
        path: '/health',
        builder: (context, state) => const HealthDashboardScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
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
