import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/app_session.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/edit_profile_screen.dart';
import '../../features/auth/presentation/profile_setup_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/main/presentation/activity_screen.dart';
import '../../features/main/presentation/achievements_screen.dart';
import '../../features/main/presentation/create_screen.dart';
import '../../features/main/presentation/explore_screen.dart';
import '../../features/main/presentation/home_screen.dart';
import '../../features/main/presentation/meal_camera_screen.dart';
import '../../features/main/presentation/meal_review_screen.dart';
import '../../features/main/presentation/post_compose_screen.dart';
import '../../features/main/presentation/profile_screen.dart';
import '../../features/main/presentation/run_log_screen.dart';
import '../../features/main/presentation/workout_log_screen.dart';
import '../../shared/layout/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(appSessionProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: session,
    initialLocation: '/welcome',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final stage = session.stage;
      const authRoutes = {'/welcome', '/login'};

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
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
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
        path: '/compose-post',
        builder: (context, state) => const PostComposeScreen(),
      ),
      GoRoute(
        path: '/meal-camera',
        builder: (context, state) => const MealCameraScreen(),
      ),
      GoRoute(
        path: '/meal-review',
        builder: (context, state) => const MealReviewScreen(),
      ),
      GoRoute(
        path: '/achievements',
        builder: (context, state) => const AchievementsScreen(),
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
