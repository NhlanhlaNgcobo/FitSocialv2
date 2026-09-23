import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/features/main/domain/activity_kind.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/run_log_screen.dart';
import 'package:fitsocial_app/features/tracking/application/tracking_providers.dart';
import 'package:fitsocial_app/features/tracking/data/health_service.dart';
import 'package:fitsocial_app/features/tracking/data/run_import_service.dart';
import 'package:fitsocial_app/features/tracking/domain/imported_run.dart';

/// The "Fill from your health app" card on Log Run.
///
/// A tester finished a run tracked by Samsung Health, opened this screen and
/// found nothing from it — the background import files drafts on Create, and
/// only when it already had permission. This card is the explicit path: ask,
/// read, fill the form, and say why when there is nothing to fill it with.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool granted,
    List<HealthRunRecord> sessions = const [],
  }) async {
    final router = GoRouter(
      initialLocation: '/log-run',
      routes: [
        GoRoute(path: '/log-run', builder: (_, __) => const RunLogScreen()),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthServiceProvider.overrideWithValue(_FakeHealth(granted)),
          runImportServiceProvider.overrideWithValue(
            RunImportService(health: _FakeSource(sessions)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pull(WidgetTester tester) async {
    await tester.tap(find.text('Fill from your health app'));
    await tester.pumpAndSettle();
  }

  HealthRunRecord session({
    ActivityKind kind = ActivityKind.run,
    double? distanceMeters = 10010,
    Duration length = const Duration(minutes: 50, seconds: 25),
  }) {
    final startedAt = DateTime.now().subtract(const Duration(hours: 2));
    return HealthRunRecord(
      externalId: 'hc-1',
      startedAt: startedAt,
      endedAt: startedAt.add(length),
      distanceMeters: distanceMeters,
      sourceId: 'com.samsung.health',
      sourceName: 'Samsung Health',
      isTreadmill: false,
      activityKind: kind,
    );
  }

  testWidgets('fills both fields from the latest session', (tester) async {
    await pump(tester, granted: true, sessions: [session()]);
    await pull(tester);

    final distance = tester.widget<TextField>(find.byType(TextField).first);
    final duration = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(distance.controller!.text, '10.01');
    expect(duration.controller!.text, '50.42');

    // The form is complete, so the summary is up. The clock itself only shows
    // on the card preview, which waits for a photo; the confirmation below is
    // what carries the real seconds.
    expect(find.text('AVG PACE'), findsOneWidget);
    expect(find.text('Filled from Samsung Health'), findsWidgets);
    expect(find.textContaining('10.01 km in 50:25'), findsOneWidget);
  });

  testWidgets('a session with no distance fills the time and asks for the rest',
      (tester) async {
    await pump(
      tester,
      granted: true,
      sessions: [session(distanceMeters: null)],
    );
    await pull(tester);

    final distance = tester.widget<TextField>(find.byType(TextField).first);
    final duration = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(distance.controller!.text, isEmpty);
    expect(duration.controller!.text, '50.42');
    expect(find.textContaining('no distance recorded'), findsOneWidget);
  });

  testWidgets('the session decides the activity', (tester) async {
    await pump(tester,
        granted: true, sessions: [session(kind: ActivityKind.hike)]);
    expect(find.text('Log Run'), findsOneWidget);

    await pull(tester);

    expect(find.text('Log Hike'), findsOneWidget);
  });

  testWidgets('says so when access is refused', (tester) async {
    await pump(tester, granted: false, sessions: [session()]);
    await pull(tester);

    expect(find.textContaining('needs permission'), findsOneWidget);
    final distance = tester.widget<TextField>(find.byType(TextField).first);
    expect(distance.controller!.text, isEmpty);
  });

  testWidgets('says so when the store is empty, and blames the sync lag',
      (tester) async {
    await pump(tester, granted: true);
    await pull(tester);

    expect(
        find.textContaining('Nothing from the last two days'), findsOneWidget);
    expect(find.textContaining('few minutes'), findsOneWidget);
  });
}

/// Only the one call the screen makes. The real thing is a platform channel.
class _FakeHealth extends HealthService {
  _FakeHealth(this.granted);

  final bool granted;

  @override
  Future<bool> requestPermissions() async => granted;
}

class _FakeSource implements RunSessionSource {
  _FakeSource(this.sessions);

  final List<HealthRunRecord> sessions;

  @override
  Future<List<HealthRunRecord>> readRunSessions({
    required DateTime start,
    required DateTime end,
  }) async =>
      sessions;

  @override
  Future<double?> readDistanceMeters({
    required DateTime start,
    required DateTime end,
    required String sourceId,
  }) async =>
      null;

  @override
  Future<HeartRateSummary?> readHeartRateSummary({
    required DateTime start,
    required DateTime end,
  }) async =>
      null;
}
