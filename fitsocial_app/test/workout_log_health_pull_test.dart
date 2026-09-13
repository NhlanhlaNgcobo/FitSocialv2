import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/workout_log_screen.dart';
import 'package:fitsocial_app/features/tracking/application/tracking_providers.dart';
import 'package:fitsocial_app/features/tracking/data/health_service.dart';
import 'package:fitsocial_app/features/tracking/data/workout_prefill_service.dart';
import 'package:fitsocial_app/features/tracking/domain/imported_workout.dart';

/// "Fill from your health app" on the Training Log.
///
/// The gym-side twin of the run log's card: name, time and calories come from
/// the watch; the exercises stay the runner's to add.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool granted,
    List<HealthWorkoutRecord> sessions = const [],
    int? activeCalories,
    List<RecentWorkout> recents = const [],
  }) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(_StubRepository(recents)),
          healthServiceProvider.overrideWithValue(_FakeHealth(granted)),
          workoutPrefillServiceProvider.overrideWithValue(
            WorkoutPrefillService(
              health: _FakeSource(sessions, activeCalories: activeCalories),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const WorkoutLogScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pull(WidgetTester tester) async {
    await tester.tap(find.text('Fill from your health app'));
    await tester.pumpAndSettle();
  }

  TextEditingController field(WidgetTester tester, int index) =>
      tester.widget<TextField>(find.byType(TextField).at(index)).controller!;

  HealthWorkoutRecord session({
    String name = 'Strength training',
    int? calories = 320,
    Duration length = const Duration(minutes: 44, seconds: 40),
    DateTime? startedAt,
  }) {
    final start =
        startedAt ?? DateTime.now().subtract(const Duration(hours: 3));
    return HealthWorkoutRecord(
      externalId: 'hc-w-1',
      startedAt: start,
      endedAt: start.add(length),
      activityName: name,
      calories: calories,
      sourceId: 'com.samsung.health',
      sourceName: 'Samsung Health',
    );
  }

  testWidgets('fills the name, duration and calories', (tester) async {
    await pump(tester, granted: true, sessions: [session()]);
    await pull(tester);

    // Title, then the two metric wells, in the order the screen lays out.
    expect(field(tester, 0).text, 'Strength training');
    expect(field(tester, 1).text, '45');
    expect(field(tester, 2).text, '320');
    expect(find.text('Filled from Samsung Health'), findsWidgets);
    expect(find.textContaining('45 min · 320 kcal'), findsOneWidget);
  });

  testWidgets('moves the date chip to when the session happened',
      (tester) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 18, 20);
    await pump(tester,
        granted: true, sessions: [session(startedAt: yesterday)]);
    expect(find.textContaining('· 18:20'), findsNothing);

    await pull(tester);

    // The card says when, and the chip at the top now agrees with it: the
    // record will carry that start, not the moment the form was opened.
    expect(find.textContaining('Yesterday 18:20'), findsOneWidget);
    expect(find.textContaining('· 18:20'), findsOneWidget);
  });

  testWidgets('leaves calories blank when nothing recorded any',
      (tester) async {
    await pump(tester, granted: true, sessions: [session(calories: null)]);
    await pull(tester);

    expect(field(tester, 1).text, '45');
    expect(field(tester, 2).text, isEmpty);
  });

  testWidgets('falls back to the energy records for calories', (tester) async {
    await pump(
      tester,
      granted: true,
      sessions: [session(calories: null)],
      activeCalories: 287,
    );
    await pull(tester);

    expect(field(tester, 2).text, '287');
  });

  testWidgets('keeps exercises a repeat chip already loaded', (tester) async {
    const squat = ExerciseEntry(name: 'Squat', sets: 5, reps: 5, weightKg: 100);
    await pump(
      tester,
      granted: true,
      sessions: [session()],
      recents: [
        RecentWorkout(
          title: 'Leg day',
          durationMinutes: 60,
          calories: 500,
          exercises: [squat],
          loggedAt: DateTime(2026, 9, 10, 18),
        ),
      ],
    );
    await tester.tap(find.text('Leg day'));
    await tester.pumpAndSettle();
    expect(find.text('Squat'), findsOneWidget);

    await pull(tester);

    // The store knows nothing about what was lifted, so the table is not
    // its to clear. The headline figures are, and they change.
    expect(find.text('Squat'), findsOneWidget);
    expect(field(tester, 0).text, 'Strength training');
    expect(field(tester, 1).text, '45');
  });

  testWidgets('says so when access is refused', (tester) async {
    await pump(tester, granted: false, sessions: [session()]);
    await pull(tester);

    expect(find.textContaining('needs permission'), findsOneWidget);
    expect(field(tester, 0).text, isEmpty);
  });

  testWidgets('says so when the store is empty', (tester) async {
    await pump(tester, granted: true);
    await pull(tester);

    expect(
        find.textContaining('Nothing from the last two days'), findsOneWidget);
  });
}

class _StubRepository extends UnconfiguredContentRepository {
  const _StubRepository(this.recents);

  final List<RecentWorkout> recents;

  @override
  Future<List<RecentWorkout>> getRecentWorkouts({int limit = 6}) async =>
      recents;
}

/// Only the one call the screen makes. The real thing is a platform channel.
class _FakeHealth extends HealthService {
  _FakeHealth(this.granted);

  final bool granted;

  @override
  Future<bool> requestPermissions() async => granted;
}

class _FakeSource implements WorkoutSessionSource {
  _FakeSource(this.sessions, {this.activeCalories});

  final List<HealthWorkoutRecord> sessions;
  final int? activeCalories;

  @override
  Future<List<HealthWorkoutRecord>> readWorkoutSessions({
    required DateTime start,
    required DateTime end,
  }) async =>
      sessions;

  @override
  Future<int?> readActiveCalories({
    required DateTime start,
    required DateTime end,
    required String sourceId,
  }) async =>
      activeCalories;
}
