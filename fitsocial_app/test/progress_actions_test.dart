import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/music_integration_controller.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/activity_screen.dart';

/// The Progress body reads a lot of things this test does not care about — the
/// session history, the calendar, the weather. Left unstubbed they render their
/// own error states, which is fine: the app bar is what is under test, and it
/// must be reachable whatever the body below it is doing.
class _StubRepository extends UnconfiguredContentRepository {
  const _StubRepository();
}

/// Records where the app bar sent us, without building the real destinations.
class RouteSpy {
  final List<String> visited = [];
}

Future<void> pumpActivity(WidgetTester tester, RouteSpy spy) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Widget stubPage(String path) => Scaffold(body: Text('page:$path'));

  final router = GoRouter(
    initialLocation: '/activity',
    routes: [
      GoRoute(
        path: '/activity',
        builder: (_, __) => const ActivityScreen(),
      ),
      for (final path in const ['/bmi', '/meal-tracking', '/achievements'])
        GoRoute(
          path: path,
          builder: (_, __) {
            spy.visited.add(path);
            return stubPage(path);
          },
        ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(const _StubRepository()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('progress app bar', () {
    testWidgets('carries BMI, meal tracking and achievements', (tester) async {
      await pumpActivity(tester, RouteSpy());

      expect(find.byTooltip('BMI'), findsOneWidget);
      expect(find.byTooltip('Meal tracking'), findsOneWidget);
      expect(find.byTooltip('Achievements'), findsOneWidget);
    });

    testWidgets('opens the BMI page', (tester) async {
      final spy = RouteSpy();
      await pumpActivity(tester, spy);

      await tester.tap(find.byTooltip('BMI'));
      await tester.pumpAndSettle();

      expect(spy.visited, ['/bmi']);
    });

    testWidgets('opens meal tracking', (tester) async {
      final spy = RouteSpy();
      await pumpActivity(tester, spy);

      await tester.tap(find.byTooltip('Meal tracking'));
      await tester.pumpAndSettle();

      expect(spy.visited, ['/meal-tracking']);
    });

    testWidgets('opens achievements', (tester) async {
      final spy = RouteSpy();
      await pumpActivity(tester, spy);

      await tester.tap(find.byTooltip('Achievements'));
      await tester.pumpAndSettle();

      expect(spy.visited, ['/achievements']);
    });

    // These three report on training, eating and streaks. None of them has
    // anything to do with a playlist, so none belongs over the Music section.
    testWidgets('drops all three when Music is showing', (tester) async {
      final spy = RouteSpy();
      await pumpActivity(tester, spy);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivityScreen)),
      );
      container
          .read(musicIntegrationControllerProvider.notifier)
          .selectSection(ActivitySection.music);
      await tester.pump();

      expect(find.byTooltip('BMI'), findsNothing);
      expect(find.byTooltip('Meal tracking'), findsNothing);
      expect(find.byTooltip('Achievements'), findsNothing);
    });
  });
}
