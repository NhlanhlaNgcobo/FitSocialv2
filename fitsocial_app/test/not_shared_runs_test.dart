import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/connectivity/backend_reachability.dart';
import 'package:fitsocial_app/features/main/application/activity_actions.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/domain/activity_kind.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/unshared_run.dart';
import 'package:fitsocial_app/features/main/presentation/not_shared_runs_screen.dart';
import 'package:fitsocial_app/shared/widgets/route_sparkline.dart';

final _run = UnsharedRun(
  id: 'run-1',
  kind: ActivityKind.run,
  startedAt: DateTime(2026, 10, 3, 7),
  distanceKm: 5.2,
  elapsed: const Duration(minutes: 27, seconds: 4),
  averagePace: '5:12 /km',
  routePoints: const [
    RoutePoint(latitude: -26.20, longitude: 28.00, seconds: 0),
    RoutePoint(latitude: -26.21, longitude: 28.02, seconds: 300),
    RoutePoint(latitude: -26.22, longitude: 28.01, seconds: 540),
  ],
  routePlacement: const RoutePlacement(dx: 0.2, dy: -0.1, scale: 0.7),
);

/// Records what the editor asked to post, without touching Firebase.
class _FakeActions extends ActivityActions {
  _FakeActions(super.ref);

  UnsharedRunShare? shared;

  @override
  Future<ActivitySaveResult> shareUnsharedRun(UnsharedRunShare share) async {
    shared = share;
    return const ActivitySaveResult(message: 'Run saved and shared.');
  }
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}

void main() {
  /// Returns the fake actions, which are only built once the editor asks.
  Future<List<_FakeActions>> pump(
    WidgetTester tester, {
    required List<UnsharedRun> runs,
    String start = '/not-shared',
  }) async {
    final actions = <_FakeActions>[];
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(
          path: '/not-shared',
          builder: (_, __) => const NotSharedRunsScreen(),
        ),
        GoRoute(
          path: '/not-shared/:runId',
          builder: (_, state) => UnsharedRunEditorScreen(
            runId: state.pathParameters['runId']!,
            initialRun: state.extra as UnsharedRun?,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unsharedRunsProvider.overrideWith((ref) async => runs),
          isOfflineProvider.overrideWithValue(false),
          activityActionsProvider.overrideWith(
            (ref) => _FakeActions(ref)..let(actions.add),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.darkTheme,
          routerConfig: router,
        ),
      ),
    );
    router.push(start);
    await tester.pumpAndSettle();
    return actions;
  }

  testWidgets('lists each unshared run', (tester) async {
    await pump(tester, runs: [_run]);
    expect(find.text('Not shared'), findsOneWidget);
    expect(find.textContaining('5.20 km', findRichText: true), findsOneWidget);
    expect(find.byType(RouteSparkline), findsOneWidget);
  });

  testWidgets('says so when there is nothing to post', (tester) async {
    await pump(tester, runs: const []);
    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('the editor reopens the card as it was saved and posts it',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final actions = await pump(tester, runs: [_run]);
    await tester.tap(find.textContaining('5.20 km', findRichText: true));
    await tester.pumpAndSettle();

    final line = tester.widget<RouteSparkline>(
      find.byType(RouteSparkline).first,
    );
    expect(line.placement, _run.routePlacement);

    await tester.scrollUntilVisible(find.text('Post to feed'), 200);
    await tester.tap(find.text('Post to feed'));
    await tester.pumpAndSettle();

    final shared = actions.single.shared!;
    expect(shared.run.id, 'run-1');
    expect(shared.routePlacement, _run.routePlacement);
    expect(shared.showRouteMap, isFalse);
    expect(shared.keepExistingImage, isFalse);
    expect(shared.backgroundImagePath, isNull);
  });

  testWidgets('an editor opened by id finds its run in the list',
      (tester) async {
    await pump(tester, runs: [_run], start: '/not-shared/run-1');
    expect(find.text('Run'), findsOneWidget);
    expect(find.byType(RouteSparkline), findsWidgets);
  });
}
